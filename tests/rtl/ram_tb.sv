`timescale 1ns/1ps
module ram_tb;
    logic clk=0,reset=1,request=0,write=0;
    logic [13:0] address=0,read_address=0;
    logic [15:0] write_data=0;
    wire ready,ack;
    wire [15:0] read_data;
    logic [15:0] expected [0:10239];
    logic [31:0] random_state=32'h149ace81;
    integer checks=0;
    always #5 clk=~clk;
    pdc_ram dut(.*);
    task automatic access_word(input logic [13:0] location,input logic writing,input logic [15:0] value);
        integer clocks=0;
        @(negedge clk);address=location;read_address=location;write_data=value;write=writing;
        @(negedge clk);request=1;
        do begin @(negedge clk);clocks++;if (clocks>8) $fatal(1,"RAM acknowledgment timeout");end while (!ack);
        if (!writing) begin
            if (read_data !== (location<10240 ? expected[location] : 16'b0))
                $fatal(1,"RAM response mismatch at %h: %h",location,read_data);
            checks++;
        end else if (location<10240) expected[location]=value;
        request=0;write=0;
        repeat (3) @(negedge clk);
    endtask
    initial begin
        for (int i=0;i<10240;i++) expected[i]=0;
        repeat (3) @(negedge clk);reset=0;wait(ready);
        access_word(14'h27ff,1,16'had17);access_word(14'h27ff,0,0);
        access_word(14'h2800,1,16'hbeef);access_word(14'h2800,0,0);
        for (int i=0;i<10240;i+=512) begin
            access_word(14'(i),1,16'(i)^16'h4ba1);
            access_word(14'(i+511),1,16'(i)^16'h7c42);
        end
        for (int i=0;i<4096;i++) begin
            random_state=random_state^random_state<<13;
            random_state=random_state^random_state>>17;
            random_state=random_state^random_state<<5;
            if (i%3==0) access_word(14'(random_state%10240),1,random_state[31:16]);
            access_word(14'(random_state%10240),0,0);
            access_word(14'((random_state>>14)%10240),0,0);
        end
        $display("RAM: %0d reads, clearing, writes, block boundaries and address lookahead passed",checks);
        $finish;
    end
    initial begin #2000000;$fatal(1,"RAM fixture timeout");end
endmodule
