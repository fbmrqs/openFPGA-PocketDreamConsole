module system_bus_tb;
    logic clk=0, reset=1;
    always #5 clk=~clk;
    logic [3:0] bus_request=0,bus_write=0;
    logic [87:0] bus_address=0;
    logic [63:0] bus_data=0;
    logic ready,rom_request,rom_ack=0;
    logic [24:0] rom_address;
    logic [255:0] rom_line_data;
    logic rom_release=0;
    always_comb for (int i=0;i<16;i++) rom_line_data[i*16 +:16]=16'(rom_address+25'(i))^16'h5a5a;
    always @(posedge clk) begin
        rom_ack<=0;
        if (reset) rom_release<=0;
        else if (!rom_request) rom_release<=0;
        else if (!rom_release) begin rom_ack<=1;rom_release<=1;end
    end
    pdc_system dut(.clk,.reset,.rom_ready(1'b1),.final_bank(3'b0),.videojet_controls(1'b0),.buttons(9'b0),
        .rom_request,.rom_address,.rom_ack,.rom_data(16'b0),.rom_line_valid(1'b1),.rom_line_data,
        .pixel_ready(1'b1),.ready);
    integer access_client=0;
    task automatic write_word(input logic [21:0] address,input logic [15:0] data);
        integer clocks=0;
        @(negedge clk);bus_address[access_client*22 +:22]=address;bus_data[access_client*16 +:16]=data;bus_write=4'(1<<access_client);bus_request=4'(1<<access_client);
        do begin @(negedge clk);clocks++;if (clocks>1024) $fatal(1,"Bus write timed out");end while (!dut.acks[access_client]);
        bus_request=0;repeat (4) @(negedge clk);
    endtask
    integer read_clocks;
    task automatic read_word(input logic [21:0] address,input logic [15:0] expected);
        integer clocks=0;
        @(negedge clk);bus_address[access_client*22 +:22]=address;bus_write=0;bus_request=4'(1<<access_client);
        do begin @(negedge clk);clocks++;if (clocks>1024) $fatal(1,"Bus read timed out");end
        while (access_client==0 ? !dut.cpu.bus_ack : access_client==1 ? !dut.ppu.memory_ack : !dut.acks[access_client]);
        if ((access_client==0 ? dut.cpu.bus_rdata : access_client==1 ? dut.ppu.memory_data : dut.shared_data)!=expected)
            $fatal(1,"Wrong bus response at %h: %h != %h",address,access_client==0 ? dut.cpu.bus_rdata : access_client==1 ? dut.ppu.memory_data : dut.shared_data,expected);
        if (address>=22'h2800 && address<22'h4000 && clocks>5)
            $fatal(1,"MMIO read costs %0d clocks (budget 5)",clocks);
        read_clocks=clocks;
        bus_request=0;repeat (4) @(negedge clk);
    endtask
    initial begin
        force dut.run=0;
        force dut.cpu.bus_addr=bus_address[21:0];
        force dut.cpu.bus_external=(bus_address[21:0]>=22'h4000);
        force dut.requests=bus_request;force dut.writes=bus_write;
        force dut.addresses=bus_address;force dut.write_values=bus_data;
        repeat (3) @(negedge clk);reset=0;
        wait (ready);
        write_word(22'h3d02,16'h1234);
        if (dut.io.port_buffer[0]!=16'h1234) $fatal(1,"Peripheral write failed");
        write_word(22'h7d02,16'hdead);
        if (dut.io.port_buffer[0]!=16'h1234) $fatal(1,"ROM write aliased a peripheral register");
        write_word(22'h3d03,16'h4321);
        write_word(22'h3ffd03,16'hdead);
        if (dut.io.port_dir[0]!=16'h4321) $fatal(1,"High ROM write aliased a peripheral register");
        write_word(22'h2b03,16'ha1a1);write_word(22'h2bf2,16'hb2b2);
        write_word(22'h2917,16'h01ff);write_word(22'h2acf,16'hc7c7);
        write_word(22'h2c18,16'hd1d1);write_word(22'h2c19,16'hd2d2);
        write_word(22'h2c1a,16'hd3d3);write_word(22'h2c1b,16'hd4d4);
        read_word(22'h3d02,16'h1234);
        access_client=3;read_word(22'h2bf2,16'hb2b2);
        access_client=0;read_word(22'h2b03,16'ha1a1);read_word(22'h2bf2,16'hb2b2);
        read_word(22'h2917,16'h01ff);read_word(22'h2acf,16'hc7c7);
        read_word(22'h2c18,16'hd1d1);read_word(22'h2c19,16'h00d2);
        read_word(22'h2c1a,16'h01d3);read_word(22'h2c1b,16'h54d4);
        write_word(22'h3406,16'h3333);
        access_client=3;read_word(22'h3406,16'h3333);
        access_client=0;read_word(22'h3410,16'h0000);
        write_word(22'h3000,16'h1234);read_word(22'h3000,16'h1234);
        read_word(22'h3204,16'h0000);read_word(22'h3406,16'h3333);
        for (int voice=0;voice<16;voice++) begin
            access_client=voice%4;
            write_word(22'h300b+22'(voice*16),16'(voice*379)^16'hfa1d);
            write_word(22'h3204+22'(voice*16),16'(voice*593)^16'hbde7);
        end
        for (int voice=15;voice>=0;voice--) begin
            access_client=(voice+1)%4;
            read_word(22'h300b+22'(voice*16),16'(voice*379)^16'hfa1d);
            read_word(22'h3204+22'(voice*16),16'(voice*593)^16'hbde7);
            read_word(22'h3406,16'h3333);
            read_word(22'h2bf2,16'hb2b2);
        end
        access_client=0;
        write_word(22'h0400,16'hbeef);
        read_word(22'h0400,16'hbeef);
        if(read_clocks>2)$fatal(1,"RAM bus read costs %0d clocks (budget 2)",read_clocks);
        read_word(22'h3d02,16'h1234);
        read_word(22'h4000,16'h1a5a);
        read_word(22'h4007,16'h1a5d);
        read_word(22'h3d03,16'h4321);
        read_word(22'h0410,16'h0);
        read_word(22'h4007,16'h1a5d);
        for (int i=0;i<128;i++) begin
            access_client=i%4;
            write_word(22'((i*79)%10240),16'(i*177)^16'had17);
        end
        for (int i=127;i>=0;i--) begin
            access_client=(i+1)%4;
            read_word(22'((i*79)%10240),16'(i*177)^16'had17);
            if (i%16==0) read_word(22'h3d02,16'h1234);
        end
        access_client=1;read_word(22'h4000,16'h1a5a);read_word(22'h4007,16'h1a5d);
        if(read_clocks>2)$fatal(1,"PPU ROM hit costs %0d clocks (budget 2)",read_clocks);
        read_word(22'h0400,16'hbeef);read_word(22'h4007,16'h1a5d);
        access_client=0;write_word(22'h27ff,16'h5a5a);read_word(22'h27ff,16'h5a5a);
        $display("System bus: RAM, MMIO memory readback, owner handoff, ROM miss/hit and ignored ROM writes passed");
        $finish;
    end
    initial begin #10000000;$fatal(1,"System bus timeout");end
endmodule
