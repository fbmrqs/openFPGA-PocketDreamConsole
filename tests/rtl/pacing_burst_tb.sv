module pacing_burst_tb;
    logic clk=0,reset=1,retire_stim=0;
    always #5 clk=~clk;
    pdc_system #(.CLOCK_KHZ(98304),.REALTIME(1)) dut(.clk,.reset,.rom_ready(1'b1),.final_bank(3'b0),.videojet_controls(1'b0),.buttons(9'b0),
        .rom_ack(1'b0),.rom_data(16'b0),.rom_line_valid(1'b0),.rom_line_data(256'b0),.pixel_ready(1'b1));
    integer model_phase=0,model_credit=0,peak=0;
    initial begin
        force dut.run=0;force dut.retired=retire_stim;force dut.cpu_cycles=8'd4;
        force dut.cpu_reset=reset;force dut.requests=4'b0;
        repeat (3) @(negedge clk);reset=0;
        for (int step=0;step<98304*8;step++) begin
            if (int'(dut.phase)!=model_phase || int'(dut.credit)!=model_credit)
                $fatal(1,"Lost modeled time after a recoverable graphics burst: step=%0d credit=%0d expected=%0d",step,dut.credit,model_credit);
            retire_stim=step>=98304*3 && model_credit>=0 && step%8==0;
            model_credit=model_credit+int'(model_phase>=98304-27000)-(retire_stim ? 4 : 0);
            if (model_credit>peak) peak=model_credit;
            model_phase=model_phase>=98304-27000 ? model_phase-(98304-27000) : model_phase+27000;
            @(negedge clk);
        end
        if (model_credit>4 || peak!=81000) $fatal(1,"Burst did not recover exactly");
        $display("Pacing burst: 3 ms stall recovered without dropping modeled cycles, peak %0d cycles",peak);
        if (dut.cycle_overflow) $fatal(1,"Recoverable burst incorrectly flagged as lost time");
        retire_stim=0;
        repeat (98304*5) @(negedge clk);
        if (!dut.cycle_overflow || int'(dut.credit)!=131071) $fatal(1,"Sustained overload did not latch overflow");
        retire_stim=1;
        repeat (16) @(negedge clk);
        if (!dut.cycle_overflow) $fatal(1,"Overflow indication did not remain latched");
        reset=1;@(negedge clk);
        if (dut.cycle_overflow) $fatal(1,"Reset did not clear overflow");
        $display("Pacing burst: sustained overload detected, indication latched and reset cleared it");
        $finish;
    end
endmodule
