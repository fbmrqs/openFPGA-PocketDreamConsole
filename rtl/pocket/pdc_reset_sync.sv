module pdc_reset_sync (
    input logic clk, async_reset,
    output logic reset
);
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] pipeline;
    assign reset=pipeline[1];
    always_ff @(posedge clk or posedge async_reset)
        if (async_reset) pipeline<=2'b11;else pipeline<={pipeline[0],1'b0};
endmodule
