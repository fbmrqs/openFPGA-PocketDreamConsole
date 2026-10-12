module pdc_ram (
    input logic clk, reset,
    output logic ready,
    input logic request, write,
    input logic [13:0] address, read_address,
    input logic [15:0] write_data,
    output logic ack,
    output logic [15:0] read_data
);
    logic [13:0] clear_address;
    logic release_request, valid_address;
    wire [15:0] ram_q;
    wire [13:0] ram_address = ready ? (address<14'h2800 ? address : 14'b0) : clear_address;
    wire ram_write = !reset && (!ready ||
        (!release_request && request && write && address<14'h2800));
    wire [13:0] safe_read_address = read_address<14'h2800 ? read_address : 14'b0;
    // Arbitration exposes the held owner's address one clock before request.
    // Both RAM read stages complete before the existing acknowledgment is used.
    pdc_cache_bank #(.INDEX_BITS(14),.WORDS(10240)) storage (
        .clk, .write(ram_write), .write_address(ram_address),
        .write_data(ready ? write_data : 16'b0),
        .read_address(safe_read_address), .read_data(ram_q));
    assign read_data=valid_address ? ram_q : 16'b0;
`ifdef PDC_VERIFY_MMIO_CYCLES
    logic [13:0] previous_read_address;
    always_ff @(posedge clk) begin
        previous_read_address<=read_address;
        if (!reset && ready && request && !release_request && previous_read_address!=address)
            $fatal(1,"RAM request arrived without its one-clock address lookahead");
    end
`endif
    always_ff @(posedge clk) begin
        ack <= 0;
        if (reset) begin ready <= 0; clear_address <= 0; release_request <= 0;valid_address<=0;end
        else if (!ready) begin
            clear_address <= clear_address + 14'd1;
            if (clear_address == 14'h27ff) ready <= 1;
        end else if (release_request) begin if (!request) release_request <= 0; end
        else if (request) begin
            valid_address<=address<14'h2800;
            ack<=1;release_request<=1;
        end
    end
endmodule
