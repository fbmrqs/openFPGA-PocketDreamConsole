module pdc_rom_cache #(parameter integer INDEX_BITS = 12, parameter logic BURST_LINES = 0, parameter logic REQUEST_STAGED = 0, parameter logic FAST_LINE = 0, parameter logic HASH_INDEX = 0) (
    input logic clk, reset, invalidate,
    input logic hash_enable,
    input logic request,
    input logic [24:0] address,
    output logic ack,
    output logic [15:0] data,
    output logic [255:0] line_data,
    output logic memory_request,
    output logic [24:0] memory_address,
    input logic memory_ack,
    input logic [15:0] memory_data,
    input logic memory_line_valid,
    input logic [255:0] memory_line_data
);
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (!reset && BURST_LINES && memory_ack && memory_request && !memory_line_valid)
            $fatal(1,"Burst cache received an incomplete ROM line");
`endif
    // Separate word banks fill a cache line atomically. Capacity is configurable.
    logic [15:0] ram_q [0:15];
    (* ramstyle = "M10K, no_rw_check" *) logic [21-INDEX_BITS:0] tags [0:(1<<INDEX_BITS)-1];
    logic [21-INDEX_BITS:0] tag_stage;
    logic [15:0] hit_word;
    (* preserve, dont_merge *) logic [1:0] group_word [0:3];
    logic [INDEX_BITS-1:0] clear_index;
    (* preserve, dont_retime *) logic clear_last;
    logic clear_drain_done;
    logic [24:0] pending;
    logic [3:0] fill_offset;
    typedef enum logic [6:0] {IDLE=7'h01, LOOKUP=7'h02, FILL=7'h04, REPLY=7'h08, RELEASE=7'h10, CLEAR_TAGS=7'h20, CLEAR_DRAIN=7'h40} state_t;
    (* preserve, dont_retime *) state_t state;
    logic [15:0] fill_data, fill_group [0:3];
    logic wanted_word, native_reply;
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (!reset && !invalidate && !$onehot(state))
            $fatal(1,"Cache state is not one-hot");
    always_ff @(posedge clk)
        if (!reset && !invalidate && state[$clog2(CLEAR_TAGS)] && clear_last!=(&clear_index))
            $fatal(1,"Prepared cache clear boundary differs from current tag");
    logic [24:0] previous_address;
    always_ff @(posedge clk) begin
        previous_address<=address;
        if (!reset && !invalidate && REQUEST_STAGED && request && state[$clog2(IDLE)] && previous_address!=address)
            $fatal(1,"Staged cache request arrived without its address lookahead");
    end
`endif
    (* preserve, dont_merge *) logic tag_write_pending;
    (* preserve, dont_merge, dont_retime, maxfan=4 *) logic [INDEX_BITS-1:0] tag_write_address;
    (* preserve, dont_merge *) logic [21-INDEX_BITS:0] tag_write_data;
    logic hit_response;
    logic front_valid;
    logic [20:0] front_address;
    wire front_hit=FAST_LINE && front_valid && front_address==address[24:4];
    logic use_hash;
    always_ff @(posedge clk) if (reset) use_hash<=HASH_INDEX && hash_enable;
    function automatic logic [INDEX_BITS-1:0] cache_index(input logic [24:0] key,input logic hashed);
        localparam integer ROTATE=INDEX_BITS>4 ? 4 : 1;
        logic [INDEX_BITS-1:0] upper;
        upper=INDEX_BITS'(key[24:INDEX_BITS+4]);
        // Keep tags intact; folding spreads aliased texture pages across sets.
        return key[INDEX_BITS+3:4] ^ (HASH_INDEX && hashed ? ((upper<<ROTATE)|(upper>>(INDEX_BITS-ROTATE))) : INDEX_BITS'(0));
    endfunction
    assign data=hit_response ? hit_word : fill_data;
    // Requesters hold address until acknowledgment, including the read stages.
    wire [INDEX_BITS-1:0] read_index = cache_index(address,use_hash);
    // Sixteen word banks let a native SDRAM reply fill a whole cache line
    // atomically; the word interface remains available to simple responders.
    genvar bank;
    generate
    for (bank=0;bank<16;bank=bank+1) begin : cache_bank
        wire bank_write = !reset && !invalidate && state[$clog2(FILL)] && memory_ack && memory_request &&
            (BURST_LINES || memory_line_valid || fill_offset==4'(bank));
        pdc_cache_bank #(.INDEX_BITS(INDEX_BITS), .WRITE_AT_READ_ADDRESS(1'b1),.READ_STAGED(1'b0)) storage (.clk(clk), .write(bank_write), .write_address(cache_index(pending,use_hash)),
            .write_data(BURST_LINES || memory_line_valid ? memory_line_data[bank*16 +:16] : memory_data),
            .read_address(read_index), .read_data(ram_q[bank]));
    end
    endgenerate
    always_ff @(posedge clk) begin
        clear_drain_done<=state[$clog2(CLEAR_DRAIN)];
        if (reset || invalidate) clear_last<=0;
        else clear_last<=state[$clog2(CLEAR_TAGS)] ? clear_index==INDEX_BITS'((1<<INDEX_BITS)-2) : &clear_index;
        wanted_word<=fill_offset==pending[3:0];
        for (int group_index=0;group_index<4;group_index++) begin
            group_word[group_index]<=address[1:0];
            fill_group[group_index]<=memory_line_data[(group_index*4+int'(group_word[group_index]))*16 +:16];
        end
        tag_write_pending<=!reset && !invalidate && (state[$clog2(CLEAR_TAGS)] ||
            (state[$clog2(FILL)] && memory_ack && memory_request && (BURST_LINES || memory_line_valid || fill_offset==15)));
        tag_write_address<=state[$clog2(CLEAR_TAGS)] ? clear_index : cache_index(pending,use_hash);
        tag_write_data<=state[$clog2(CLEAR_TAGS)] ? '0 : {1'b1,pending[24:INDEX_BITS+4]};
        tag_stage<=tags[read_index];
        if (!reset && !invalidate && tag_write_pending) tags[tag_write_address]<=tag_write_data;
    end
    always_ff @(posedge clk) begin
        if (BURST_LINES) fill_data<=fill_group[pending[3:2]];
        ack <= 0;
        if (reset || invalidate) begin
            clear_index<=0;state<=CLEAR_TAGS;memory_request<=0;
            memory_address <= 0; pending <= 0; fill_offset <= 0; if (!BURST_LINES) fill_data <= 0;hit_response<=0;hit_word<=0;line_data<='0;front_valid<=0;front_address<=0;
        end else begin
        unique case (1'b1)
            state[$clog2(CLEAR_TAGS)]: begin
                state<=CLEAR_TAGS;
                if (clear_last) state<=CLEAR_DRAIN;
                else clear_index<=clear_index+INDEX_BITS'(1);
            end
            state[$clog2(CLEAR_DRAIN)]: begin
                state<=CLEAR_DRAIN;
                if (clear_drain_done) state<=IDLE;
            end
            state[$clog2(IDLE)]: begin
                state<=IDLE;pending<=address;memory_address<={address[24:4],4'b0};fill_offset<=0;
                if (request) begin
                    if (front_hit) begin
                        hit_word<=line_data[address[3:0]*16 +:16];hit_response<=1;ack<=1;state<=RELEASE;
                    end else state<=LOOKUP;
                end
            end
            state[$clog2(LOOKUP)]: ;
            state[$clog2(FILL)]: begin
                state<=FILL;
                if (memory_ack && memory_request) begin
                memory_request <= 0;
                if (BURST_LINES || memory_line_valid) line_data<=memory_line_data;
                else line_data[fill_offset*16 +:16]<=memory_data;
                if (!BURST_LINES && !memory_line_valid && wanted_word) fill_data<=memory_data;
                if (BURST_LINES || memory_line_valid || fill_offset == 15) begin
                    front_valid<=1;front_address<=pending[24:4];
                    native_reply<=BURST_LINES || memory_line_valid;state<=REPLY;
                end else begin
                    fill_offset <= fill_offset + 4'd1;
                    memory_address[3:0] <= memory_address[3:0] + 4'd1;
                end
                end else if (!memory_request) memory_request <= 1;
            end
            state[$clog2(REPLY)]: begin
                if (!BURST_LINES && native_reply) fill_data<=fill_group[pending[3:2]];
                ack<=1;state<=RELEASE;
            end
            state[$clog2(RELEASE)]: begin state<=RELEASE;if (!request) state<=IDLE;end
            default: state <= IDLE;
        endcase
        if (state[$clog2(LOOKUP)] || (REQUEST_STAGED && request && state[$clog2(IDLE)] && !front_hit)) begin
            if (tag_stage=={1'b1,address[24:INDEX_BITS+4]}) begin
                front_valid<=1;front_address<=address[24:4];
                for (int word_index=0;word_index<16;word_index++) line_data[word_index*16 +:16]<=ram_q[word_index];
                hit_word<=ram_q[address[3:0]];hit_response<=1;ack<=1;state<=RELEASE;
            end else begin hit_response<=0;memory_request<=1;state<=FILL;end
        end
        end
    end
endmodule

// RAM clients may stage addresses locally; ROM caches use the primitive read register.
module pdc_cache_bank #(parameter integer INDEX_BITS = 12, parameter integer WORDS = 1<<INDEX_BITS, parameter logic WRITE_AT_READ_ADDRESS = 0, parameter logic READ_STAGED = 1) (
    input logic clk, write,
    input logic [INDEX_BITS-1:0] write_address, read_address,
    input logic [15:0] write_data,
    output logic [15:0] read_data
);
    // Writes commit in the release phase; optional read staging serves RAM clients.
    (* preserve, dont_merge, dont_retime, maxfan = 4 *) logic [INDEX_BITS-1:0] stored_write_address;
    (* preserve, dont_merge *) logic [15:0] stored_write_data;
    (* preserve, dont_merge *) logic write_pending;
    (* preserve, dont_merge, dont_retime, maxfan = 4 *) logic [INDEX_BITS-1:0] local_read_address;
    wire [INDEX_BITS-1:0] bank_read_address=READ_STAGED ? local_read_address : read_address;
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (WRITE_AT_READ_ADDRESS && write && local_read_address!=write_address)
            $fatal(1,"Cache fill address differs from local bank read address");
`endif
    always_ff @(posedge clk) begin
        local_read_address<=read_address;
        stored_write_address<=WRITE_AT_READ_ADDRESS ? local_read_address : write_address;stored_write_data<=write_data;write_pending<=write;
    end
`ifdef ALTERA_RESERVED_QIS
    altsyncram #(
        .lpm_type("altsyncram"), .operation_mode("DUAL_PORT"), .intended_device_family("Cyclone V"), .ram_block_type("M10K"),
        .width_a(16), .width_b(16), .widthad_a(INDEX_BITS), .widthad_b(INDEX_BITS),
        .numwords_a(WORDS), .numwords_b(WORDS),
        .address_reg_b("CLOCK0"), .outdata_reg_b("UNREGISTERED"),
        .clock_enable_input_a("BYPASS"), .clock_enable_input_b("BYPASS"),
        .clock_enable_output_b("BYPASS"), .read_during_write_mode_mixed_ports("DONT_CARE"),
        .power_up_uninitialized("FALSE")
    ) memory (
        .clock0(clk), .clock1(1'b1), .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
        .aclr0(1'b0), .aclr1(1'b0), .addressstall_a(1'b0), .addressstall_b(1'b0),
        .wren_a(write_pending), .address_a(stored_write_address), .data_a(stored_write_data),
        .wren_b(1'b0), .address_b(bank_read_address), .data_b(16'b0), .q_a(), .q_b(read_data),
        .rden_a(1'b1), .rden_b(1'b1), .byteena_a(1'b1), .byteena_b(1'b1), .eccstatus()
    );
`else
    logic [15:0] words [0:WORDS-1];
    always_ff @(posedge clk) begin
        if (write_pending) words[stored_write_address]<=stored_write_data;
`ifdef PDC_POISON_COLLISIONS
        read_data<=write_pending && stored_write_address==bank_read_address ? 16'hdead : words[bank_read_address];
`else
        read_data<=words[bank_read_address];
`endif
    end
`endif
endmodule
