`timescale 1ns/1ps
module cache_bank_vendor_tb #(parameter TEST_SPRITES=0);
    logic clk=0,write=0;
    logic [5:0] write_address=0,read_address=0,old_read_address=0;
    logic [15:0] write_data=0,read_data,expected=0,stored_data=0,words[0:63];
    logic stored_write=0,previous_write=0,collision=0;
    logic [5:0] stored_address=0,previous_write_address=0;
    logic [31:0] random=32'h7864cd31;
    integer checks=0;
    always #5 clk=~clk;
    generate if (TEST_SPRITES) begin : sprite_test
        logic local_write;
        logic [5:0] local_write_address;
        logic [15:0] local_write_data;
        always @(posedge clk) begin
            local_write<=write;local_write_address<=write_address;local_write_data<=write_data;
        end
        pdc_sprite_bank dut(.clk, .write(local_write), .write_address({2'b0,local_write_address}),
            .write_data(local_write_data), .read_address({2'b0,read_address}), .read_data);
    end else begin : cache_test
        pdc_cache_bank #(.INDEX_BITS(6)) dut(.*);
    end endgenerate
    always @(posedge clk) begin
        collision=(stored_write && stored_address==old_read_address) ||
            (previous_write && previous_write_address==old_read_address);
        expected=words[old_read_address];
        if (stored_write) words[stored_address]=stored_data;
        previous_write=stored_write;previous_write_address=stored_address;
        stored_write=write;stored_address=write_address;stored_data=write_data;old_read_address=read_address;
    end
    initial begin
        for (integer i=0;i<64;i++) words[i]=0;
        for (integer i=0;i<10000;i++) begin
            @(negedge clk);
            if (i>3 && !collision) begin
                if (read_data!==expected) $fatal(1,"Vendor cache read mismatch at %0d: %h/%h",i,read_data,expected);
                checks++;
            end
            random=random^(random<<13);random=random^(random>>17);random=random^(random<<5);
            write=random[0];write_address=random[6:1];read_address=random[12:7];write_data=random[31:16];
        end
        $display("Vendor RAM bank (sprite=%0d): %0d two-clock reads with random writes passed",TEST_SPRITES,checks);$finish;
    end
endmodule
