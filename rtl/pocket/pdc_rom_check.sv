module pdc_rom_check #(
    parameter integer BANK_WORDS_BITS=22,
    parameter logic [21:0] VECTOR_LINE=22'h00fff0,
    parameter logic [31:0] PINK_CRC=32'h0c1dc0f3,
    parameter logic [31:0] PDC100_CRC=32'hccd6c6d3
) (
    input logic clk, reset, rom_ready,
    input logic [2:0] final_bank,
    output logic rom_request,
    output wire [24:0] rom_address,
    input logic rom_ack, rom_line_valid,
    input logic [255:0] rom_line_data,
    output wire done, passed,
    output logic [3:0] status,
    output logic [15:0] reset_vector,
    output logic [31:0] first_crc, second_crc
);
    typedef enum logic [1:0] {WAIT_READY, WAIT_LINE, CRC_BITS, DONE} state_t;
    state_t state;
    logic [2:0] bank;
    logic [21:0] offset;
    logic second_pass;
    logic [7:0] bit_index;
    logic [255:0] line_bits;
    logic [31:0] crc, expected_crc;
    wire [31:0] next_crc=(crc>>1) ^ ((crc[0]^line_bits[0]) ? 32'hedb88320 : 32'b0);
    assign rom_address={bank,offset};
    assign done=status[0];
    assign passed=status==4'b0111;

    // CRC-32/ISO-HDLC over little-endian ROM bytes, low bit first. Two full
    // bank sweeps force fresh SDRAM reads instead of reusing one cached line.
    always_ff @(posedge clk) begin
        if (reset || !rom_ready) begin
            state<=WAIT_READY;rom_request<=0;bank<=0;offset<=0;
            second_pass<=0;bit_index<=0;line_bits<=0;crc<=32'hffffffff;expected_crc<=0;
            status<=0;reset_vector<=0;first_crc<=0;second_crc<=0;
        end else case (state)
            WAIT_READY: begin
                bank<=final_bank;expected_crc<=final_bank==1 ? PINK_CRC : PDC100_CRC;
                rom_request<=1;state<=WAIT_LINE;
            end
            WAIT_LINE: if (rom_ack) begin
                rom_request<=0;
                if (!rom_line_valid) begin status<=4'b1001;state<=DONE;end
                else begin
                    line_bits<=rom_line_data;bit_index<=0;state<=CRC_BITS;
                    if (!second_pass && offset==VECTOR_LINE) reset_vector<=rom_line_data[112 +:16];
                end
            end
            CRC_BITS: begin
                crc<=next_crc;line_bits<=line_bits>>1;bit_index<=bit_index+8'd1;
                if (&bit_index) begin
                    if (&offset[BANK_WORDS_BITS-1:4]) begin
                        if (!second_pass) begin
                            first_crc<=~next_crc;status[1]<=~next_crc==expected_crc;
                            second_pass<=1;offset<=0;crc<=32'hffffffff;
                            rom_request<=1;state<=WAIT_LINE;
                        end else begin
                            second_crc<=~next_crc;status[2]<=~next_crc==expected_crc;
                            status[0]<=1;state<=DONE;
                        end
                    end else begin
                        offset<=offset+22'd16;rom_request<=1;state<=WAIT_LINE;
                    end
                end
            end
            DONE: begin end
            default: begin status<=4'b1001;rom_request<=0;state<=DONE;end
        endcase
    end
endmodule
