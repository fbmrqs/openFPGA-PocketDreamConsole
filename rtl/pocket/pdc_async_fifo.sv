module pdc_async_fifo #(
    parameter integer WIDTH = 32,
    parameter integer ADDRESS_BITS = 10
) (
    input logic reset,
    input logic write_clk, write_en,
    input logic [WIDTH-1:0] write_data,
    output logic full,
    input logic read_clk, read_en,
    output logic [WIDTH-1:0] read_data,
    output logic read_valid, empty,
    output logic [ADDRESS_BITS:0] write_level, read_level
);
    localparam integer POINTER_BITS = ADDRESS_BITS+1;
    logic [WIDTH-1:0] words [0:(1<<ADDRESS_BITS)-1];
    logic [POINTER_BITS-1:0] write_binary, write_gray, read_binary, read_gray;
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [POINTER_BITS-1:0] read_sync_1, read_sync_2, write_sync_1, write_sync_2;
    logic [POINTER_BITS-1:0] write_next, write_gray_next, read_next, read_gray_next;
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] write_reset, read_reset;
    wire write_reset_active = write_reset[1];
    wire read_reset_active = read_reset[1];
    function automatic logic [POINTER_BITS-1:0] binary(input logic [POINTER_BITS-1:0] gray);
        binary[POINTER_BITS-1]=gray[POINTER_BITS-1];
        for (int bit_index=POINTER_BITS-2;bit_index>=0;bit_index--)
            binary[bit_index]=binary[bit_index+1]^gray[bit_index];
    endfunction
    always_ff @(posedge write_clk or posedge reset)
        if (reset) write_reset<=2'b11;else write_reset<={write_reset[0],1'b0};
    always_ff @(posedge read_clk or posedge reset)
        if (reset) read_reset<=2'b11;else read_reset<={read_reset[0],1'b0};
    // Registered levels lag remote movement conservatively: write occupancy
    // can overestimate and read availability can underestimate by one clock.
    assign write_next = write_binary+POINTER_BITS'(write_en && !full);
    assign read_next = read_binary+POINTER_BITS'(read_en && !empty);
    assign write_gray_next = (write_next>>1)^write_next;
    assign read_gray_next = (read_next>>1)^read_next;
    always_ff @(posedge write_clk or posedge write_reset_active) begin
        if (write_reset_active) begin
            write_level<=0;write_binary<=0;write_gray<=0;read_sync_1<=0;read_sync_2<=0;full<=1;
        end else begin
            read_sync_1<=read_gray;read_sync_2<=read_sync_1;
            write_level<=write_next-binary(read_sync_2);
            write_binary<=write_next;write_gray<=write_gray_next;
            full<=write_gray_next=={~read_sync_2[POINTER_BITS-1:POINTER_BITS-2],read_sync_2[POINTER_BITS-3:0]};
            if (write_en && !full) words[write_binary[ADDRESS_BITS-1:0]]<=write_data;
        end
    end
    always_ff @(posedge read_clk or posedge read_reset_active) begin
        if (read_reset_active) begin
            read_level<=0;read_binary<=0;read_gray<=0;write_sync_1<=0;write_sync_2<=0;empty<=1;read_valid<=0;read_data<=0;
        end else begin
            write_sync_1<=write_gray;write_sync_2<=write_sync_1;
            read_level<=binary(write_sync_2)-read_next;
            read_binary<=read_next;read_gray<=read_gray_next;
            empty<=read_gray_next==write_sync_2;
            read_valid<=read_en && !empty;
            if (read_en && !empty) read_data<=words[read_binary[ADDRESS_BITS-1:0]];
        end
    end
endmodule
