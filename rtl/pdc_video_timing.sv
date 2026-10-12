module pdc_video_timing (
    input logic clk, reset, advance,
    input logic [7:0] cycles,
    input logic register_write,
    input logic [13:0] address,
    input logic [15:0] write_data,
    output logic [15:0] read_data,
    input logic sprite_dma_done,
    output logic irq,
    output logic start_line, frame_done,
    output logic [8:0] scanline,
    output logic [7:0] render_line
);
    logic [10:0] counter;
    logic [8:0] irq_vpos, irq_hpos;
    logic [2:0] control, status;
    logic [11:0] elapsed;
    always_comb begin
        irq = |(control & status);
        read_data = 0;
        case (address)
            14'h2836: read_data={7'b0,irq_vpos};
            14'h2837: read_data={7'b0,irq_hpos};
            14'h2862: read_data={13'b0,control};
            14'h2863: read_data={13'b0,status};
            default: begin end
        endcase
        elapsed={1'b0,counter}+{4'b0,cycles};
    end
    always_ff @(posedge clk) begin
        start_line<=0;frame_done<=0;
        if (reset) begin counter<=0;scanline<=0;render_line<=0;irq_vpos<=9'h1ff;irq_hpos<=9'h1ff;control<=0;status<=0;end
        else begin
            if (register_write) case(address)
                14'h2836:irq_vpos<=write_data[8:0];14'h2837:irq_hpos<=write_data[8:0];
                14'h2862:control<=write_data[2:0];14'h2863:status<=status&~write_data[2:0];default:begin end
            endcase
            if (sprite_dma_done && control[2]) status[2]<=1;
            if (advance) begin
                if (elapsed>=1716) begin
                    counter<=11'(elapsed-12'd1716);
                    if (scanline==irq_vpos && control[1]) status[1]<=1;
                    if (scanline<240) begin
                        render_line<=scanline[7:0];start_line<=1;
                        if (scanline==239) begin if (control[0]) status[0]<=1;frame_done<=1;end
                        scanline<=scanline+9'd1;
                    end else if (scanline==261) begin scanline<=0;status[0]<=0;end
                    else scanline<=scanline+9'd1;
                end else counter<=elapsed[10:0];
            end
        end
    end
endmodule
