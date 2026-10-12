module pdc_dma (
    input logic clk, reset, start,
    input logic [21:0] source,
    input logic [13:0] target,
    input logic [15:0] length,
    input logic sprite_transfer,
    output logic busy, done,
    output logic [21:0] current_source,
    output logic [13:0] current_target,
    output logic [15:0] remaining,
    output logic request, write,
    output logic [21:0] address,
    output logic [15:0] write_data,
    input logic ack,
    input logic [15:0] read_data
);
    typedef enum logic [2:0] {IDLE, READ, READ_WAIT, WRITE, WRITE_WAIT, NEXT, FINISH} state_t;
    state_t state;
    logic sprite_mode;
    always_ff @(posedge clk) begin
        done <= 0;
        if (reset) begin
            state <= IDLE; busy <= 0; request <= 0; write <= 0; address <= 0; write_data <= 0;
            current_source <= 0; current_target <= 0; remaining <= 0; sprite_mode <= 0;
        end else case (state)
            IDLE: if (start) begin
                current_source <= source; current_target <= target; remaining <= length;
                sprite_mode <= sprite_transfer; busy <= 1; state <= READ;
            end
            READ: begin
                address <= current_source;
                if (remaining==0) state <= FINISH;
                else begin request <= 1; write <= 0; state <= READ_WAIT; end
            end
            READ_WAIT: if (ack) begin request <= 0; write_data <= read_data; state <= WRITE; end
            WRITE: begin
                request <= 1; write <= 1;
                address <= sprite_mode ? {8'b0,4'hb,current_target[9:0]} : {8'b0,current_target};
                state <= WRITE_WAIT;
            end
            WRITE_WAIT: if (ack) begin request <= 0; state <= NEXT; end
            NEXT: begin
                current_source <= sprite_mode ? {6'b0,current_source[15:0]+16'd1} : current_source+22'd1;
                current_target <= sprite_mode ? {4'b0,current_target[9:0]+10'd1} : current_target+14'd1;
                remaining <= remaining-16'd1; state <= READ;
            end
            FINISH: begin done <= 1; busy <= 0; state <= IDLE; end
            default: state <= IDLE;
        endcase
    end
endmodule
