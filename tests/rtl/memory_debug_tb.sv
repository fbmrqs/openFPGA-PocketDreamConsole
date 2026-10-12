`timescale 1ns/1ps
module memory_debug_tb;
    logic clk=0, reset=1, done=0;
    logic [3:0] status=0;
    logic [15:0] reset_vector=0;
    logic [31:0] load_crc=0, write_crc=0, first_crc=0, second_crc=0;
    logic [31:0] bridge_address=0;
    wire [31:0] bridge_data;
    pdc_memory_debug dut (.*);
    always #5 clk=~clk;
    task automatic read_value(input logic [31:0] address, expected);
        bridge_address=address; #1;
        if (bridge_data !== {expected[7:0],expected[15:8],expected[23:16],expected[31:24]})
            $fatal(1,"memory debug address %h got %h expected numeric %h",address,bridge_data,expected);
    endtask
    initial begin
        #17;reset=0;
        #6;status=1;reset_vector=16'h8d09;
        load_crc=32'h0c1dc0f3;write_crc=32'h0c1dc0f3;
        first_crc=32'h12345678;second_crc=32'h90abcdef;
        #2;done=1;
        #12;read_value(32'h20000010,0);
        #50;
        read_value(32'h20000010,1);read_value(32'h20000014,32'h8d09);
        read_value(32'h20000018,32'h0c1dc0f3);read_value(32'h2000001c,32'h0c1dc0f3);
        read_value(32'h20000020,32'h12345678);read_value(32'h20000024,32'h90abcdef);
        // Subsequent activity cannot tear the retained completed result.
        first_crc=0;second_crc=0;#50;
        read_value(32'h20000020,32'h12345678);
        done=0;#50;read_value(32'h20000010,0);read_value(32'h20000020,0);
        status=7;reset_vector=16'ha56a;first_crc=32'hccd6c6d3;second_crc=first_crc;
        #3;done=1;#50;
        read_value(32'h20000010,7);read_value(32'h20000014,32'ha56a);
        read_value(32'h20000024,32'hccd6c6d3);
        reset=1;#1;read_value(32'h20000010,0);
        $display("Memory debug: coherent snapshots, full-width byte order, hold, reload and reset passed");
        $finish;
    end
endmodule
