module spu_counter_tb;
    pdc_spu dut(.clk(1'b0),.reset(1'b1),.register_write(1'b0),.register_address(14'b0),.register_data(16'b0),.advance(1'b0),.cycles(8'b0),.memory_ack(1'b0),.memory_data(16'b0));
    logic [31:0] random=32'h514ce80d,value,expected;
    logic [7:0] debit;
    logic [8:0] period;
    task automatic check(input logic [31:0] counter,input logic [7:0] elapsed);
        for (integer p=0;p<2;p++) begin
            period=p==0 ? 9'd96 : 9'd384;
            expected=counter-32'(elapsed);
            if (dut.counter_expired(counter,elapsed)!=($signed(expected)<=0)) $fatal(1,"Counter expiry differs at %h - %h",counter,elapsed);
            if ($signed(expected)<=0) expected=expected+32'(period);
            if (dut.counter_advance(counter,elapsed,period)!=expected) $fatal(1,"Counter update differs at %h - %h + %h",counter,elapsed,period);
        end
    endtask
    initial begin
        for (integer n=0;n<262144;n++) begin
            random=random^(random<<13);random=random^(random>>17);random=random^(random<<5);
            check(random,8'(n));
        end
        for (integer n=0;n<256;n++) begin
            check(32'h80000000+32'(n),8'(255-n));check(32'h7fffffff-32'(n),8'(n));
            check(32'(n),8'(255-n));check(32'hffffffff-32'(n),8'(n));
        end
        $display("SPU counters: 526336 full-width expiry/reload cases, signed wrap and all 8-bit debits passed");$finish;
    end
endmodule
