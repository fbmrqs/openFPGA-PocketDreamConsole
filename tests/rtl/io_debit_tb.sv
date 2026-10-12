module io_debit_tb;
    pdc_io dut(.clk(1'b0),.reset(1'b1));
    logic [31:0] random=32'h76cbef15,expected;
    logic [16:0] low;
    logic [15:0] upper;
    task automatic check(input logic [31:0] counter,input logic [7:0] elapsed);
        for (integer timer=0;timer<2;timer++) begin
            expected=counter-(timer!=0 ? 32'(elapsed)<<15 : 32'(elapsed));
            low={1'b0,counter[15:0]}-(timer!=0 ? 17'(32'(elapsed)<<15) & 17'hffff : 17'(elapsed));
            upper=counter[31:16]-(timer!=0 ? 16'(elapsed>>1) : 16'b0);
            if (dut.debit_expired(upper,low)!=($signed(expected)<=0))
                $fatal(1,"IO expiry mismatch: %h, debit %h, timer %0d",counter,elapsed,timer);
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
        $display("IO debit: 526336 expiry cases passed, including signed wrap and all cycle counts");$finish;
    end
endmodule
