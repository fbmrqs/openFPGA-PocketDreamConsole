`timescale 1ns/1ps
module display_mode_tb;
    logic clk=0;
    always #5 clk=~clk;
    logic little=0, rd=0, wr=0, active=0;
    logic [31:0] address=0, data=0;
    wire [31:0] q;
    wire grayscale;
    pdc_bridge_cmd dut (
        .clk, .bridge_endian_little(little), .bridge_addr(address),
        .bridge_rd(rd), .bridge_wr(wr), .bridge_wr_data(data), .bridge_rd_data(q),
        .status_boot_done(1'b1), .status_setup_done(1'b0), .status_running(1'b0),
        .target_dataslot_read(1'b0), .target_dataslot_write(1'b0),
        .target_dataslot_getfile(1'b0), .target_dataslot_openfile(1'b0),
        .video_grayscale(grayscale), .video_grayscale_active(active));
    function automatic logic [31:0] endian(input logic [31:0] word_value);
        return little ? {word_value[7:0],word_value[15:8],word_value[23:16],word_value[31:24]} : word_value;
    endfunction
    task automatic write_word(input logic [31:0] offset, value);
        @(negedge clk); address=32'hf8000000+offset;data=endian(value);wr=1;
        @(negedge clk);wr=0;
    endtask
    task automatic expect_word(input logic [31:0] offset, value);
        @(negedge clk);address=32'hf8000000+offset;rd=1;
        @(negedge clk);rd=0;
        if(q!==endian(value))$fatal(1,"Bridge %x expected %x got %x",offset,endian(value),q);
    endtask
    initial begin
        for(int order=0;order<2;order++)begin
            little=1'(order);repeat(8)@(negedge clk);
            expect_word(4,32'h20);expect_word(8,32'h40);
            write_word(32'h20,32'h2101);write_word(0,32'h434d00b8);
            repeat(12)@(negedge clk);
            if(!grayscale)$fatal(1,"Grayscale request missing");
            expect_word(0,32'h425500b8);
            active=1;repeat(4)@(negedge clk);
            expect_word(0,32'h4f4b0000);expect_word(32'h40,32'h444d);
            write_word(32'h20,32'h1000);write_word(0,32'h434d00b8);
            repeat(12)@(negedge clk);
            if(grayscale)$fatal(1,"Color request missing");
            expect_word(0,32'h425500b8);
            active=0;repeat(4)@(negedge clk);
            expect_word(0,32'h4f4b0000);expect_word(32'h40,32'h444d);
            // The existing reset commands still operate in both byte orders.
            write_word(0,32'h434d0011);repeat(4)@(negedge clk);
            expect_word(0,32'h4f4b0000);
            if(!dut.reset_n)$fatal(1,"Reset exit failed");
            write_word(0,32'h434d0010);repeat(4)@(negedge clk);
            expect_word(0,32'h4f4b0000);
            if(dut.reset_n)$fatal(1,"Reset enter failed");
        end
        $display("Display notification: grayscale acknowledgement waits for video domain; color, reset and both byte orders passed");
        $finish;
    end
endmodule

// The display command uses registers only; its unrelated data table is idle.
module mf_datatable (
    input wire [9:0] address_a,address_b,
    input wire clock_a,clock_b,wren_a,wren_b,
    input wire [31:0] data_a,data_b,
    output wire [31:0] q_a,q_b
);
    assign q_a=0;
    assign q_b=0;
endmodule
