module rom_path_tb (
    input logic reset, bridge_clk, system_clk, memory_clk,
    input logic slot_write, slot_complete,
    input logic [15:0] slot_id,
    input logic [31:0] slot_size, bridge_address, bridge_data,
    input logic bridge_write,
    output logic slot_ok, rom_ready,
    output logic [2:0] final_bank,
    output logic load_fault,
    output wire [31:0] load_crc, write_crc,
    input logic check_enable,
    input logic rom_request,
    input logic [24:0] rom_address,
    output logic rom_ack,
    output logic [15:0] rom_data,
    output logic rom_line_valid,
    output logic [255:0] rom_line_data,
    output logic word_write,
    output logic [23:0] word_address,
    output logic [31:0] word_data,
    input logic word_done,
    output logic burst_read,
    output logic [24:0] burst_address,
    output wire [3:0] check_status,
    output wire check_done,
    output wire [31:0] first_crc, second_crc,
    input logic burst_valid, burst_done,
    input logic [15:0] burst_data
);
    wire check_request;
    wire [24:0] check_address;
    pdc_rom_store store (
        .reset,.bridge_clk,.system_clk,.memory_clk,
        .slot_write,.slot_complete,.slot_id,.slot_size,.bridge_address,.bridge_data,.bridge_write,
        .slot_ok,.rom_ready,.final_bank,.load_fault,.load_crc,.write_crc,
        .rom_request(check_enable ? check_request : rom_request),
        .rom_address(check_enable ? check_address : rom_address),
        .rom_ack,.rom_data,.rom_line_valid,.rom_line_data,
        .word_write,.word_address,.word_data,.word_done,
        .burst_read,.burst_address,.burst_valid,.burst_done,.burst_data);
    pdc_rom_check #(.BANK_WORDS_BITS(8),.VECTOR_LINE(22'h30),
                    .SINGLE_CRC(32'hcf964c64),.PINK_CRC(32'h95c56ca2),.PDC100_CRC(32'heb971541)) check_rom (
        .clk(system_clk),.reset(reset || !check_enable),.rom_ready,.final_bank,
        .loaded_crc(final_bank==0 ? 32'hcf964c64 : final_bank==1 ? 32'h95c56ca2 : 32'heb971541),.videojet_controls(),
        .rom_request(check_request),.rom_address(check_address),
        .rom_ack,.rom_line_valid,.rom_line_data,.done(check_done),.passed(),
        .status(check_status),.reset_vector(),.first_crc,.second_crc);
endmodule
