module pocket_psram_tb (
    input logic clk, bank, read_en, write_en,
    input logic [21:0] address,
    input logic [15:0] write_data, chip_data,
    output logic busy, read_avail,
    output logic [15:0] read_data, bus_data,
    output logic [5:0] physical_address,
    output logic adv_n, ce0_n, ce1_n, oe_n, we_n, ub_n, lb_n, controller_drive
);
    wire [15:0] dq;
    assign dq = controller_drive ? 16'hzzzz : chip_data;
    assign bus_data = dq;
    assign controller_drive = controller.data_out_en;
    psram #(.CLOCK_SPEED(133.240790),.MAX_ACCESS_TIME_FROM_ADV(95),.MIN_CE_BEFORE_ADV_HIGH(13),.MIN_ADDRESS_HOLD_AFTER_ADV_HIGH(8)) controller (
        .clk,.bank_sel(bank),.addr(address),.write_en,.data_in(write_data),
        .write_high_byte(1'b1),.write_low_byte(1'b1),.read_en,.read_avail,.data_out(read_data),.busy,
        .cram_a(physical_address),.cram_dq(dq),.cram_wait(1'b0),.cram_clk(),.cram_adv_n(adv_n),.cram_cre(),
        .cram_ce0_n(ce0_n),.cram_ce1_n(ce1_n),.cram_oe_n(oe_n),.cram_we_n(we_n),.cram_ub_n(ub_n),.cram_lb_n(lb_n));
endmodule
