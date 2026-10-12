`timescale 1ns/1ps
module fault_debug_tb;
    logic clk=0, reset=1, cpu_fault=0;
    logic [21:0] fault_pc=0;
    logic [15:0] fault_opcode=0;
    logic [31:0] bridge_address=0;
    wire [31:0] bridge_data;
    always #7 clk=~clk;
    pdc_fault_debug dut (.*);

    task automatic read_ui(input logic [31:0] address, expected);
        logic [31:0] displayed;
        bridge_address=address;
        #1;
        displayed={bridge_data[7:0],bridge_data[15:8],bridge_data[23:16],bridge_data[31:24]};
        if (displayed!==expected)
            $fatal(1,"address %h displayed %h, expected %h",address,displayed,expected);
    endtask
    task automatic settle;
        repeat (6) @(negedge clk);
    endtask
    initial begin
        settle();reset=0;
        read_ui(32'h20000008,0);read_ui(32'h2000000c,0);
        // Inputs can vary before a fault, but must never be shown as a fault.
        fault_pc=22'h123456;fault_opcode=16'h789a;
        settle();read_ui(32'h20000008,0);read_ui(32'h2000000c,0);
        // Fault and its held payload arrive between bridge clock edges.
        #3;cpu_fault=1;
        read_ui(32'h20000008,0);
        settle();
        read_ui(32'h20000008,32'h00123456);read_ui(32'h2000000c,32'h0000789a);
        read_ui(32'h20000000,0);read_ui(32'h20000004,0);read_ui(32'h20000010,0);
        // Resetting the CPU must clear the old snapshot and allow another fault.
        #3;cpu_fault=0;fault_pc=0;fault_opcode=0;
        settle();read_ui(32'h20000008,0);read_ui(32'h2000000c,0);
        #5;fault_pc=22'h3fedcb;fault_opcode=16'hff80;cpu_fault=1;
        settle();
        read_ui(32'h20000008,32'h003fedcb);read_ui(32'h2000000c,32'h0000ff80);
        reset=1;
        read_ui(32'h20000008,0);read_ui(32'h2000000c,0);
        $display("Fault diagnostics: coherent capture, reset/reload, address decoding and APF byte order passed");
        $finish;
    end
endmodule
