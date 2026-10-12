module memory_tb #(parameter logic BURST_LINES=0,parameter logic REQUEST_STAGED=0,parameter logic FAST_LINE=0);
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset = 1, invalidate = 0, request = 0, ack;
    logic [24:0] address = 0, memory_address;
    logic [15:0] data, memory_data;
    logic memory_request, memory_ack = 0, memory_line_valid = BURST_LINES;
    logic [255:0] memory_line_data, line_data;
    integer reads = 0, delay_count = 0, last_reads;
    logic active = 0, release_request = 0;
    logic [24:0] held_address;
    logic staged_request;
    always_ff @(posedge clk) staged_request<=!reset && request;
    pdc_rom_cache #(.BURST_LINES(BURST_LINES),.REQUEST_STAGED(REQUEST_STAGED),.FAST_LINE(FAST_LINE)) cache(
        .request(REQUEST_STAGED ? staged_request : request), .*);
    function automatic logic [15:0] value(input logic [24:0] addr);
        return addr[15:0] ^ {7'b0,addr[24:16]} ^ 16'h5a5a;
    endfunction
    always_comb begin
        for (int word_index=0;word_index<16;word_index++)
            memory_line_data[word_index*16 +:16] = value({held_address[24:4],4'b0}+25'(word_index));
    end
    always @(posedge clk) begin
        memory_ack <= 0;
        if (reset) begin active <= 0; release_request <= 0; end
        else if (active) begin
            if (!memory_request || memory_address != held_address) $fatal(1,"Unstable cache memory request");
            if (delay_count == 0) begin
                memory_data <= value(held_address); memory_ack <= 1;
                active <= 0; release_request <= 1; reads <= reads+1;
            end else delay_count <= delay_count-1;
        end else if (release_request) begin if (!memory_request) release_request <= 0; end
        else if (memory_request) begin
            held_address <= memory_address; active <= 1; delay_count <= int'(memory_address[2:0]);
        end
    end
    integer read_clocks;
    task automatic read(input logic [24:0] addr);
        @(negedge clk);address=addr;request=1;
        read_clocks=0;
        do begin @(negedge clk);read_clocks++;end while (!ack);
        if (data != value(addr)) $fatal(1,"Wrong cache value %h",addr);
        for(int word_index=0;word_index<16;word_index++)
            if(line_data[word_index*16 +:16]!=value({addr[24:4],4'b0}+25'(word_index))) $fatal(1,"Wrong cache line word %0d at %h",word_index,addr);
        // The requester can keep valid asserted after ack without retriggering.
        repeat (3) @(negedge clk);
        request=0;repeat (3) @(negedge clk);
    endtask
    initial begin
        repeat (3) @(negedge clk);reset=0;
        read(25'h12345);if (reads!=(BURST_LINES ? 1 : 16)) $fatal(1,"Miss must fill exactly one line with the selected transfer mode");
        read(25'h12340);if(read_clocks>(FAST_LINE && !REQUEST_STAGED ? 1 : 2))$fatal(1,"ROM cache hit costs %0d clocks",read_clocks);if (reads!=(BURST_LINES ? 1 : 16)) $fatal(1,"Hit must not access memory");
        read(25'h412345);if (reads!=(BURST_LINES ? 2 : 32)) $fatal(1,"Bank tags must distinguish banks");
        invalidate=1;@(negedge clk);invalidate=0;
        read(25'h412345);if (reads!=(BURST_LINES ? 3 : 48)) $fatal(1,"Invalidation must refill");
        memory_line_valid=1;
        read(25'h612345);if (reads!=(BURST_LINES ? 4 : 49)) $fatal(1,"Native miss must transfer a single full line");
        for (int offset=0;offset<16;offset++) read(25'h612340+25'(offset));
        if (reads!=(BURST_LINES ? 4 : 49)) $fatal(1,"Native line fill must cover all words");
        for (int i=0;i<256;i++) read(25'(i*2027));
        read(25'h1fff8);last_reads=reads;
        invalidate=1;@(negedge clk);invalidate=0;
        read(25'h1fff8);
        if (reads!=last_reads+1) $fatal(1,"Invalidating the final cache line must refill before its held request");
        $display("ROM cache: hit/miss, bank tags, invalidation, delayed memory, held request passed");
        $finish;
    end
    initial begin #10000000; $fatal(1,"Cache test timeout"); end
endmodule
