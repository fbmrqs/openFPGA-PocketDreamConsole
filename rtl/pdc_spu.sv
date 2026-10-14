// PCM, ADPCM and envelope semantics follow the vendored SPG200 reference (ISC).
module pdc_spu #(parameter logic ADDRESS_LOOKAHEAD = 0) (
    input logic clk, reset,
    input logic register_write,
    input logic [13:0] register_address, register_read_lookahead,
    input logic [15:0] register_data,
    output logic [15:0] register_read_data,
    input logic advance,
    input logic [7:0] cycles,
    output logic busy,
    output logic channel_irq, beat_irq,
    output logic memory_request,
    output logic [21:0] memory_address,
    input logic memory_ack,
    input logic [15:0] memory_data,
    output logic sample_valid,
    output logic signed [15:0] sample_left, sample_right
);
    logic signed [15:0] final_left, final_right;
    logic [15:0] c [0:15][0:11];
    logic [15:0] p [0:15][0:7];
    logic [15:0] g [0:24];
    logic [21:0] wave_address [0:15], loop_address [0:15], envelope_address [0:15];
    logic [18:0] phase [0:15], phase_acc [0:15], target_phase [0:15];
    logic [3:0] wave_shift [0:15], envelope_clock [0:15];
    logic [6:0] adpcm_index [0:15];
    logic signed [15:0] adpcm_last [0:15];
    logic [11:0] current_beat;
    integer sample_clock, env_clock;
    logic [3:0] ramp_clock;
    logic [3:0] ramp_voice;
    logic [31:0] env_counter, ramp_counter;
    logic env_pending, ramp_pending;
    (* preserve *) logic [15:0] envelope_due, pitch_due, ramp_due;
    (* preserve, maxfan = 64 *) logic [4:0] channel;
    logic sample_pending;
    logic [16:0] channel_position;
    (* preserve *) logic [15:0] pitch_changed;
    wire current_pitch_changed=|(channel_position[15:0] & pitch_changed);
    wire current_channel_enabled=|(channel_position[15:0] & channel_enabled);
    wire current_envelope_enabled=|(channel_position[15:0] & envelope_enabled);
    wire current_ramp_enabled=|(channel_position[15:0] & ramp_enabled);
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (!reset && state[$clog2(PITCH)] &&
            (pitch_start!=phase[channel[3:0]] || pitch_target!=target_phase[channel[3:0]] ||
             current_pitch_changed!=(phase[channel[3:0]]!=target_phase[channel[3:0]])))
            $fatal(1,"Prepared pitch operands do not match selected channel");
    always_ff @(posedge clk)
        if (!reset && busy && channel_position!=(17'b1<<channel))
            $fatal(1,"Sound channel selector and register index diverged");
`endif
    logic channel_clear, channel_step, channel_jump;
    // Keep late eligibility decisions out of the counter carry chain.
    (* keep *) wire [4:0] incremented_channel=channel+5'd1;
    logic [4:0] next_enabled_channel;
    logic [16:0] next_enabled_position;
    always_comb begin
        next_enabled_channel=5'd16;next_enabled_position=17'h10000;
        for (int voice=15;voice>=0;voice--)
            if (channel_enabled[voice] && 5'(voice)>channel) begin
                next_enabled_channel=5'(voice);next_enabled_position=17'b1<<voice;
            end
    end
    task automatic skip_disabled_channels;
        channel_jump=1;channel_position<=next_enabled_position;
    endtask
    task automatic reset_channel;
        channel_clear=1;channel_position<=17'b1;
    endtask
    task automatic advance_channel;
        channel_step=1;channel_position<=channel_position<<1;
    endtask
    (* preserve, dont_retime *) logic [15:0] channel_enabled;
    always_ff @(posedge clk) channel_enabled<=g[0] & ~g[11];
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (!reset && (state[$clog2(CHANNEL)] || state[$clog2(ENVELOPE)]) && !channel_position[16] &&
            current_channel_enabled!=(g[0][channel[3:0]] && !g[11][channel[3:0]]))
            $fatal(1,"Prepared sound eligibility differs from consumed channel");
`endif
    wire [15:0] envelope_enabled=channel_enabled & ~g[21] & ~g[10] & envelope_due;
    wire [15:0] ramp_enabled=channel_enabled & g[10] & ramp_due;
    typedef enum logic [38:0] {
        IDLE = 39'd1 << 0,
        CHANNEL = 39'd1 << 1,
        CHANNEL_PHASE = 39'd1 << 2,
        FETCH = 39'd1 << 3,
        DECODE = 39'd1 << 4,
        PCM_COMMIT = 39'd1 << 5,
        ADPCM_ERROR = 39'd1 << 6,
        ADPCM_MAGNITUDE = 39'd1 << 7,
        ADPCM_ACCUMULATE = 39'd1 << 8,
        ADPCM_CLAMP = 39'd1 << 9,
        WAVE_ADVANCE = 39'd1 << 10,
        MIX = 39'd1 << 11,
        MIX_PRODUCT = 39'd1 << 12,
        BLEND = 39'd1 << 13,
        ENVELOPE_SCALE = 39'd1 << 14,
        PAN_SCALE = 39'd1 << 15,
        OUTPUT_SCALE = 39'd1 << 17,
        OUTPUT_OFFSET = 39'd1 << 18,
        GAIN_INPUT = 39'd1 << 19,
        GAIN_PRODUCT = 39'd1 << 20,
        SAMPLE_DONE = 39'd1 << 21,
        ENVELOPE = 39'd1 << 22,
        ENV_DELAY = 39'd1 << 23,
        ENV_STEP = 39'd1 << 24,
        ENV_COMMIT = 39'd1 << 25,
        ENV_ROUTE = 39'd1 << 26,
        ENV_REPEAT = 39'd1 << 27,
        ENV_WORD0 = 39'd1 << 28,
        ENV_WORD1 = 39'd1 << 29,
        ENV_WORD2 = 39'd1 << 30,
        ENV_RELOAD = 39'd1 << 31,
        PITCH = 39'd1 << 32,
        PITCH_ADD = 39'd1 << 33,
        PITCH_COMMIT = 39'd1 << 34,
        RAMP = 39'd1 << 35,
        RAMP_STEP = 39'd1 << 36,
        RAMP_COMMIT = 39'd1 << 37,
        DONE = 39'd1 << 38
    } state_t;
    state_t state, resume_state;
    logic [15:0] fetched_word;
    (* preserve *) logic [15:0] decoded_pcm;
    logic [21:0] env_read_address;
    logic env_repeat, encoding_adpcm, encoding_byte, env_loaded;
    logic [6:0] envelope_repeat_count;
    logic signed [31:0] left_mix, right_mix;
    logic [19:0] next_phase;
    logic [21:0] advancing_wave;
    logic [21:0] envelope_base, prepared_envelope_address;
    logic [8:0] envelope_offset;
    (* preserve *) logic [21:0] wave_base, loop_base;
    (* preserve *) logic [15:0] wave_mode;
    (* preserve *) logic [3:0] decoded_shift;
    (* preserve, dont_retime *) logic [7:0] decoded_byte;
    logic decoded_word_end;
    always_ff @(posedge clk) begin
        decoded_byte<=8'(memory_data>>decoded_shift);
        decoded_word_end<=memory_data==16'hffff;
    end
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (!reset && state[$clog2(DECODE)] &&
            (decoded_byte!=8'(fetched_word>>decoded_shift) || decoded_word_end!=(fetched_word==16'hffff)))
            $fatal(1,"Prepared sound byte differs from the fetched wave word");
`endif
    (* preserve, dont_merge *) logic [15:0] gain_low [0:1], gain_volume [0:3];
    (* preserve, dont_merge *) logic [6:0] gain_high [0:1];
    logic [31:0] gain_low_product [0:1];
    logic [6:0] gain_high_product [0:1];
    logic [4:0] advancing_shift;
    logic [3:0] adpcm_code;
    logic [15:0] adpcm_step, error_low, error_high, error_magnitude;
    logic signed [15:0] previous_adpcm;
    logic [6:0] previous_adpcm_index;
    logic signed [17:0] adpcm_sum;
    wire signed [8:0] adjusted_adpcm_index = $signed({2'b0,previous_adpcm_index})+9'(STEP_ADJUST[adpcm_code[2:0]]);
    (* preserve, dont_retime *) logic signed [8:0] adpcm_index_step;
    (* preserve, dont_retime *) logic [6:0] next_adpcm_index;
    (* preserve, dont_retime *) logic ramp_active;
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk) begin
        if (!reset && state[$clog2(ADPCM_ACCUMULATE)] &&
            next_adpcm_index!=(adjusted_adpcm_index<0 ? 7'd0 : adjusted_adpcm_index>88 ? 7'd88 : adjusted_adpcm_index[6:0]))
            $fatal(1,"Prepared ADPCM index differs from decoded sample");
        if (!reset && state[$clog2(RAMP_STEP)] &&
            ramp_active!=(channel_enabled[ramp_voice] && g[10][ramp_voice] && ramp_due[ramp_voice]))
            $fatal(1,"Prepared ramp eligibility differs from selected voice");
    end
`endif
    logic [35:0] previous_product, current_product;
    logic [15:0] mix_previous, mix_current;
    logic [18:0] mix_phase;
    logic [19:0] mix_previous_weight;
    logic [6:0] mix_amplitude, mix_pan, mix_volume;
    logic [18:0] pitch_start, pitch_target;
    logic [11:0] pitch_step;
    logic pitch_down;
    logic signed [20:0] pitch_candidate;
    logic [13:0] left_gain, right_gain;
    logic signed [30:0] left_product, right_product;
    logic signed [15:0] mixed_sample;
    integer i,j,index,code,sample,pan_left,pan_right,amount;
    integer scaled_left, scaled_right;
    logic [15:0] old_flags;
    logic [7:0] envelope_delay;
    (* preserve, dont_retime *) logic [7:0] channel_envelope_delay [0:15];
    (* preserve, dont_retime *) logic [15:0] channel_envelope_step;
    genvar envelope_voice;
    generate for (envelope_voice=0;envelope_voice<16;envelope_voice++) begin : envelope_delay_capture
        always_ff @(posedge clk) begin
            channel_envelope_delay[envelope_voice]<=c[envelope_voice][5][15:8]==0 ? 8'd0 : c[envelope_voice][5][15:8]-8'd1;
            channel_envelope_step[envelope_voice]<=c[envelope_voice][5][15:8]<=8'd1;
        end
    end endgenerate
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (!reset && state[$clog2(ENV_DELAY)] &&
            (channel_envelope_delay[channel[3:0]]!=(c[channel[3:0]][5][15:8]==0 ? 8'd0 : c[channel[3:0]][5][15:8]-8'd1) ||
             channel_envelope_step[channel[3:0]]!=(c[channel[3:0]][5][15:8]<=8'd1)))
            $fatal(1,"Prepared envelope delay differs from selected channel");
`endif
    logic [6:0] envelope_amplitude, repeat_remaining;
    (* preserve *) logic [6:0] envelope_source, envelope_step, envelope_target;
    logic envelope_down;
    (* preserve, dont_retime *) logic envelope_target_reached, envelope_shutdown;
    logic signed [8:0] envelope_candidate;
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (!reset && state[$clog2(ENV_ROUTE)] &&
            (envelope_target_reached!=(c[channel[3:0]][5][6:0]==c[channel[3:0]][4][14:8]) ||
             envelope_shutdown!=(c[channel[3:0]][4][7] && c[channel[3:0]][5][6:0]==0)))
            $fatal(1,"Prepared envelope route differs from committed channel registers");
`endif
    localparam integer STEP_SIZE [0:88] = '{
        7,8,9,10,11,12,13,14,16,17,19,21,23,25,28,31,34,37,41,45,50,55,60,66,73,80,
        88,97,107,118,130,143,157,173,190,209,230,253,279,307,337,371,408,449,494,544,598,
        658,724,796,876,963,1060,1166,1282,1411,1552,1707,1878,2066,2272,2499,2749,3024,
        3327,3660,4026,4428,4871,5358,5894,6484,7132,7845,8630,9493,10442,11487,12635,
        13899,15289,16818,18500,20350,22385,24623,27086,29794,32767};
    localparam integer STEP_ADJUST [0:7] = '{-1,-1,-1,-1,2,4,6,8};
    function automatic logic counter_expired(input logic [31:0] value,input logic [7:0] debit);
        return (value[31] && !(value[31:8]==24'h800000 && value[7:0]<debit)) ||
            (!value[31] && value[31:8]==0 && value[7:0]<=debit);
    endfunction
    function automatic logic [23:0] counter_upper_step(input logic [23:0] value,input logic down,input logic twice);
        if (down) return {12'(value[23:12]-12'(~|value[11:0])),12'(value[11:0]-12'd1)};
        return {12'(value[23:12]+12'(twice ? &value[11:1] : &value[11:0])),
            12'(value[11:0]+(twice ? 12'd2 : 12'd1))};
    endfunction
    function automatic logic [31:0] counter_advance(input logic [31:0] value,input logic [7:0] debit,input logic [8:0] period);
        logic [8:0] low;
        logic [9:0] reloaded_low;
        logic [23:0] upper,reloaded_upper;
        low={1'b0,value[7:0]}-{1'b0,debit};
        reloaded_low={2'b0,value[7:0]}+{2'b0,period[7:0]}-{2'b0,debit};
        upper=low[8] ? counter_upper_step(value[31:8],1,0) : value[31:8];
        if (period[8]) reloaded_upper=reloaded_low[9] ? value[31:8] :
            counter_upper_step(value[31:8],0,reloaded_low[8]);
        else reloaded_upper=reloaded_low[9] ? counter_upper_step(value[31:8],1,0) :
            reloaded_low[8] ? counter_upper_step(value[31:8],0,0) : value[31:8];
        return counter_expired(value,debit) ? {reloaded_upper,reloaded_low[7:0]} : {upper,low[7:0]};
    endfunction

    function automatic logic divided(input logic [31:0] counter,input integer divide);
        case (divide)
            0: return 1;
            1: return ~|counter[0:0];
            2: return ~|counter[1:0];
            3: return ~|counter[2:0];
            4: return ~|counter[3:0];
            5: return ~|counter[4:0];
            6: return ~|counter[5:0];
            7: return ~|counter[6:0];
            8: return ~|counter[7:0];
            9: return ~|counter[8:0];
            10: return ~|counter[9:0];
            11: return ~|counter[10:0];
            12: return ~|counter[11:0];
            13: return ~|counter[12:0];
            14: return ~|counter[13:0];
            default: return 0;
        endcase
    endfunction
    function automatic logic envelope_divided(input logic [31:0] count,input logic [3:0] rate);
        case(rate)
            4'd0: return ~|count[1:0];
            4'd1: return ~|count[2:0];
            4'd2: return ~|count[3:0];
            4'd3: return ~|count[4:0];
            4'd4: return ~|count[5:0];
            4'd5: return ~|count[6:0];
            4'd6: return ~|count[7:0];
            4'd7: return ~|count[8:0];
            4'd8: return ~|count[9:0];
            4'd9: return ~|count[10:0];
            4'd10: return ~|count[11:0];
            4'd11: return ~|count[12:0];
            4'd12: return ~|count[12:0];
            4'd13: return ~|count[12:0];
            4'd14: return ~|count[12:0];
            4'd15: return ~|count[12:0];
        endcase
    endfunction
    function automatic logic pitch_divided(input logic [31:0] count,input logic [2:0] rate);
        case(rate)
            3'd0: return ~|count[2:0];
            3'd1: return ~|count[3:0];
            3'd2: return ~|count[4:0];
            3'd3: return ~|count[5:0];
            3'd4: return ~|count[6:0];
            3'd5: return ~|count[7:0];
            3'd6: return ~|count[8:0];
            3'd7: return ~|count[9:0];
        endcase
    endfunction
    function automatic logic ramp_divided(input logic [31:0] count,input logic [2:0] rate);
        case(rate)
            3'd0: return ~|count[1:0];
            3'd1: return ~|count[3:0];
            3'd2: return ~|count[5:0];
            3'd3: return ~|count[7:0];
            3'd4: return ~|count[9:0];
            3'd5: return ~|count[11:0];
            3'd6: return ~|count[12:0];
            3'd7: return ~|count[12:0];
        endcase
    endfunction
    task automatic start_channel(input integer ch);
        wave_shift[ch] <= 0; adpcm_index[ch] <= 0; adpcm_last[ch] <= 0;
        if (!g[21][ch]) c[ch][5][15:8] <= c[ch][6][7:0];
    endtask
    task automatic stop_channel(input integer ch);
        g[11][ch] = 1; g[22][ch] = 0; g[10][ch] = 0; c[ch][1][15] <= 0;
    endtask
    task automatic update_beat_irq;
        beat_irq = (g[5][15] && g[5][14]) || g[23] != 0;
    endtask
    task automatic fetch(input logic [21:0] addr, input state_t next_state);
        memory_address <= addr; memory_request <= 1; resume_state<= next_state; state<= FETCH;
    endtask
    (* preserve, dont_retime *) logic [15:0] channel_read [0:15], global_read;
    function automatic logic [15:0] read_channel(input integer voice, input logic pitch, input logic [3:0] index);
        read_channel=0;
        if (!pitch) case(index)
            0:read_channel=wave_address[voice][15:0];
            1:read_channel=c[voice][1] | {4'b0,loop_address[voice][21:16],wave_address[voice][21:16]};
            2:read_channel=loop_address[voice][15:0];
            7:read_channel=c[voice][7] | {10'b0,envelope_address[voice][21:16]};
            8:read_channel=envelope_address[voice][15:0];
            3,4,5,6,9,10,11:read_channel=c[voice][index];
            default:begin end
        endcase
        else case(index)
            0:read_channel={13'b0,phase[voice][18:16]};
            1:read_channel={13'b0,phase_acc[voice][18:16]};
            2:read_channel={13'b0,target_phase[voice][18:16]};
            4:read_channel=phase[voice][15:0];
            5:read_channel=phase_acc[voice][15:0];
            6:read_channel=target_phase[voice][15:0];
            3,7:read_channel=p[voice][index[2:0]];
            default:begin end
        endcase
    endfunction
    function automatic logic [15:0] read_global(input logic [4:0] index);
        read_global=0;
        if(index==15)read_global=g[0] & ~g[11];
        else if(index>=6 && index<=9)begin
            for(int part=0;part<4;part++)read_global[part*4+:4]=envelope_clock[(int'(index)-6)*4+part];
        end else if(index<=24 && index!=16 && index!=17 && index!=14)read_global=g[index];
    endfunction
    genvar read_voice;
    generate for (read_voice=0;read_voice<16;read_voice++) begin : read_capture
        if (ADDRESS_LOOKAHEAD) begin : prepared
            (* preserve, dont_merge, dont_retime *) logic [11:0] wave_select;
            (* preserve, dont_merge, dont_retime *) logic [7:0] pitch_select;
            logic [15:0] selected_word;
            always_comb begin
                selected_word=0;
                for(int word_index=0;word_index<12;word_index++)
                    selected_word|=read_channel(read_voice,1'b0,4'(word_index)) & {16{wave_select[word_index]}};
                for(int word_index=0;word_index<8;word_index++)
                    selected_word|=read_channel(read_voice,1'b1,4'(word_index)) & {16{pitch_select[word_index]}};
            end
            always_ff @(posedge clk) begin
                for(int word_index=0;word_index<12;word_index++)
                    wave_select[word_index]<=!register_read_lookahead[9] && register_read_lookahead[3:0]==4'(word_index);
                for(int word_index=0;word_index<8;word_index++)
                    pitch_select[word_index]<=register_read_lookahead[9] && register_read_lookahead[3:0]==4'(word_index);
                channel_read[read_voice]<=selected_word;
            end
`ifdef PDC_VERIFY_MMIO_CYCLES
            always_ff @(posedge clk) if (!reset &&
                selected_word!=read_channel(read_voice,register_address[9],register_address[3:0]))
                $fatal(1,"Prepared sound field differs from the current register read");
`endif
        end else begin : direct
            always_ff @(posedge clk)
                channel_read[read_voice]<=read_channel(read_voice,register_address[9],register_address[3:0]);
        end
    end endgenerate
    (* preserve, dont_retime *) logic [4:0] global_read_index;
    always_ff @(posedge clk) begin
        global_read_index<=register_read_lookahead[4:0];
        global_read<=read_global(ADDRESS_LOOKAHEAD ? global_read_index : register_address[4:0]);
    end
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (ADDRESS_LOOKAHEAD && !reset && global_read_index!=register_address[4:0])
            $fatal(1,"Global sound read field differs from the registered bus address");
`endif
    always_comb begin
        register_read_data=0;
        if ((register_address>=14'h3000 && register_address<14'h3100) ||
            (register_address>=14'h3200 && register_address<14'h3300))
            register_read_data=channel_read[register_address[7:4]];
        else if(register_address>=14'h3400 && register_address<=14'h3418)register_read_data=global_read;
        channel_irq=g[3]!=0;
    end
    // Output gain keeps only product bits 22:7, including signed wrap.
    // Independent input/output registers can pack into the DSP blocks.
    always_ff @(posedge clk) begin
        gain_low[0]<=16'(scaled_left);gain_low[1]<=16'(scaled_right);
        gain_high[0]<=7'(scaled_left>>>16);gain_high[1]<=7'(scaled_right>>>16);
        for(int part=0;part<4;part++)gain_volume[part]<=g[1];
        for(int side=0;side<2;side++)begin
            gain_low_product[side]<=gain_low[side]*gain_volume[side*2];
            gain_high_product[side]<=7'(gain_high[side]*gain_volume[side*2+1][6:0]);
        end
    end
    always @(posedge clk) begin
        channel_clear=0;channel_step=0;channel_jump=0;
        // synthesis translate_off
        if (!reset && register_write && (busy || advance))
            $fatal(1,"SPU register writes require an idle peripheral");
        // synthesis translate_on
        sample_valid <= 0;
        if (reset) begin
            decoded_pcm<=0;
            envelope_source<=0;envelope_step<=0;envelope_target<=0;envelope_down<=0;envelope_candidate<=0;
            envelope_target_reached<=0;envelope_shutdown<=0;
            pitch_start<=0;pitch_target<=0;pitch_step<=0;pitch_down<=0;pitch_candidate<=0;
            mix_previous<=0;mix_current<=0;mix_phase<=0;mix_previous_weight<=0;mix_amplitude<=0;mix_pan<=0;mix_volume<=0;
            for (i=0;i<16;i=i+1) begin
                for (j=0;j<12;j=j+1) c[i][j] <= 0;
                for (j=0;j<8;j=j+1) p[i][j] <= 0;
                c[i][9] <= 16'h8000; c[i][11] <= 16'h8000;
                wave_address[i] <= 0; loop_address[i] <= 0; envelope_address[i] <= 0;
                phase[i] <= 0; phase_acc[i] <= 0; target_phase[i] <= 0;
                wave_shift[i] <= 0; envelope_clock[i] <= 0; adpcm_index[i] <= 0; adpcm_last[i] <= 0;
            end
            for (i=0;i<25;i=i+1) g[i] = 0;
            g[16] = 16'h8000; g[17] = 16'h8000; g[18] = 16'h8000; g[19] = 16'h8000;
            current_beat = 0; sample_clock = 96; env_clock = 384; ramp_clock = 4'd13;
            env_counter = 0; ramp_counter = 0; env_pending = 0; ramp_pending = 0; sample_pending=0;
            pitch_changed<=0;busy<= 0; beat_irq = 0; memory_request <= 0; memory_address <= 0; state<= IDLE; resume_state<= IDLE;
            sample_left <= 0; sample_right <= 0; final_left = 0; final_right = 0; reset_channel(); fetched_word = 0;
            ramp_voice<=0;
            env_read_address <= 0; env_repeat <= 0; encoding_adpcm = 0; encoding_byte = 0; env_loaded = 0; left_mix = 0; right_mix = 0;
            adpcm_code<=0;adpcm_step<=0;error_low<=0;error_high<=0;error_magnitude<=0;
            previous_adpcm<=0;previous_adpcm_index<=0;adpcm_sum<=0;
            adpcm_index_step<=0;next_adpcm_index<=0;ramp_active<=0;
        end else begin
            for (int voice=0;voice<16;voice++) pitch_changed[voice]<=phase[voice]!=target_phase[voice];
            if (state[$clog2(IDLE)]) begin
                for (int scan=0;scan<16;scan++) begin
                    envelope_due[scan]<=envelope_divided(~env_counter,envelope_clock[scan]);
                    pitch_due[scan]<=pitch_divided(~env_counter,p[scan][7][15:13]);
                    ramp_due[scan]<=ramp_divided(~ramp_counter,p[scan][3][2:0]);
                end
            end
            // Address preparation does not depend on whether a fetch is needed.
            envelope_base<=envelope_address[channel[3:0]];
            envelope_offset<=c[channel[3:0]][10][8:0];
            prepared_envelope_address<=envelope_base+22'(envelope_offset);
            pitch_start<=phase[channel[3:0]];pitch_target<=target_phase[channel[3:0]];
            pitch_step<=p[channel[3:0]][7][11:0];pitch_down<=p[channel[3:0]][7][12];
            if (state[$clog2(CHANNEL)]) begin
                wave_base<=wave_address[channel[3:0]];loop_base<=loop_address[channel[3:0]];
                wave_mode<=c[channel[3:0]][1];decoded_shift<=wave_shift[channel[3:0]];
            end
            if (state[$clog2(CHANNEL_PHASE)]) memory_address<=wave_base;
            if (state[$clog2(ENV_REPEAT)]) memory_address<=env_read_address;
            if (register_write) begin
                index = int'(register_address[7:4]);
                if (register_address >= 14'h3000 && register_address < 14'h3100) begin
                    case (register_address[3:0])
                        0: begin wave_address[index][15:0] <= register_data; wave_shift[index] <= 0; end
                        1: begin c[index][1] <= register_data & 16'hf000; wave_address[index][21:16] <= register_data[5:0]; loop_address[index][21:16] <= register_data[11:6]; end
                        2: loop_address[index][15:0] <= register_data;
                        3: c[index][3] <= register_data & 16'h7f7f;
                        4: c[index][4] <= register_data & 16'h7fff;
                        5: c[index][5] <= register_data & 16'hff7f;
                        7: begin c[index][7] <= register_data & 16'hffc0; envelope_address[index][21:16] <= register_data[5:0]; end
                        8: envelope_address[index][15:0] <= register_data;
                        6,9,10,11: c[index][register_address[3:0]] <= register_data;
                        default: begin end
                    endcase
                end else if (register_address >= 14'h3200 && register_address < 14'h3300) begin
                    case (register_address[3:0])
                        0: phase[index][18:16] <= register_data[2:0];
                        1: phase_acc[index][18:16] <= register_data[2:0];
                        2: target_phase[index][18:16] <= register_data[2:0];
                        3: p[index][3] <= register_data & 16'h7;
                        4: phase[index][15:0] <= register_data;
                        5: phase_acc[index][15:0] <= register_data;
                        6: target_phase[index][15:0] <= register_data;
                        7: p[index][7] <= register_data;
                        default: begin end
                    endcase
                end else case (register_address)
                    14'h3400: begin
                        old_flags = g[0]; g[0] = register_data;
                        for (i=0;i<16;i=i+1) if (old_flags[i]!=g[0][i] && !g[11][i]) begin
                            if (g[0][i]) start_channel(i); else stop_channel(i);
                        end
                    end
                    14'h3401: g[1] = register_data & 16'h7f;
                    14'h3402: g[2] = register_data;
                    14'h3403: g[3] = g[3] & ~register_data;
                    14'h3404: begin g[4] = register_data & 16'hfff; current_beat = register_data[11:0]; end
                    14'h3405: begin
                        old_flags = g[5]; g[5] = register_data; g[5][14] = old_flags[14] && !register_data[14]; update_beat_irq();
                    end
                    14'h3406,14'h3407,14'h3408,14'h3409: begin
                        for (i=0;i<4;i=i+1) envelope_clock[(int'(register_address)-32'h3406)*4+i] <= register_data[i*4 +: 4];
                    end
                    14'h340a: g[10] = register_data & g[0] & ~g[11];
                    14'h340b: begin
                        old_flags = g[11]; g[11] = g[11] & ~register_data;
                        for (i=0;i<16;i=i+1) if (old_flags[i]!=g[11][i] && g[0][i] && !g[11][i]) start_channel(i);
                    end
                    14'h340c: g[12] = register_data;
                    14'h340d: g[13] = (register_data & 16'h388) | (g[13] & 16'h20);
                    14'h3410: g[16] = register_data;
                    14'h3411: g[17] = register_data;
                    14'h3414: g[20] = register_data;
                    14'h3415: g[21] = register_data;
                    14'h3416: g[22] = register_data;
                    14'h3417: g[23] = g[23] & ~register_data;
                    14'h3418: g[24] = register_data;
                    default: begin end
                endcase
            end else unique case (1'b1)
                state[$clog2(IDLE)]: if (advance) begin
                    sample_pending=counter_expired(32'(sample_clock),cycles);
                    env_pending=counter_expired(32'(env_clock),cycles);ramp_pending=0;
                    sample_clock=32'(counter_advance(32'(sample_clock),cycles,9'd96));
                    env_clock=32'(counter_advance(32'(env_clock),cycles,9'd384));
                    if (env_pending) begin
                        env_counter = env_counter+32'd1;
                        ramp_clock = ramp_clock-4'd1;
                        if (ramp_clock <= 0) begin ramp_clock = ramp_clock+4'd13; ramp_counter = ramp_counter+32'd1; ramp_pending = 1; end
                    end
                    reset_channel(); busy<= 1;
                    if (sample_pending) state<= CHANNEL;
                    else if (env_pending) state<= ENVELOPE;
                    else begin busy<=0;state<=IDLE;end
                end
                state[$clog2(CHANNEL)]: begin
                    if (channel_position[0]) begin left_mix=0;right_mix=0;end
                    if (channel_position[16]) state<= OUTPUT_SCALE;
                    else if (!current_channel_enabled) skip_disabled_channels();
                    else begin
                        next_phase <= {1'b0,phase_acc[channel[3:0]]}+{1'b0,phase[channel[3:0]]};
                        state<=CHANNEL_PHASE;
                    end
                end
                state[$clog2(CHANNEL_PHASE)]: begin
                        phase_acc[channel[3:0]] <= next_phase[18:0];
                        mix_phase<=next_phase[18:0];
                        if (next_phase[19]) begin
                            if (g[2][channel[3:0]]) g[3][channel[3:0]] = 1;
                            c[channel[3:0]][9] <= c[channel[3:0]][11];
                            if (wave_mode[13:12] != 0) begin memory_request<=1;resume_state<=DECODE;state<=FETCH;end
                            else state<= MIX;
                        end else state<= MIX;
                end
                state[$clog2(FETCH)]: if (memory_ack) begin fetched_word = memory_data; memory_request <= 0; state<= resume_state; end
                state[$clog2(DECODE)]: begin
                    index = int'(channel[3:0]); encoding_adpcm = wave_mode[15]; encoding_byte = !wave_mode[14];
                    advancing_wave=wave_base;advancing_shift={1'b0,decoded_shift};
                    state<=WAVE_ADVANCE;
                    if ((wave_mode[15] || wave_mode[14]) ? decoded_word_end : decoded_byte==8'hff) begin
                        if (wave_mode[13:12] == 1) stop_channel(index);
                        else if (wave_mode[13:12] == 2) begin advancing_wave=loop_base;advancing_shift=0;c[index][1][15]<=0;end
                    end else if (wave_mode[15]) begin
                        code = int'(decoded_byte[3:0]);
                        adpcm_code<=4'(code);adpcm_step<=16'(STEP_SIZE[adpcm_index[index]]);
                        previous_adpcm<=adpcm_last[index];previous_adpcm_index<=adpcm_index[index];
                        state<=ADPCM_ERROR;
                    end else if (!wave_mode[14]) begin
                        code = int'(decoded_byte);
                        decoded_pcm <= {8'(code),8'(code)};state<=PCM_COMMIT;
                    end else begin decoded_pcm <= fetched_word;state<=PCM_COMMIT;end
                end
                state[$clog2(PCM_COMMIT)]: begin c[channel[3:0]][11]<=decoded_pcm;state<=WAVE_ADVANCE;end
                state[$clog2(ADPCM_ERROR)]: begin
                    adpcm_index_step<=adjusted_adpcm_index;
                    error_low<=(adpcm_step>>3)+(adpcm_code[0] ? adpcm_step>>2 : 16'd0);
                    error_high<=(adpcm_code[1] ? adpcm_step>>1 : 16'd0)+(adpcm_code[2] ? adpcm_step : 16'd0);
                    state<=ADPCM_MAGNITUDE;
                end
                state[$clog2(ADPCM_MAGNITUDE)]: begin
                    error_magnitude<=error_low+error_high;
                    next_adpcm_index<=adpcm_index_step<0 ? 7'd0 : adpcm_index_step>88 ? 7'd88 : adpcm_index_step[6:0];
                    state<=ADPCM_ACCUMULATE;
                end
                state[$clog2(ADPCM_ACCUMULATE)]: begin
                    adpcm_sum<=adpcm_code[3] ? 18'(previous_adpcm)-$signed({2'b0,error_magnitude}) :
                        18'(previous_adpcm)+$signed({2'b0,error_magnitude});
                    adpcm_index[channel[3:0]]<=next_adpcm_index;
                    state<=ADPCM_CLAMP;
                end
                state[$clog2(ADPCM_CLAMP)]: begin
                    sample=adpcm_sum>18'sd32767 ? 32767 : adpcm_sum < -18'sd32768 ? -32768 : int'(adpcm_sum);
                    adpcm_last[channel[3:0]]<=16'(sample);c[channel[3:0]][11]<=16'(sample)^16'h8000;
                    state<=WAVE_ADVANCE;
                end
                state[$clog2(WAVE_ADVANCE)]: begin
                    index=int'(channel[3:0]);
                    advancing_shift=encoding_adpcm ? advancing_shift+5'd4 : encoding_byte ? advancing_shift+5'd8 : 5'd16;
                    wave_shift[index]<=advancing_shift[4] ? 4'd0 : advancing_shift[3:0];
                    wave_address[index]<={6'(advancing_wave[21:16]+6'(advancing_shift[4] && &advancing_wave[15:0])),
                        8'(advancing_wave[15:8]+8'(advancing_shift[4] && &advancing_wave[7:0])),
                        8'(advancing_wave[7:0]+8'(advancing_shift[4]))};
                    state<=MIX;
                end
                state[$clog2(MIX)]: begin
                    index = int'(channel[3:0]);
                    mix_previous<=c[index][9];mix_current<=c[index][11];
                    mix_previous_weight<=20'h80000-{1'b0,mix_phase};
                    mix_amplitude<=c[index][5][6:0];mix_pan<=c[index][3][14:8];mix_volume<=c[index][3][6:0];
                    state<=MIX_PRODUCT;
                end
                state[$clog2(MIX_PRODUCT)]: begin
                    previous_product<=36'(mix_previous)*36'(mix_previous_weight);
                    current_product<=36'(mix_current)*36'(mix_phase);
                    state<=BLEND;
                end
                state[$clog2(BLEND)]: begin
                    mixed_sample = 16'(int'(previous_product[34:19])+int'(current_product[34:19])-32768);
                    state<=ENVELOPE_SCALE;
                end
                state[$clog2(ENVELOPE_SCALE)]: begin
                    index=int'(channel[3:0]);
                    mixed_sample = 16'((23'(mixed_sample)*$signed({1'b0,mix_amplitude})) >>> 7);
                    pan_left = mix_pan<=64 ? 127 : int'(7'(8'd0-{mix_pan,1'b0}));
                    pan_right = mix_pan>=64 ? 127 : int'({mix_pan[5:0],1'b0});
                    left_gain=14'(pan_left*int'(mix_volume));
                    right_gain=14'(pan_right*int'(mix_volume));
                    state<=PAN_SCALE;
                end
                state[$clog2(PAN_SCALE)]: begin
                    left_product=31'(mixed_sample)*$signed({1'b0,left_gain});
                    right_product=31'(mixed_sample)*$signed({1'b0,right_gain});
                    left_mix = left_mix+32'(left_product>>>14);
                    right_mix = right_mix+32'(right_product>>>14);
                    advance_channel(); state<= CHANNEL;
                end
                state[$clog2(OUTPUT_SCALE)]: begin
                    scaled_left = left_mix >>> (4-int'(g[13][7:6])); scaled_right = right_mix >>> (4-int'(g[13][7:6]));
                    state<=OUTPUT_OFFSET;
                end
                state[$clog2(OUTPUT_OFFSET)]: begin
                    scaled_left=scaled_left+32'($signed(g[16]^16'h8000));
                    scaled_right=scaled_right+32'($signed(g[17]^16'h8000));
                    state<=GAIN_INPUT;
                end
                state[$clog2(GAIN_INPUT)]: state<=GAIN_PRODUCT;
                state[$clog2(GAIN_PRODUCT)]: state<=SAMPLE_DONE;
                state[$clog2(SAMPLE_DONE)]: begin
                    final_left={7'(gain_low_product[0][22:16]+gain_high_product[0]),gain_low_product[0][15:7]};
                    final_right={7'(gain_low_product[1][22:16]+gain_high_product[1]),gain_low_product[1][15:7]};
                    sample_left <= final_left; sample_right <= final_right;
                    g[18] = final_left ^ 16'h8000; g[19] = final_right ^ 16'h8000; sample_valid <= 1;
                    reset_channel(); state<= env_pending ? ENVELOPE : DONE;
                end
                state[$clog2(ENVELOPE)]: if (channel_position[16]) begin reset_channel(); state<= ramp_pending ? RAMP : DONE; end
                    else begin
                        index = int'(channel[3:0]); env_loaded = 0;
                        if (!current_channel_enabled) begin skip_disabled_channels(); end
                        else if (current_envelope_enabled) state<= ENV_DELAY;
                        else state<= PITCH;
                    end
                state[$clog2(ENV_DELAY)]: begin
                    index=int'(channel[3:0]);
                    envelope_source<=c[index][5][6:0];envelope_step<=c[index][4][6:0];
                    envelope_target<=c[index][4][14:8];envelope_down<=c[index][4][7];
                    envelope_delay=channel_envelope_delay[channel[3:0]];
                    c[index][5][15:8]<=envelope_delay;
                    state<=channel_envelope_step[channel[3:0]] ? ENV_STEP : PITCH;
                end
                state[$clog2(ENV_STEP)]: begin
                    envelope_candidate<=envelope_down ? $signed({2'b0,envelope_source})-$signed({2'b0,envelope_step}) :
                        $signed({2'b0,envelope_source})+$signed({2'b0,envelope_step});
                    state<=ENV_COMMIT;
                end
                state[$clog2(ENV_COMMIT)]: begin
                    envelope_amplitude=envelope_down ?
                        (envelope_candidate<$signed({2'b0,envelope_target}) ? envelope_target : envelope_candidate[6:0]) :
                        (envelope_candidate>$signed({2'b0,envelope_target}) ? envelope_target : envelope_candidate[6:0]);
                    envelope_target_reached<=envelope_amplitude==envelope_target;
                    envelope_shutdown<=envelope_down && envelope_amplitude==0;
                    c[channel[3:0]][5][6:0]<=envelope_amplitude;state<=ENV_ROUTE;
                end
                state[$clog2(ENV_ROUTE)]: begin
                    index=int'(channel[3:0]);
                    envelope_repeat_count<=c[index][6][15:9];
                    env_read_address<=prepared_envelope_address;env_repeat<=c[index][6][8];
                    if (envelope_shutdown) begin stop_channel(index);state<=PITCH;end
                    else if (envelope_target_reached) begin
                        state<=ENV_REPEAT;
                    end else state<=ENV_RELOAD;
                end
                state[$clog2(ENV_REPEAT)]: begin
                    index=int'(channel[3:0]);repeat_remaining=envelope_repeat_count;
                    if (env_repeat && repeat_remaining!=0) repeat_remaining=repeat_remaining-7'd1;
                    c[index][6][15:9]<=repeat_remaining;
                    if (!env_repeat || repeat_remaining==0) fetch(env_read_address,ENV_WORD0);
                    else state<=ENV_RELOAD;
                end
                state[$clog2(ENV_WORD0)]: begin c[channel[3:0]][4] <= fetched_word; fetch(env_read_address+22'd1,ENV_WORD1); end
                state[$clog2(ENV_WORD1)]: begin
                    index = int'(channel[3:0]); c[index][6] <= fetched_word;
                    if (env_repeat) fetch(env_read_address+22'd2,ENV_WORD2);
                    else begin c[index][10][8:0] <= c[index][10][8:0]+9'd2; env_loaded = 1; state<= ENV_RELOAD; end
                end
                state[$clog2(ENV_WORD2)]: begin c[channel[3:0]][10][8:0] <= fetched_word[8:0]; env_loaded = 1; state<= ENV_RELOAD; end
                state[$clog2(ENV_RELOAD)]: begin
                    index = int'(channel[3:0]);
                    if (env_loaded && c[index][7][6] && c[index][10][8:0]==c[index][7][15:7]) begin g[23][index] = 1; update_beat_irq(); end
                    c[index][5][15:8] <= c[index][6][7:0]; state<= PITCH;
                end
                state[$clog2(PITCH)]: begin
                    index=int'(channel[3:0]);
                    if (g[24][index] && current_pitch_changed && pitch_due[index]) begin
                        state<=PITCH_ADD;
                    end else begin advance_channel();state<=ENVELOPE;end
                end
                state[$clog2(PITCH_ADD)]: begin
                    pitch_candidate<=pitch_down ? $signed({2'b0,pitch_start})-$signed({9'b0,pitch_step}) :
                        $signed({2'b0,pitch_start})+$signed({9'b0,pitch_step});
                    state<=PITCH_COMMIT;
                end
                state[$clog2(PITCH_COMMIT)]: begin
                    phase[channel[3:0]]<=pitch_down ?
                        (pitch_candidate<$signed({2'b0,pitch_target}) ? pitch_target : pitch_candidate[18:0]) :
                        (pitch_candidate>$signed({2'b0,pitch_target}) ? pitch_target : pitch_candidate[18:0]);
                    advance_channel();state<=ENVELOPE;
                end
                state[$clog2(RAMP)]: if (channel_position[16]) state<= DONE;
                    else begin
                        index = int'(channel[3:0]);
                        ramp_voice<=channel[3:0];advance_channel();
                        ramp_active<=current_ramp_enabled;
                        envelope_source<=c[index][5][6:0];envelope_step<=c[index][10][15:9];state<=RAMP_STEP;
                    end
                state[$clog2(RAMP_STEP)]: begin
                    if (ramp_active) begin
                        envelope_candidate<=$signed({2'b0,envelope_source})-$signed({2'b0,envelope_step});state<=RAMP_COMMIT;
                    end else state<=RAMP;
                end
                state[$clog2(RAMP_COMMIT)]: begin
                    envelope_amplitude=envelope_candidate[8] ? 7'd0 : envelope_candidate[6:0];
                    c[ramp_voice][5][6:0]<=envelope_amplitude;
                    if (envelope_amplitude==0) stop_channel(int'(ramp_voice));
                    state<=RAMP;
                end
                state[$clog2(DONE)]: begin
                    if (env_pending && current_beat!=0) begin
                        current_beat = current_beat-12'd1;
                        if (current_beat==0) begin
                            current_beat = g[4][11:0];
                            if (g[5][13:0]!=0) g[5][13:0] = g[5][13:0]-14'd1;
                            if (g[5][13:0]==0 && g[5][15]) begin g[5][14] = 1; update_beat_irq(); end
                        end
                    end
                    busy<= 0; state<= IDLE;
                end
                default: state<= IDLE;
            endcase
        end
        if (channel_clear) channel<=5'd0;
        else if (channel_jump) channel<=next_enabled_channel;
        else if (channel_step) channel<=incremented_channel;
    end
endmodule
