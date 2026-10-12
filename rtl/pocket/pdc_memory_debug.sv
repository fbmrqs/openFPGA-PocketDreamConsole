module pdc_memory_debug (
    input wire clk, reset, done,
    input wire [3:0] status,
    input wire [15:0] reset_vector,
    input wire [31:0] load_crc, write_crc, first_crc, second_crc,
    input wire [31:0] bridge_address,
    output logic [31:0] bridge_data
);
    // All source fields are frozen before done. Wait beyond the data
    // synchronizer before retaining one coherent menu snapshot per load.
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [2:0] done_sync;
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [147:0] payload_sync_1, payload_sync_2;
    logic captured;
    logic [147:0] snapshot;
    logic [31:0] value;
    always_ff @(posedge clk or posedge reset)
        if (reset) begin
            done_sync<=0;payload_sync_1<=0;payload_sync_2<=0;captured<=0;snapshot<=0;
        end else begin
            done_sync<={done_sync[1:0],done};
            payload_sync_1<={status,reset_vector,load_crc,write_crc,first_crc,second_crc};
            payload_sync_2<=payload_sync_1;
            if (!done_sync[2]) begin captured<=0;snapshot<=0;end
            else if (!captured) begin captured<=1;snapshot<=payload_sync_2;end
        end
    always_comb begin
        value=0;
        case (bridge_address)
            32'h20000010: value={28'b0,snapshot[147:144]};
            32'h20000014: value={16'b0,snapshot[143:128]};
            32'h20000018: value=snapshot[127:96];
            32'h2000001c: value=snapshot[95:64];
            32'h20000020: value=snapshot[63:32];
            32'h20000024: value=snapshot[31:0];
            default: begin end
        endcase
        bridge_data={value[7:0],value[15:8],value[23:16],value[31:24]};
    end
endmodule
