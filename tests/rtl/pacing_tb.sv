module pacing_tb;
    logic clk=0,reset=1,retire_stim=0;
    logic [7:0] cycle_stim=2;
    logic [15:0] backlog;
    always #5 clk=~clk;
    pdc_system #(.REALTIME(1)) dut(.clk,.reset,.rom_ready(1'b1),.final_bank(3'b0),.videojet_controls(1'b0),.buttons(9'b0),
        .rom_ack(1'b0),.rom_data(16'b0),.rom_line_valid(1'b0),.rom_line_data(256'b0),
        .pixel_ready(1'b1),.cycle_backlog(backlog));
    integer model_phase=0,model_credit=0;
    logic [31:0] random_state=32'h6d2b79f5;
    integer expected_backlog;
    initial begin
        force dut.run=0;force dut.retired=retire_stim;force dut.cpu_cycles=cycle_stim;
        force dut.cpu_reset=reset;force dut.requests=4'b0;
        repeat (3) @(negedge clk);reset=0;
        for (int step=0;step<2000000;step++) begin
            if (int'(dut.phase)!=model_phase || int'(dut.credit)!=model_credit)
                $fatal(1,"Pacing mismatch at %d: phase %d/%d, credit %d/%d",step,dut.phase,model_phase,dut.credit,model_credit);
            expected_backlog=model_credit<0 ? 0 : model_credit>65535 ? 65535 : model_credit;
            if (int'(backlog)!=expected_backlog) $fatal(1,"Pacing backlog saturation failed");
            random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);
            retire_stim=step>600000 && model_credit>=0 && random_state[2:0]==0;
            cycle_stim=8'(2+(random_state%254));
            if (retire_stim) model_credit=model_credit+int'(model_phase>=196608-27000)-int'(cycle_stim);
            else if (model_credit<131071) model_credit=model_credit+int'(model_phase>=196608-27000);
            model_phase=model_phase>=196608-27000 ? model_phase-(196608-27000) : model_phase+27000;
            @(negedge clk);
        end
        $display("Pacing: 2000000 clocks, reference phase/credit equivalence, negative credit and saturation passed");$finish;
    end
endmodule
