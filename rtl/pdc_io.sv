module pdc_io (
    input logic clk, reset,
    input logic [2:0] final_bank,
    input logic videojet_controls,
    input logic [8:0] buttons,
    input logic [21:0] pc,
    input logic [5:0] ds,
    output logic ds_write,
    output logic [5:0] ds_value,
    input logic access, write,
    input logic [13:0] address,
    input logic [15:0] write_data,
    output logic [15:0] read_data,
    input logic advance,
    input logic [7:0] cycles,
    output logic busy,
    input logic ppu_irq, spu_channel_irq, spu_beat_irq,
    input logic [8:0] scanline,
    output logic [7:0] irq,
    output logic fiq,
    output logic [2:0] bank,
    output logic bank_changed,
    output logic [1:0] address_decode,
    output logic watchdog_reset
);
    logic [15:0] port_buffer [0:2], port_dir [0:2], port_attribute [0:2], port_mask [0:2];
    logic [4:0] gpio_mode;
    logic [15:0] timer_a, timer_b, preload_a, preload_b, control_a, control_b;
    logic enabled_a, enabled_b;
    logic [3:0] timebase;
    logic [15:0] system_control, irq_control, irq_status, extmem_control;
    (* preserve, dont_merge *) logic watchdog_enabled;
    logic [2:0] fiq_select;
    logic [15:0] adc_control, adc_status, adc_data, uart_control, uart_status;
    logic adc_active;
    logic [31:0] adc_divcounter, timer_divcounter;
    typedef enum logic [11:0] {TICK_COUNT=12'h001, TICK_RELOAD=12'h002, TICK_DIVIDE=12'h004, TICK_COMMIT=12'h008, ADC_CHECK=12'h010, ADC_RELOAD=12'h020, ADC_COMPLETE=12'h040, ADVANCE_COMMIT=12'h080, COUNTDOWN_COMPLETE=12'h100, UART_BASE=12'h200, UART_DURATION=12'h400, GPIO_COMMIT=12'h800} tick_state_t;
    (* preserve, dont_retime *) tick_state_t tick_state;
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (!reset && !$onehot(tick_state)) $fatal(1,"Peripheral tick state is not one-hot");
`endif
    logic increment_a, increment_b;
    (* preserve, dont_merge *) logic [14:0] timer_divided;
    logic signed [4:0] tick_divisor_a, tick_divisor_b;
    logic [15:0] next_timer_a, next_timer_b, tick_irqs;
    logic [7:0] baud_lo, baud_hi, tx_buffer;
    logic [16:0] uart_period, uart_extra;
    logic [19:0] uart_base;
    logic uart_long_word;
    logic [14:0] random1, random2;
    integer timer_clock, adc_clock, advance_scale;
    logic signed [24:0] tx_clock;
    logic signed [25:0] watchdog_clock;
    (* preserve *) logic [16:0] timer_low, adc_low, tx_low, watchdog_low;
    (* preserve *) logic [15:0] timer_upper, adc_upper;
    (* preserve *) logic [8:0] tx_upper;
    (* preserve *) logic [9:0] watchdog_upper;
    logic adc_update, tx_update, watchdog_update, repeating_timer;
    always_ff @(posedge clk) begin
        tx_upper<=tx_clock[24:16];watchdog_upper<=watchdog_clock[25:16];
    end
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (!reset && busy && tick_state[$clog2(ADVANCE_COMMIT)] &&
            (tx_upper!=tx_clock[24:16] || watchdog_upper!=watchdog_clock[25:16]))
            $fatal(1,"Prepared peripheral upper words differ from their countdowns");
`endif
    logic adc_due, timer_due, watchdog_due;
    integer divisor_a, divisor_b, index, field, k;
    logic [15:0] active_irqs, input_port, output_port;
    wire [15:0] bank_port_buffer= (address==14'h3d01 || address==14'h3d02) ? write_data : port_buffer[0];
    wire [15:0] bank_port_dir= address==14'h3d03 ? write_data : port_dir[0];
    wire [15:0] bank_port_attribute= address==14'h3d04 ? write_data : port_attribute[0];
    wire [15:0] bank_port_mask= address==14'h3d05 ? write_data : port_mask[0];
    wire [15:0] projected_port=(bank_port_buffer^(bank_port_dir&~bank_port_attribute))&~bank_port_mask;
    wire [15:0] current_port=(port_buffer[0]^(port_dir[0]&~port_attribute[0]))&~port_mask[0];
    (* preserve, dont_retime *) logic gpio_masked_valid;
    (* preserve, dont_retime *) logic [2:0] gpio_masked_bank;
    always_ff @(posedge clk) begin
        gpio_masked_valid<=access && write ? |projected_port[15:8] : |current_port[15:8];
        gpio_masked_bank<=(access && write ? projected_port[2:0] : current_port[2:0])&final_bank;
    end
    logic gpio_raw_valid;
    logic [2:0] gpio_raw_bank;
    function automatic logic [31:0] increment_counter(input logic [31:0] value);
        return {8'(value[31:24]+8'(&value[23:0])),8'(value[23:16]+8'(&value[15:0])),
                8'(value[15:8]+8'(&value[7:0])),8'(value[7:0]+8'd1)};
    endfunction
    function automatic logic debit_expired(input logic [15:0] upper,input logic [16:0] low);
        if (upper[15]) return upper!=16'h8000 || !low[16];
        return upper==0 && (low[16] || low[15:0]==0);
    endfunction
    wire adc_expired=adc_update && debit_expired(adc_upper,adc_low);
    wire tx_expired=tx_update && debit_expired(16'($signed(tx_upper)),tx_low);
    wire watchdog_expired=watchdog_update && debit_expired(16'($signed(watchdog_upper)),watchdog_low);
    function automatic logic divided(input logic [31:0] count,input integer divisor);
        case (divisor)
            0: return 1;
            1: return ~|count[0:0];
            2: return ~|count[1:0];
            3: return ~|count[2:0];
            4: return ~|count[3:0];
            5: return ~|count[4:0];
            6: return ~|count[5:0];
            7: return ~|count[6:0];
            8: return ~|count[7:0];
            9: return ~|count[8:0];
            10: return ~|count[9:0];
            11: return ~|count[10:0];
            12: return ~|count[11:0];
            13: return ~|count[12:0];
            14: return ~|count[13:0];
            default: return 0;
        endcase
    endfunction
    assign timer_divided[0]=1'b1;
    genvar count;
    generate for (count=1;count<15;count=count+1) begin : timer_dividers
        always_ff @(posedge clk) begin
            if (access && write && address==14'h3d11) timer_divided[count]<=1'b1;
            else timer_divided[count]<=busy && tick_state[$clog2(TICK_RELOAD)] && !(access && write) ?
                &timer_divcounter[count-1:0] : ~|timer_divcounter[count-1:0];
        end
`ifdef PDC_VERIFY_MMIO_CYCLES
        always_ff @(posedge clk)
            if (!reset && busy && tick_state[$clog2(TICK_DIVIDE)] && !(access && write) &&
                timer_divided[count]!=(~|timer_divcounter[count-1:0]))
                $fatal(1,"Prepared timer divider does not match counter");
`endif
    end endgenerate
    function automatic logic timer_is_divided(input logic signed [4:0] divisor);
        return divisor>=0 && divisor<=14 && timer_divided[divisor[3:0]];
    endfunction
    task automatic uart_irq_update;
        irq_status[8] = (uart_control[0] && uart_status[0]) || (uart_control[1] && uart_status[1]);
    endtask
    always_comb begin
        active_irqs = irq_status & irq_control;
        irq = {(|(active_irqs & 16'h008b)),(|(active_irqs & 16'h0070)),(|(active_irqs & 16'h1200)),
               spu_beat_irq,(|(active_irqs & 16'h2100)),(|(active_irqs & 16'h0c00)),spu_channel_irq,ppu_irq};
        case (fiq_select)
            0: fiq = ppu_irq;
            1: fiq = spu_channel_irq;
            2: fiq = active_irqs[11];
            3: fiq = active_irqs[10];
            4: fiq = active_irqs[8];
            5: fiq = active_irqs[9] || active_irqs[12];
            6: fiq = active_irqs[13];
            default: fiq = 0;
        endcase
        address_decode = extmem_control[7:6];
        divisor_a = -1; divisor_b = -1;
        if (control_a[2:0]==5) begin
            case (control_a[5:3])
                0: divisor_a=4; 1: divisor_a=5; 2: divisor_a=7;
                3: divisor_a=12-int'(timebase[1:0]); 4: divisor_a=13; 5: divisor_a=14;
                default: begin end
            endcase
        end else if (control_a[5:3]==6) begin
            case (control_a[2:0]) 2:divisor_a=0;3:divisor_a=2;4:divisor_a=3;default:begin end endcase
        end
        case (control_b[2:0]) 2:divisor_b=0;3:divisor_b=2;4:divisor_b=3;default:begin end endcase
        read_data = 0; input_port = 0;
        case (address)
            14'h3d01: read_data=((port_buffer[0] ^ (port_dir[0] & ~port_attribute[0])) & port_dir[0] & ~port_mask[0]) | ((videojet_controls ? 16'b0 : {3'b0,buttons[8],3'b0,buttons[7],8'b0}) & ~port_dir[0] & ~port_mask[0]);
            14'h3d02: read_data=port_buffer[0];
            14'h3d03: read_data=port_dir[0];
            14'h3d04: read_data=port_attribute[0];
            14'h3d05: read_data=port_mask[0];
            14'h3d06: read_data=((port_buffer[1] ^ (port_dir[1] & ~port_attribute[1])) & port_dir[1] & ~port_mask[1]) | ({8'b0,buttons[3] && !videojet_controls,buttons[6:4],buttons[3] && videojet_controls,buttons[2:0]} & ~port_dir[1] & ~port_mask[1]);
            14'h3d07: read_data=port_buffer[1];
            14'h3d08: read_data=port_dir[1];
            14'h3d09: read_data=port_attribute[1];
            14'h3d0a: read_data=port_mask[1];
            14'h3d0b: read_data=((port_buffer[2] ^ (port_dir[2] & ~port_attribute[2])) & port_dir[2] & ~port_mask[2]) | (16'b0 & ~port_dir[2] & ~port_mask[2]);
            14'h3d0c: read_data=port_buffer[2];
            14'h3d0d: read_data=port_dir[2];
            14'h3d0e: read_data=port_attribute[2];
            14'h3d0f: read_data=port_mask[2];
            14'h3d00: read_data={11'b0,gpio_mode};
            14'h3d10: read_data={12'b0,timebase};
            14'h3d12: read_data=timer_a;14'h3d13:read_data=control_a;14'h3d14:read_data={15'b0,enabled_a};
            14'h3d16: read_data=timer_b;14'h3d17:read_data=control_b;14'h3d18:read_data={15'b0,enabled_b};
            14'h3d1c: read_data={7'b0,scanline};
            14'h3d20: read_data=system_control;14'h3d21:read_data=irq_control;14'h3d22:read_data=irq_status;
            14'h3d23: read_data=extmem_control;
            14'h3d25: read_data=adc_control|adc_status;14'h3d27:read_data=adc_data;
            14'h3d2c: read_data={1'b0,random1};14'h3d2d:read_data={1'b0,random2};
            14'h3d2e: read_data={13'b0,fiq_select};14'h3d2f:read_data={10'b0,ds};
            14'h3d30: read_data=uart_control;14'h3d31:read_data=uart_status;
            14'h3d33: read_data={8'b0,baud_lo};14'h3d34:read_data={8'b0,baud_hi};14'h3d35:read_data={8'b0,tx_buffer};
            default: begin end
        endcase
    end
    always @(posedge clk) begin
        ds_write=0; bank_changed=0; watchdog_reset=0;
        adc_upper<=adc_clock[31:16];
        adc_low<=tick_state[$clog2(ADC_CHECK)] ? {1'b0,adc_clock[15:0]}+17'd16 :
            {1'b0,adc_clock[15:0]}-17'(cycles);
        if (reset) begin
            for (k=0;k<3;k=k+1) begin port_buffer[k]<=0;port_dir[k]<=0;port_attribute[k]<=0;port_mask[k]<=0;end
            gpio_mode=0;timer_a=0;timer_b=0;preload_a=0;preload_b=0;control_a=16'h36;control_b=6;
            enabled_a=0;enabled_b=0;timebase=0;system_control=0;irq_control=0;irq_status=0;
            extmem_control=16'h28;fiq_select=7;bank=final_bank;ds_value=0;
            adc_control=0;adc_status=0;adc_data=0;adc_active=0;adc_divcounter<=0;timer_divcounter<=0;
            watchdog_due<=0;timer_due<=0;tick_divisor_a<=-1;tick_divisor_b<=-1;tick_state<=TICK_COUNT;increment_a<=0;increment_b<=0;next_timer_a<=0;next_timer_b<=0;tick_irqs<=0;
            uart_control=0;uart_status=16'h20;baud_lo=0;baud_hi=0;tx_buffer=0;uart_period<=0;uart_extra<=0;uart_base<=0;uart_long_word<=0;
            random1=15'h1418;random2=15'h1658;timer_clock=27000000;adc_clock=16;tx_clock=0;
            watchdog_clock<=26'sd20250000;advance_scale=0;busy<=0;
            timer_low<=0;adc_low<=0;tx_low<=0;watchdog_low<=0;
            timer_upper<=0;adc_upper<=0;
            adc_update<=0;tx_update<=0;watchdog_update<=0;repeating_timer<=0;
            adc_due<=0;
        end else begin
            if (access) begin
                if (!write) begin
                    if (address==14'h3d2c) random1={random1[13:0],random1[14]^random1[13]};
                    if (address==14'h3d2d) random2={random2[13:0],random2[14]^random2[13]};
                    if (address==14'h3d36) uart_status[7]=0;
                end else if (address>=14'h3d01 && address<=14'h3d0f) begin
                    case (address)
                        14'h3d01:port_buffer[0]<=write_data;
                        14'h3d02:port_buffer[0]<=write_data;
                        14'h3d03:port_dir[0]<=write_data;
                        14'h3d04:port_attribute[0]<=write_data;
                        14'h3d05:port_mask[0]<=write_data;
                        14'h3d06:port_buffer[1]<=write_data;
                        14'h3d07:port_buffer[1]<=write_data;
                        14'h3d08:port_dir[1]<=write_data;
                        14'h3d09:port_attribute[1]<=write_data;
                        14'h3d0a:port_mask[1]<=write_data;
                        14'h3d0b:port_buffer[2]<=write_data;
                        14'h3d0c:port_buffer[2]<=write_data;
                        14'h3d0d:port_dir[2]<=write_data;
                        14'h3d0e:port_attribute[2]<=write_data;
                        14'h3d0f:port_mask[2]<=write_data;
                        default:begin end
                    endcase
                    if (address<=14'h3d05 && pc<22'h2800) begin
                        gpio_raw_valid<=address<=14'h3d02 && |write_data[15:8];
                        gpio_raw_bank<=write_data[2:0]&final_bank;
                        busy<=1;tick_state<=GPIO_COMMIT;
                    end
                end else case (address)
                    14'h3d00:gpio_mode=write_data[4:0];14'h3d10:timebase=write_data[3:0];14'h3d11:timer_divcounter<=0;
                    14'h3d12:begin timer_a=write_data;preload_a=write_data;end
                    14'h3d13:control_a=write_data;14'h3d14:enabled_a=write_data[0];14'h3d15:irq_status[11]=0;
                    14'h3d16:begin timer_b=write_data;preload_b=write_data;end
                    14'h3d17:control_b=write_data;14'h3d18:enabled_b=write_data[0];14'h3d19:irq_status[10]=0;
                    14'h3d20:begin if (write_data[15] && !watchdog_enabled) watchdog_clock<=26'sd20250000;system_control=write_data&16'hc3f6;end
                    14'h3d21:irq_control=write_data;14'h3d22:irq_status=irq_status&~write_data;14'h3d23:extmem_control=write_data&16'hffe;
                    14'h3d24:if (watchdog_enabled && write_data==16'h55aa) watchdog_clock<=26'sd20250000;
                    14'h3d25:begin
                        adc_control=write_data&16'h177f;adc_status=adc_status&~(write_data&16'h2000);
                        if (!adc_status[13]) irq_status[13]=0;
                        if (adc_control[0]) begin
                            adc_status[13]=1;
                            if (adc_control[12]) begin adc_status[13]=0;adc_control[12]=0;adc_active=1;adc_data[15]=0;end
                        end else adc_active=0;
                    end
                    14'h3d2c:random1=write_data[14:0];14'h3d2d:random2=write_data[14:0];14'h3d2e:fiq_select=write_data[2:0];
                    14'h3d2f:begin ds_write=1;ds_value=write_data[5:0];end
                    14'h3d30:begin
                        old_flags=uart_control;uart_control=write_data;uart_irq_update();
                        if (old_flags[7]!=uart_control[7]) begin
                            uart_status[1]=uart_control[7];if (!uart_control[7]) begin uart_status[6]=0;tx_clock=0;end
                        end
                    end
                    14'h3d31:begin uart_status=uart_status&~(write_data&16'h3);uart_irq_update();end
                    14'h3d33:baud_lo=write_data[7:0];14'h3d34:baud_hi=write_data[7:0];
                    14'h3d35:begin
                        tx_buffer=write_data[7:0];
                        if (uart_control[7] && !uart_status[6]) begin
                            uart_status[1]=0;uart_status[6]=1;
                            uart_period<=17'h10000-{1'b0,baud_hi,baud_lo};uart_long_word<=uart_control[5];
                            busy<=1;tick_state<=UART_BASE;
                        end
                    end
                    default:begin end
                endcase
            end
            else if (advance && !busy) begin
                advance_scale=int'(cycles)*32768;busy<=1;repeating_timer<=0;
                timer_low<={1'b0,timer_clock[15:0]}-{1'b0,advance_scale[15:0]};
                timer_upper<=timer_clock[31:16]-advance_scale[31:16];
                adc_update<=adc_active;
                tx_low<={1'b0,tx_clock[15:0]}-17'(cycles);tx_update<=tx_clock!=0;
                watchdog_low<={1'b0,watchdog_clock[15:0]}-17'(cycles);
                watchdog_update<=watchdog_enabled;
                tick_state<=ADVANCE_COMMIT;
            end else if (busy) begin
                unique case (1'b1)
                    tick_state[$clog2(GPIO_COMMIT)]: begin
                        if (gpio_masked_valid) begin
                            if (bank!=gpio_masked_bank) begin bank=gpio_masked_bank;bank_changed=1;end
                        end else if (gpio_raw_valid && bank!=gpio_raw_bank) begin bank=gpio_raw_bank;bank_changed=1;end
                        busy<=0;tick_state<=TICK_COUNT;
                    end
                    tick_state[$clog2(ADVANCE_COMMIT)]: begin
                        timer_due<=debit_expired(timer_upper,timer_low);
                        if (!debit_expired(timer_upper,timer_low) &&
                            (repeating_timer || !(adc_expired || tx_expired || watchdog_expired))) busy<=0;
                        adc_due<=adc_expired;watchdog_due<=watchdog_expired;
                        timer_clock<=$signed({16'(timer_upper-16'(timer_low[16])),timer_low[15:0]});
                        if (adc_update) adc_clock<=$signed({16'(adc_upper-16'(adc_low[16])),adc_low[15:0]});
                        if (tx_update) tx_clock<=$signed({9'(tx_upper-9'(tx_low[16])),tx_low[15:0]});
                        if (watchdog_update) watchdog_clock<=$signed({10'(watchdog_upper-10'(watchdog_low[16])),watchdog_low[15:0]});
                        adc_update<=0;tx_update<=0;watchdog_update<=0;
                        tick_state<=repeating_timer || !(adc_expired || tx_expired || watchdog_expired) ? TICK_COUNT : COUNTDOWN_COMPLETE;
                    end
                    tick_state[$clog2(UART_BASE)]: begin
                        uart_base<=({3'b0,uart_period}<<3)+({3'b0,uart_period}<<1);
                        uart_extra<=uart_long_word ? uart_period : 17'b0;
                        tick_state<=UART_DURATION;
                    end
                    tick_state[$clog2(UART_DURATION)]: begin
                        tx_clock<=$signed({1'b0,20'(uart_base+{3'b0,uart_extra}),4'b0});
                        tick_state<=TICK_COUNT;busy<=0;
                    end
                    tick_state[$clog2(COUNTDOWN_COMPLETE)]: begin
                        if (uart_status[6] && tx_clock<=0) begin tx_clock=0;uart_status[1]=1;uart_status[6]=0;uart_irq_update();end
                        if (watchdog_due) begin
                            watchdog_clock<=watchdog_clock+26'sd20250000;watchdog_reset=1;
                        end
                        tick_state<=adc_due ? ADC_CHECK : TICK_COUNT;
                    end
                    tick_state[$clog2(ADC_CHECK)]: if (adc_clock<=0) begin
                        
                        tick_state<=ADC_RELOAD;
                    end else tick_state<=TICK_COUNT;
                    tick_state[$clog2(ADC_RELOAD)]: begin
                        adc_clock<=$signed({16'(adc_upper+16'(adc_low[16])),adc_low[15:0]});
                        adc_divcounter<=increment_counter(adc_divcounter);tick_state<=ADC_COMPLETE;
                    end
                    tick_state[$clog2(ADC_COMPLETE)]: begin
                        if (divided(adc_divcounter,int'(adc_control[3:2]))) begin
                            adc_data=16'h8000;adc_status[13]=1;adc_active=0;
                            if (adc_control[9]) irq_status[13]=1;
                        end
                        tick_state<=TICK_COUNT;
                    end
                    tick_state[$clog2(TICK_COUNT)]: if (timer_due) begin
                        timer_low<={1'b0,timer_clock[15:0]}+17'(27000000&65535);
                        timer_upper<=timer_clock[31:16]+16'(27000000>>16);tick_state<=TICK_RELOAD;
                    end else busy<=0;
                    tick_state[$clog2(TICK_RELOAD)]: begin
                        timer_clock<=$signed({16'(timer_upper+16'(timer_low[16])),timer_low[15:0]});
                        timer_divcounter<=increment_counter(timer_divcounter);
                        tick_divisor_a<=5'(divisor_a);tick_divisor_b<=5'(divisor_b);tick_state<=TICK_DIVIDE;
                    end
                    tick_state[$clog2(TICK_DIVIDE)]: begin
                        increment_a<=enabled_a && timer_is_divided(tick_divisor_a);
                        increment_b<=enabled_b && timer_is_divided(tick_divisor_b);
                        next_timer_a<=timer_a+16'd1;next_timer_b<=timer_b+16'd1;
                        tick_irqs<=0;
                        tick_irqs[6]<=timer_divided[3];
                        tick_irqs[5]<=timer_divided[4];
                        tick_irqs[4]<=timer_divided[5];
                        tick_irqs[1]<=timer_divided[4'd8-{2'b0,timebase[3:2]}];
                        tick_irqs[0]<=timer_divided[4'd12-{2'b0,timebase[1:0]}];
                        tick_irqs[3]<=timer_divided[13];
                        tick_state<=TICK_COMMIT;
                    end
                    tick_state[$clog2(TICK_COMMIT)]: begin
                        irq_status=irq_status|tick_irqs;
                        if (increment_a) begin
                            timer_a=next_timer_a==0 ? preload_a : next_timer_a;
                            if (next_timer_a==0) irq_status[11]=1;
                        end
                        if (increment_b) begin
                            timer_b=next_timer_b==0 ? preload_b : next_timer_b;
                            if (next_timer_b==0) irq_status[10]=1;
                        end
                        timer_low<={1'b0,timer_clock[15:0]}-{1'b0,advance_scale[15:0]};
                        timer_upper<=timer_clock[31:16]-advance_scale[31:16];
                        repeating_timer<=1;adc_update<=0;tx_update<=0;watchdog_update<=0;tick_state<=ADVANCE_COMMIT;
                    end
                    default: tick_state<=TICK_COUNT;
                endcase
            end
        end
        watchdog_enabled<=system_control[15];
    end
    logic [15:0] old_flags;
endmodule
