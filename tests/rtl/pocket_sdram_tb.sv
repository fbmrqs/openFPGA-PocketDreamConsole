module pocket_sdram_tb #(parameter logic [9:0] REFRESH_INTERVAL=10'd736) (
    input logic controller_clk, chip_clk, reset_n,
    input logic [15:0] chip_data,
    input logic word_write,
    input logic [23:0] word_address,
    input logic [31:0] word_data,
    output logic word_done,
    input logic burst_read,
    input logic [24:0] burst_address,
    output logic burst_valid, burst_done,
    output logic [31:0] burst_data,
    output logic phy_cke, phy_cas, phy_ras, phy_we,
    output logic [1:0] phy_ba, phy_dqm,
    output logic [12:0] phy_a,
    output logic [15:0] bus_data,
    output logic controller_drive
);
    wire [15:0] dq;
    assign controller_drive=controller.phy_dq_oe;
    assign dq=controller_drive ? 16'hzzzz : chip_data;
    assign bus_data=dq;
    io_sdram #(.REFRESH_INTERVAL(REFRESH_INTERVAL)) controller (
        .controller_clk,.chip_clk,.clk_90(controller_clk),.reset_n,
        .phy_cke,.phy_clk(),.phy_cas,.phy_ras,.phy_we,.phy_ba,.phy_a,.phy_dq(dq),.phy_dqm,
        .burst_rd(burst_read),.burst_addr(burst_address),.burst_len(11'd8),.burst_32bit(1'b0),
        .burst_data,.burst_data_valid(burst_valid),.burst_data_done(burst_done),
        .burstwr(1'b0),.burstwr_addr(25'b0),.burstwr_ready(),.burstwr_strobe(1'b0),.burstwr_data(16'b0),.burstwr_done(1'b0),
        .word_rd(1'b0),.word_wr(word_write),.word_addr(word_address),.word_data,.word_wstrb(4'hf),
        .word_data_next(32'b0),.word_wstrb_next(4'b0),.word_burst_len(4'b0),.word_burst_wr_len(4'b0),
        .word_q(),.word_busy(),.word_q_valid(),.word_wr_data_next(),.word_wr_done(word_done),.word_queue_pending(),
        .burst_wr_direct_data(32'b0),.burst_wr_direct_strb(4'b0),.dbg_io());
endmodule
