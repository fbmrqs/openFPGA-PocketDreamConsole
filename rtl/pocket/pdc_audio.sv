module pdc_audio (
    input logic reset, system_clk, audio_clk,
    input logic sample_valid,
    input logic signed [15:0] sample_left, sample_right,
    output logic audio_mclk, audio_lrck, audio_dac,
    output logic overflow, underflow
);
    logic reset_system;
    pdc_reset_sync reset_system_sync (.clk(system_clk),.async_reset(reset),.reset(reset_system));
    logic reset_audio;
    pdc_reset_sync reset_audio_sync (.clk(audio_clk),.async_reset(reset),.reset(reset_audio));
    assign audio_mclk=audio_clk;

    logic full, empty, read_en, read_valid, started;
    logic [31:0] fifo_data, next_sample, current_sample;
    logic [9:0] available;
    pdc_async_fifo #(.WIDTH(32),.ADDRESS_BITS(9)) samples (
        .reset,.write_clk(system_clk),.write_en(sample_valid),.write_data({sample_left,sample_right}),.full,
        .read_clk(audio_clk),.read_en,.read_data(fifo_data),.read_valid,.empty,
        .write_level(),.read_level(available));
    always_ff @(posedge system_clk or posedge reset_system)
        if (reset_system) overflow<=0;else if (sample_valid && full) overflow<=1;
    logic [1:0] divider;
    logic [5:0] bit_index;
    logic clock_edge;
    assign clock_edge = divider==3;
    assign read_en = clock_edge && bit_index==60 && started && !empty;
    always_ff @(negedge audio_clk or posedge reset_audio) begin
        if (reset_audio) begin
            audio_lrck<=0;audio_dac<=0;divider<=0;bit_index<=0;
            underflow<=0;started<=0;next_sample<=0;current_sample<=0;
        end else begin
            if (available>=256) started<=1;
            if (read_valid) next_sample<=fifo_data;
            divider<=divider+2'd1;
            if (clock_edge) begin
                bit_index<=bit_index+6'd1;
                if (bit_index==31) audio_lrck<=1;
                if (bit_index==63) begin audio_lrck<=0;current_sample<=next_sample;end
                audio_dac<=0;
                if (bit_index<16) audio_dac<=current_sample[{1'b1,~bit_index[3:0]}];
                else if (bit_index>=32 && bit_index<48) audio_dac<=current_sample[{1'b0,~bit_index[3:0]}];
                // Repeat the last stereo pair instead of inserting impulses when a producer is late.
                if (bit_index==60 && started && empty) underflow<=1;
            end
        end
    end
endmodule
