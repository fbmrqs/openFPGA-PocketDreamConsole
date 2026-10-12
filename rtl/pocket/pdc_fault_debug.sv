module pdc_fault_debug (
    input wire clk, reset,
    input wire cpu_fault,
    input wire [21:0] fault_pc,
    input wire [15:0] fault_opcode,
    input wire [31:0] bridge_address,
    output logic [31:0] bridge_data
);
    // The CPU holds the payload while fault is asserted. Delay its validity
    // beyond the payload synchronizer, then retain one coherent snapshot.
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [2:0] fault_sync;
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [37:0] payload_sync_1, payload_sync_2;
    logic captured;
    logic [21:0] pc_snapshot;
    logic [15:0] opcode_snapshot;
    always_ff @(posedge clk or posedge reset)
        if (reset) begin
            fault_sync<=0;payload_sync_1<=0;payload_sync_2<=0;
            captured<=0;pc_snapshot<=0;opcode_snapshot<=0;
        end else begin
            fault_sync<={fault_sync[1:0],cpu_fault};
            payload_sync_1<={fault_pc,fault_opcode};
            payload_sync_2<=payload_sync_1;
            if (!fault_sync[2]) begin
                captured<=0;pc_snapshot<=0;opcode_snapshot<=0;
            end else if (!captured) begin
                captured<=1;
                {pc_snapshot,opcode_snapshot}<=payload_sync_2;
            end
        end

    // Compensate for the APF peripheral's little-endian byte reversal so
    // Core Settings displays the actual numeric PC and opcode.
    always_comb begin
        bridge_data=0;
        case (bridge_address)
            32'h20000008: bridge_data={pc_snapshot[7:0],pc_snapshot[15:8],2'b0,pc_snapshot[21:16],8'b0};
            32'h2000000c: bridge_data={opcode_snapshot[7:0],opcode_snapshot[15:8],16'b0};
            default: begin end
        endcase
    end
endmodule
