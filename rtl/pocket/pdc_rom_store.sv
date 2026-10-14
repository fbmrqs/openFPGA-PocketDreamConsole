module pdc_rom_store (
    input logic reset, bridge_clk, system_clk, memory_clk,
    input logic slot_write, slot_complete,
    input logic [15:0] slot_id,
    input logic [31:0] slot_size, bridge_address, bridge_data,
    input logic bridge_write,
    output logic slot_ok, rom_ready,
    output logic [2:0] final_bank,
    output logic load_fault,
    output wire [31:0] load_crc, write_crc,
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
    input logic burst_valid, burst_done,
    input logic [15:0] burst_data
);
    logic reset_bridge;
    pdc_reset_sync reset_bridge_sync (.clk(bridge_clk),.async_reset(reset),.reset(reset_bridge));
    logic reset_system;
    pdc_reset_sync reset_system_sync (.clk(system_clk),.async_reset(reset),.reset(reset_system));
    logic reset_memory;
    pdc_reset_sync reset_memory_sync (.clk(memory_clk),.async_reset(reset),.reset(reset_memory));

    // Independent CRC taps bracket the loading FIFO. Only the startup bank
    // is included, matching the two readback sweeps. These never gate traffic.
    function automatic [31:0] crc_word(input [31:0] seed, data);
        logic [31:0] value;
        value=seed;
        for (int bit_index=0;bit_index<32;bit_index++)
            value=(value>>1)^((value[0]^data[bit_index]) ? 32'hedb88320 : 32'b0);
        return value;
    endfunction
    logic [31:0] load_crc_state, write_crc_state;
    assign load_crc=~load_crc_state;
    assign write_crc=~write_crc_state;
    logic generation, complete, bridge_fault, slot_write_delayed;
    logic [24:0] expected_words, received_words;
    logic [2:0] selected_bank;
    logic load_start, fifo_reset, data_write, write_full, write_empty, write_pop, write_valid;
    logic [56:0] write_packet;
    assign slot_ok = slot_size==32'h00800000 || slot_size==32'h01000000 || slot_size==32'h04000000;
    assign load_start = slot_write && !slot_write_delayed && slot_id==1;
    assign fifo_reset = reset || load_start;
    assign data_write = bridge_write && bridge_address[31:26]==6'h04;
    always_ff @(posedge bridge_clk or posedge reset_bridge) begin
        if (reset_bridge) begin
            generation<=0;complete<=0;bridge_fault<=0;expected_words<=0;received_words<=0;selected_bank<=0;slot_write_delayed<=0;
        end else begin
            slot_write_delayed<=slot_write;
            if (load_start) begin
            generation<=!generation;complete<=0;bridge_fault<=!slot_ok;
            expected_words<=slot_size[26:2];received_words<=0;
            selected_bank<=slot_size==32'h00800000 ? 3'd0 : slot_size==32'h01000000 ? 3'd1 : 3'd7;
            end else begin
            if (data_write) begin
                if (write_full || bridge_address[1:0]!=0 || {1'b0,bridge_address[25:2]}!=received_words || received_words>=expected_words)
                    bridge_fault<=1;
                received_words<=received_words+25'd1;
            end
            if (slot_complete) begin
                complete<=1;
                if (received_words!=expected_words || expected_words==0) bridge_fault<=1;
            end
        end
        end
    end
    always_ff @(posedge bridge_clk or posedge reset_bridge)
        if (reset_bridge) load_crc_state<=32'hffffffff;
        else if (load_start) load_crc_state<=32'hffffffff;
        else if (data_write && bridge_address[25:23]==selected_bank)
            load_crc_state<=crc_word(load_crc_state,bridge_data);

    pdc_async_fifo #(.WIDTH(57),.ADDRESS_BITS(12)) writes (
        .reset(fifo_reset),.write_clk(bridge_clk),.write_en(data_write),
        .write_data({generation,bridge_address[25:2],bridge_data}),.full(write_full),
        .read_clk(memory_clk),.read_en(write_pop),.read_data(write_packet),.read_valid(write_valid),.empty(write_empty),.write_level(),.read_level());

    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] generation_sync, complete_sync, fault_sync;
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] ready_sync;
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] load_fault_sync;
    logic memory_ready, memory_generation;
    logic [24:0] committed_words;
    logic request_full, request_empty, request_pop, request_valid, sent;
    logic [24:0] request_packet;
    logic response_full, response_empty, response_push, response_valid;
    logic [280:0] response_packet, response_input;
    logic [255:0] system_line;
    logic [20:0] system_line_tag;
    logic system_line_valid;
    (* preserve, dont_retime, maxfan = 32 *) logic response_accepted;
    logic [280:0] accepted_response;
    assign rom_line_valid=system_line_valid;
    assign rom_line_data=system_line;
    wire system_line_hit=system_line_valid && system_line_tag==rom_address[24:4];
    pdc_async_fifo #(.WIDTH(25),.ADDRESS_BITS(2)) requests (
        .reset(fifo_reset),.write_clk(system_clk),.write_en(rom_request && !sent && !system_line_hit && !request_full),
        .write_data(rom_address),.full(request_full),.read_clk(memory_clk),.read_en(request_pop),
        .read_data(request_packet),.read_valid(request_valid),.empty(request_empty),.write_level(),.read_level());
    pdc_async_fifo #(.WIDTH(281),.ADDRESS_BITS(2)) responses (
        .reset(fifo_reset),.write_clk(memory_clk),.write_en(response_push),.write_data(response_input),.full(response_full),
        .read_clk(system_clk),.read_en(!response_empty),.read_data(response_packet),.read_valid(response_valid),.empty(response_empty),.write_level(),.read_level());
    always_ff @(posedge system_clk or posedge reset_system) begin
        if (reset_system) begin
            sent<=0;rom_ack<=0;rom_data<=0;ready_sync<=0;rom_ready<=0;final_bank<=0;load_fault<=0;load_fault_sync<=0;
            system_line<=0;system_line_tag<=0;system_line_valid<=0;
            response_accepted<=0;accepted_response<=0;
        end
        else begin
            response_accepted<=response_valid && rom_request && sent && response_packet[280:256]==rom_address;
            if (response_valid) accepted_response<=response_packet;
            ready_sync<={ready_sync[0],memory_ready};
            load_fault_sync<={load_fault_sync[0],bridge_fault};
            rom_ready<=ready_sync[1];final_bank<=selected_bank;load_fault<=load_fault_sync[1];
            rom_ack<=0;
            if (!ready_sync[1]) system_line_valid<=0;
            if (!rom_request) sent<=0;
            else if (!sent) begin
                if (system_line_hit) begin
                    sent<=1;rom_data<=system_line[rom_address[3:0]*16 +:16];rom_ack<=1;
                end else if (!request_full) sent<=1;
            end
            if (response_accepted) begin
                system_line<=accepted_response[255:0];system_line_tag<=accepted_response[280:260];system_line_valid<=1;
                if (rom_request && sent && accepted_response[280:256]==rom_address) begin
                    rom_data<=accepted_response[rom_address[3:0]*16 +:16];rom_ack<=1;
                end
            end
        end
    end

    logic [15:0] line_words [0:15];
    logic [20:0] line_tag;
    logic line_valid, active_generation;
    logic [24:0] active_address;
    logic [4:0] fill_count;
    typedef enum logic [2:0] {IDLE, GET_WRITE, WRITE_WAIT, GET_READ, READ_WAIT, SEND_READ} state_t;
    state_t state;
    always_ff @(posedge memory_clk or posedge reset_memory)
        if (reset_memory) write_crc_state<=32'hffffffff;
        else if (generation_sync[1]!=memory_generation) write_crc_state<=32'hffffffff;
        else if (state==WRITE_WAIT && word_done && active_generation==memory_generation &&
                 word_address[23:21]==selected_bank)
            write_crc_state<=crc_word(write_crc_state,word_data);
    assign write_pop = state==IDLE && !write_empty;
    assign request_pop = state==IDLE && write_empty && memory_ready && !request_empty;
    always_ff @(posedge memory_clk or posedge reset_memory) begin
        if (reset_memory) begin
            generation_sync<=0;complete_sync<=0;fault_sync<=0;memory_generation<=0;
            memory_ready<=0;committed_words<=0;line_valid<=0;line_tag<=0;fill_count<=0;
            state<=IDLE;word_write<=0;word_address<=0;word_data<=0;
            burst_read<=0;burst_address<=0;response_push<=0;response_input<=0;
            active_address<=0;active_generation<=0;
        end else begin
            generation_sync<={generation_sync[0],generation};
            complete_sync<={complete_sync[0],complete};fault_sync<={fault_sync[0],bridge_fault};
            word_write<=0;burst_read<=0;response_push<=0;
            if (generation_sync[1]!=memory_generation) begin
                memory_generation<=generation_sync[1];committed_words<=0;memory_ready<=0;line_valid<=0;
            end else if (complete_sync[1] && !fault_sync[1] && committed_words==expected_words && expected_words!=0)
                memory_ready<=1;
            if (fault_sync[1]) memory_ready<=0;
            case (state)
                IDLE: if (write_pop) state<=GET_WRITE;else if (request_pop) state<=GET_READ;
                GET_WRITE: if (write_valid) begin
                    word_address<=write_packet[55:32];word_data<=write_packet[31:0];
                    active_generation<=write_packet[56];word_write<=1;state<=WRITE_WAIT;
                end
                WRITE_WAIT: if (word_done) begin
                    if (active_generation==memory_generation && generation_sync[1]==memory_generation)
                        committed_words<=committed_words+25'd1;
                    state<=IDLE;
                end
                GET_READ: if (request_valid) begin
                    active_address<=request_packet;active_generation<=memory_generation;
                    if (line_valid && line_tag==request_packet[24:4]) state<=SEND_READ;
                    else begin
                        line_valid<=0;line_tag<=request_packet[24:4];fill_count<=0;
                        burst_address<={request_packet[24:4],4'b0};burst_read<=1;state<=READ_WAIT;
                    end
                end
                READ_WAIT: begin
                    if (burst_valid && fill_count<16) begin line_words[fill_count[3:0]]<=burst_data;fill_count<=fill_count+5'd1;end
                    if (burst_done) begin
                        line_valid<=active_generation==memory_generation && (fill_count==16 || (fill_count==15 && burst_valid));
                        state<=SEND_READ;
                    end
                end
                SEND_READ: if (!response_full) begin
                    if (active_generation==memory_generation) begin
                        response_input[280:256]<=active_address;
                        for (int word_index=0;word_index<16;word_index++)
                            response_input[word_index*16 +:16]<=line_words[word_index];
                        response_push<=1;
                    end
                    state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
