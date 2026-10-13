// Instruction semantics follow third_party/veesem/core/spg200/cpu.cpp (ISC).
module unsp_cpu (
    input logic clk, reset, run,
    input logic prefetch_enable,
    input logic [7:0] irq,
    input logic fiq,
    input logic ds_write,
    input logic [5:0] ds_value,
    output logic [5:0] ds,
    output logic [21:0] pc,
    output logic bus_valid, bus_write, bus_external,
    (* maxfan = 8 *) output logic [21:0] bus_addr,
    output logic [15:0] bus_wdata,
    input logic bus_ack,
    input logic [15:0] bus_rdata,
    output logic retired, interrupt_entry,
    output logic [7:0] cycles,
    output logic fault,
    output logic [21:0] fault_pc,
    output logic [15:0] fault_opcode,
    output logic [127:0] registers,
    output logic [11:0] shifts,
    output logic [4:0] modes
);
    // One-hot state bits keep register enables out of a binary decode chain.
    typedef enum logic [34:0] {
        RESET_VECTOR = 35'd1 << 0,
        RESET_DONE = 35'd1 << 1,
        BOUNDARY = 35'd1 << 2,
        WAIT_BUS = 35'd1 << 3,
        FETCHED = 35'd1 << 4,
        DECODE = 35'd1 << 5,
        ALU = 35'd1 << 6,
        WRITE_ALU = 35'd1 << 7,
        IMMEDIATE = 35'd1 << 8,
        INDIRECT = 35'd1 << 9,
        INDIRECT_UPDATE = 35'd1 << 10,
        INDIRECT_ACCESS = 35'd1 << 11,
        MEMORY_ALU = 35'd1 << 12,
        PUSH = 35'd1 << 13,
        PUSH_DONE = 35'd1 << 14,
        POP = 35'd1 << 15,
        POP_DONE = 35'd1 << 16,
        ENTRY_PC = 35'd1 << 17,
        ENTRY_SR = 35'd1 << 18,
        ENTRY_VECTOR = 35'd1 << 19,
        ENTRY_DONE = 35'd1 << 20,
        TARGET = 35'd1 << 21,
        CALL_PC = 35'd1 << 22,
        CALL_SR = 35'd1 << 23,
        CALL_DONE = 35'd1 << 24,
        MAC_A = 35'd1 << 25,
        MAC_B = 35'd1 << 26,
        MAC_ACC = 35'd1 << 27,
        MAC_WRITE = 35'd1 << 28,
        MAC_NEXT = 35'd1 << 29,
        HALTED = 35'd1 << 30,
        PREFETCH_DONE = 35'd1 << 31,
        BRANCH = 35'd1 << 32,
        MAC_PRODUCT = 35'd1 << 33,
        SHIFT = 35'd1 << 34
    } state_t;
    state_t state, resume_state;
    logic [15:0] r [0:7];
    logic [3:0] sb [0:2];
    logic in_irq, in_fiq, irq_enable, fiq_enable, fir_move;
    logic [15:0] iw, data_word, immediate_word, old_mac;
    (* preserve *) logic [15:0] a, captured_b;
    (* preserve, dont_retime *) logic [15:0] fetched_b, fetched_arithmetic_b;
    logic fetched_arithmetic_carry, b_from_fetch;
    wire [15:0] b=b_from_fetch ? fetched_b : captured_b;
    (* preserve *) logic [11:0] operand_form;
    logic [21:0] instruction_pc, address, target_pc;
    logic [3:0] op;
    logic [2:0] rd, rs;
    logic [5:0] mode;
    logic [4:0] remaining, total, mac_index;
    logic [3:0] stack_reg;
    logic [31:0] accumulator;
    logic signed [32:0] product;
    logic [31:0] registered_product;
    always_ff @(posedge clk) registered_product<=product[31:0];
    logic signed [16:0] multiplier_a;
    logic signed [15:0] multiplier_b;
    wire [15:0] multiplier_a_value=state[$clog2(MAC_B)] ? data_word :
        state[$clog2(DECODE)] && rd==6 ? r[6] : a;
    (* preserve *) logic [15:0] mac_rd_next, mac_rs_next;
    logic [15:0] alu_result, status_result;
    logic [16:0] wide_result;
    logic [15:0] captured_arithmetic_b;
    logic captured_arithmetic_carry, arithmetic_negative;
    wire [15:0] arithmetic_b=b_from_fetch ? fetched_arithmetic_b : captured_arithmetic_b;
    wire arithmetic_carry=b_from_fetch ? fetched_arithmetic_carry : captured_arithmetic_carry;
    (* preserve, dont_merge *) logic operand_subtract, operand_status_carry;
    logic [17:0] arithmetic_result;
    logic [9:0] arithmetic_low;
    logic [8:0] arithmetic_high_zero, arithmetic_high_one;
    logic alu_valid, alu_saves, arithmetic, branch_taken;
    (* preserve *) logic [5:0] alu_select;
    logic alu_save;
    integer i, shift_index, n;
    (* preserve, dont_retime *) logic [2:0] shift_amount;
    (* preserve, dont_retime *) logic [1:0] prepared_shift_index;
    (* preserve, dont_retime *) logic [19:0] shift_operand;
    wire [15:0] shift_source=rs[2:1]==2'b11 ? (rs[0] ? r[7] : r[6]) : b;
    logic [19:0] shift_word;
    logic [21:0] next_pc, next_bus_address;
    logic next_bus_external;
    (* keep *) wire stack_bus_select=state[$clog2(ENTRY_PC)] || state[$clog2(ENTRY_SR)] ||
        state[$clog2(CALL_PC)] || state[$clog2(CALL_SR)];
    logic [6:0] branch_low;
    (* preserve *) logic [15:0] pointer;
    logic pointer_wrap;
    (* preserve *) logic [5:0] segment;
    logic prefetch_valid;
    logic [15:0] prefetch_word;
    (* preserve *) logic [5:0] branch_displacement;
    (* preserve *) logic branch_backwards;

    function automatic logic [15:0] increment16(input logic [15:0] value);
        return {8'(value[15:8]+8'(&value[7:0])),8'(value[7:0]+8'd1)};
    endfunction
    function automatic logic [15:0] decrement16(input logic [15:0] value);
        return {8'(value[15:8]-8'(~|value[7:0])),8'(value[7:0]-8'd1)};
    endfunction
    function automatic logic [15:0] increment_pointer(input logic [15:0] value,input logic twice);
        return {8'(value[15:8]+8'(twice ? &value[7:1] : &value[7:0])),
                8'(value[7:0]+(twice ? 8'd2 : 8'd1))};
    endfunction

    function automatic logic branch_condition(input logic [3:0] opcode,input logic [15:0] status);
        case (opcode)
            0: return !status[6];
            1: return status[6];
            2: return !status[7];
            3: return status[7];
            4: return !status[8];
            5: return status[8];
            6: return !status[9];
            7: return status[9];
            8: return status[8] || !status[6];
            9: return !status[8] && status[6];
            10: return status[8] || status[7];
            11: return !status[8] && !status[7];
            12: return status[9] == status[7];
            13: return status[9] != status[7];
            14: return 1;
            default: return 0;
        endcase
    endfunction

    always_comb begin
        registers = '0;
        for (int k = 0; k < 8; k++) registers[k*16 +: 16] = r[k];
        shifts = {sb[2], sb[1], sb[0]};
        modes = {fir_move, fiq_enable, irq_enable, in_fiq, in_irq};
        ds = r[6][15:10];
        pc = {r[6][5:0], r[7]};
        alu_valid = |alu_select;
        alu_saves = alu_save;
        arithmetic = alu_select[0];
        wide_result = '0;

        // The low bit injects carry into one adder instead of two serial adds.
        arithmetic_low={1'b0,a[7:0],1'b1}+{1'b0,arithmetic_b[7:0],arithmetic_carry};
        arithmetic_high_zero={1'b0,a[15:8]}+{1'b0,arithmetic_b[15:8]};
        arithmetic_high_one=9'(({1'b0,a[15:8],1'b1}+{1'b0,arithmetic_b[15:8],1'b1})>>1);
        arithmetic_result={arithmetic_low[9] ? arithmetic_high_one : arithmetic_high_zero,arithmetic_low[8:0]};
        arithmetic_negative=a[15]==arithmetic_b[15] ? a[15] : !arithmetic_result[17];
        unique case (1'b1)
            alu_select[0]: wide_result=arithmetic_result[17:1];
            alu_select[1]: wide_result = {~|b,increment16(~b)};
            alu_select[2]: wide_result = {1'b0,a ^ b};
            alu_select[3]: wide_result = {1'b0,b};
            alu_select[4]: wide_result = {1'b0,a | b};
            alu_select[5]: wide_result = {1'b0,a & b};
            default: wide_result = 0;
        endcase
        alu_result = wide_result[15:0];
        status_result = r[6];
        if (rd != 7) begin
            status_result[9] = alu_result[15];
            status_result[8] = alu_result == 0;
            if (arithmetic) begin
                status_result[7] = arithmetic_negative;
                status_result[6] = wide_result[16];
            end
        end
        branch_taken=branch_condition(op,r[6]);
        product = 33'(multiplier_a)*33'(multiplier_b);
    end

    always_ff @(posedge clk) begin
        prepared_shift_index<=in_fiq ? 2'd2 : in_irq ? 2'd1 : 2'd0;
        shift_amount<={1'b0,iw[4:3]}+3'd1;
        shift_operand<=operand_form[7] || operand_form[9] ?
            {sb[in_fiq ? 2 : in_irq ? 1 : 0],shift_source} :
            {shift_source,sb[in_fiq ? 2 : in_irq ? 1 : 0]};
    end

    (* preserve, dont_retime *) logic [15:0] stack_increment, stack_decrement;
    wire [15:0] stack_operand=state[$clog2(POP_DONE)] && stack_reg[2:0]==rs ? data_word : r[rs];
    always_ff @(posedge clk) begin
        stack_increment<=increment16(stack_operand);stack_decrement<=decrement16(stack_operand);
    end
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (!reset && ((state[$clog2(PUSH)] && stack_decrement!=decrement16(r[rs])) ||
            (state[$clog2(POP)] && stack_increment!=increment16(r[rs]))))
            $fatal(1,"Stack pointer lookahead differs from architectural register");
`endif
    (* preserve, dont_retime *) logic [15:0] mac_rd_address,mac_rs_address;
    always_ff @(posedge clk) begin
        mac_rd_address<=state[$clog2(MAC_NEXT)] ? (rs==rd ? mac_rs_next : mac_rd_next) : r[rd];
        mac_rs_address<=r[rs];
    end

    wire [15:0] fetch_operand=(bus_rdata[15:12]==15 || bus_rdata[8:3]==32 ||
        (bus_rdata[8:3]>=36 && bus_rdata[8:3]<56)) ? r[bus_rdata[2:0]] : {10'b0,bus_rdata[5:0]};
    always_ff @(posedge clk)
        if (state[$clog2(WAIT_BUS)] && (resume_state[$clog2(FETCHED)] || resume_state[$clog2(PREFETCH_DONE)])) begin
            fetched_b<=fetch_operand;
            fetched_arithmetic_b<=bus_rdata[15:12]>=2 ? ~fetch_operand : fetch_operand;
            fetched_arithmetic_carry<=(bus_rdata[15:12]==1 || bus_rdata[15:12]==3) ? r[6][6] : bus_rdata[15:12]>=2;
        end

    task automatic capture_b(input logic [15:0] value,input logic subtract,input logic status_carry);
        captured_b<=value;b_from_fetch<=0;
        captured_arithmetic_b<=subtract ? ~value : value;
        captured_arithmetic_carry<=status_carry ? r[6][6] : subtract;
    endtask
    task automatic read_word(input logic [21:0] addr, input state_t next_state);
        bus_valid <= 1;
        bus_write <= 0;
        next_bus_address = addr;
        next_bus_external = |addr[21:14];
        resume_state <= next_state;
        state <= WAIT_BUS;
    endtask
    task automatic write_word(input logic [21:0] addr, input logic [15:0] value, input state_t next_state);
        bus_valid <= 1;
        bus_write <= 1;
        next_bus_address = addr;
        next_bus_external = |addr[21:14];
        bus_wdata <= value;
        resume_state <= next_state;
        state <= WAIT_BUS;
    endtask
    task automatic write_return_stack(input logic [15:0] value, input state_t next_state);
        bus_valid <= 1;bus_write <= 1;bus_wdata <= value;
        resume_state <= next_state;state <= WAIT_BUS;
    endtask
    task automatic advance_pc;
        next_pc = {6'(r[6][5:0]+6'(&r[7])),increment16(r[7])};
        r[7] <= next_pc[15:0];
        r[6][5:0] <= next_pc[21:16];
    endtask
    task automatic finish(input logic [7:0] elapsed);
        cycles <= elapsed;
        retired <= 1;
        state <= BOUNDARY;
    endtask
    task automatic illegal;
        fault = 1;
        fault_pc = instruction_pc;
        fault_opcode = iw;
        state <= HALTED;
    endtask

    // Architectural writes commit together. Pointer and MAC aliases below
    // explicitly preserve the reference's ordered updates.
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (!reset && (!$onehot(state) || !$onehot(resume_state)))
            $fatal(1,"CPU state or return state is not one-hot");
    always_ff @(posedge clk)
        if (!reset && bus_valid && bus_external!=(bus_addr>=22'h4000))
            $fatal(1,"CPU external-memory classification does not match bus address");
`endif
    task automatic decode_fetched(input logic [15:0] word);
        logic [3:0] fetched_op;
        logic [2:0] fetched_rd,fetched_rs;
        logic [5:0] fetched_mode;
        fetched_op=word[15:12];fetched_rd=word[11:9];fetched_rs=word[2:0];fetched_mode=word[8:3];
        instruction_pc<={r[6][5:0],r[7]};
        iw<=word;op<=fetched_op;rd<=fetched_rd;rs<=fetched_rs;mode<=fetched_mode;
        alu_select<={fetched_op==11 || fetched_op==12,fetched_op==10,fetched_op==9,
            fetched_op==8,fetched_op==6,fetched_op<=4};
        alu_save<=!(fetched_op==4 || fetched_op==12);
        operand_subtract<=fetched_op>=2;
        operand_status_carry<=fetched_op==1 || fetched_op==3;
        operand_form<={fetched_mode>=56,fetched_mode>=52 && fetched_mode<56,
            fetched_mode>=48 && fetched_mode<52,fetched_mode>=44 && fetched_mode<48,
            fetched_mode>=40 && fetched_mode<44,fetched_mode>=36 && fetched_mode<40,
            fetched_mode>32 && fetched_mode<36,fetched_mode==32,
            fetched_mode>=24 && fetched_mode<32,fetched_mode>=16 && fetched_mode<24,
            fetched_mode>=8 && fetched_mode<16,fetched_mode<8};
        advance_pc();state<=DECODE;
        if (fetched_op<15 && fetched_mode<16 && fetched_rd==7) begin
            if (branch_condition(fetched_op,r[6])) state<=BRANCH;
            else finish(2);
        end else if (fetched_op<15 && fetched_mode>=8 && fetched_mode<16 && fetched_rd<6) begin
            cycles <= 2;state<=ALU;
        end else if (fetched_op<15 && fetched_mode>=24 && fetched_mode<32) begin
            state<=INDIRECT;
        end else if (fetched_op<15 && fetched_mode==32 && fetched_rd<6 && fetched_rs<6) begin
            cycles <= 3;state<=ALU;
        end
    endtask
    task automatic finish_prefetch(input logic [15:0] word);
        prefetch_word<=word;prefetch_valid<=1;state <= BOUNDARY;
        if (run && !(fiq && !in_fiq && fiq_enable) && !(irq!=0 && !in_irq && irq_enable)) begin
            prefetch_valid<=0;decode_fetched(word);
        end
    endtask

    always @(posedge clk) begin
        retired <= 0;
        if (reset) begin
            for (i = 0; i < 8; i = i + 1) r[i] <= 0;
            for (i = 0; i < 3; i = i + 1) sb[i] <= 0;
            in_irq <= 0; in_fiq <= 0; irq_enable <= 0; fiq_enable <= 0; fir_move <= 1;
            bus_valid <= 0; bus_write <= 0; bus_external <= 0; bus_addr <= 0; bus_wdata <= 0;
            cycles <= 0; fault = 0; fault_pc = 0; fault_opcode = 0;
            interrupt_entry = 0; iw<=0; instruction_pc<= 0;
            data_word<=0; a<= 0; captured_b <= 0;b_from_fetch<=0; accumulator = 0; old_mac = 0;

            mac_rd_next<=0;mac_rs_next<=0;
            operand_subtract<=0;operand_status_carry<=0;
            captured_arithmetic_b<=0;captured_arithmetic_carry<=0;alu_select<=6'b1;alu_save<=1;operand_form<=12'b1;
            immediate_word = 0; address = 0; target_pc = 0; op<=0;rd<=0;rs<=0;
            mode<=0;remaining = 0; total <= 0; mac_index = 0; stack_reg = 0;
            resume_state <= RESET_DONE;
            prefetch_valid<=0;prefetch_word<=0;
            branch_displacement<=0;branch_backwards<=0;
            state <= RESET_VECTOR;
        end else begin
            // Prepare an idle fetch address independently of request eligibility.
            next_bus_address=pc;next_bus_external=|pc[21:14];
            // Fetch operands are independent of the interrupt decision. Fast
            // decode excludes SR/PC aliases, which need the ordered slow path.
            if (state[$clog2(WAIT_BUS)] && (resume_state[$clog2(FETCHED)] || resume_state[$clog2(PREFETCH_DONE)])) begin
                branch_displacement<=bus_rdata[5:0];branch_backwards<=bus_rdata[6];
                a<=r[bus_rdata[11:9]];
                b_from_fetch<=1;
            end
            unique case (1'b1)
                state[$clog2(RESET_VECTOR)]: read_word(22'h00fff7, RESET_DONE);
                state[$clog2(RESET_DONE)]: begin r[7] <= data_word; state <= BOUNDARY; end
                state[$clog2(BOUNDARY)]: if (run) begin
                    interrupt_entry = 0;
                    if (fiq && !in_fiq && fiq_enable) begin
                        prefetch_valid<=0;
                        in_fiq <= 1; interrupt_entry = 1; address = 22'h00fff6; state <= ENTRY_PC;
                    end else if (irq != 0 && !in_irq && irq_enable) begin
                        prefetch_valid<=0;
                        in_irq <= 1; interrupt_entry = 1;
                        n = 7;
                        for (i = 7; i >= 0; i = i - 1) if (irq[i]) n = i;
                        address = 22'h00fff8 + 22'(n); state <= ENTRY_PC;
                    end else begin
                        instruction_pc<= {r[6][5:0],r[7]};
                        if (prefetch_valid) begin
                            prefetch_valid<=0;decode_fetched(prefetch_word);
                        end else read_word(pc, FETCHED);
                    end
                end else if (prefetch_enable && !prefetch_valid && (pc<22'h2800 || pc>=22'h4000))
                    read_word(pc,PREFETCH_DONE);
                state[$clog2(PREFETCH_DONE)]: finish_prefetch(data_word);
                state[$clog2(WAIT_BUS)]: if (bus_ack) begin
                    data_word<=bus_rdata; bus_valid <= 0;
                    if (resume_state[$clog2(FETCHED)]) begin
                        decode_fetched(bus_rdata);
                    end else if (resume_state[$clog2(PREFETCH_DONE)]) begin
                        finish_prefetch(bus_rdata);
                    end else if (resume_state[$clog2(MEMORY_ALU)]) begin
                        capture_b(bus_rdata,operand_subtract,operand_status_carry);state<=ALU;
                    end else state <= resume_state;
                end
                state[$clog2(DECODE)]: begin
                    if (op == 15) begin
                        case (iw[8:6])
                            0,4: if (rd != 7 && rs != 7 && iw[5:3] == 1) begin
                                a<= r[rd]; capture_b(r[rs],operand_subtract,operand_status_carry); state <= MAC_PRODUCT; total <= 0;
                            end else illegal();
                            1: begin read_word({r[6][5:0],r[7]}, TARGET); end
                            2: if (rd == 7) read_word({r[6][5:0],r[7]}, TARGET);
                               else if (rs != 7) begin
                                   remaining = iw[6:3] == 0 ? 5'd16 : {1'b0,iw[6:3]};
                                   total <= remaining; mac_index = 0; accumulator = 0; state <= MAC_A;
                               end else illegal();
                            3,6,7: if (rd != 7 && rs != 7) begin
                                remaining = iw[6:3] == 0 ? 5'd16 : {1'b0,iw[6:3]};
                                total <= remaining; mac_index = 0; accumulator = 0; state <= MAC_A;
                            end else illegal();
                            5: begin
                                case (iw[5:0])
                                    0,1,2,3: begin irq_enable <= iw[0]; fiq_enable <= iw[1]; finish(2); end
                                    4,5: begin fir_move <= !iw[0]; finish(2); end
                                    8,9: begin irq_enable <= iw[0]; finish(2); end
                                    12,14: begin fiq_enable <= iw[1]; finish(2); end
                                    32,40,48,56: begin address = 22'h00fff5; state <= ENTRY_PC; end
                                    37: finish(2);
                                    default: illegal();
                                endcase
                            end
                            default: illegal();
                        endcase
                    end else if ((operand_form[0] || operand_form[1]) && rd == 7) begin
                        if (op == 15) illegal();
                        else begin
                            if (branch_taken) begin
                                branch_displacement<=iw[5:0];branch_backwards<=mode>=8;
                                state <= BRANCH;
                            end else finish(2);
                        end
                    end else if (operand_form[0]) begin
                        address = {6'b0,r[5]} + {16'b0,iw[5:0]};
                        cycles <= 6;
                        if (op == 13) write_word(address,r[rd],WRITE_ALU);
                        else begin a<= r[rd]; read_word(address,MEMORY_ALU); end
                    end else if ((operand_form[0] || operand_form[1])) begin
                        a<= r[rd]; capture_b({10'b0,iw[5:0]},operand_subtract,operand_status_carry); cycles <= 2; state <= ALU;
                    end else if (operand_form[2]) begin
                        remaining = {2'b0,iw[5:3]}; total <= remaining; stack_reg = {1'b0,rd};
                        if (op == 9 && rd == 5 && iw[5:3] == 3 && rs == 0) begin
                            if (in_fiq) in_fiq <= 0; else if (in_irq) in_irq <= 0;
                            remaining = 2; total <= 2;
                        end
                        if (op == 9) state <= POP;
                        else if (op == 13) state <= PUSH;
                        else illegal();
                    end else if (operand_form[3]) state <= INDIRECT;
                    else if (operand_form[4]) begin
                        a<= r[rd]; capture_b(r[rs],operand_subtract,operand_status_carry); cycles <= rd == 7 ? 5 : 3; state <= ALU;
                    end else if (operand_form[5]) begin
                        a<= r[rs]; capture_b(r[rd],operand_subtract,operand_status_carry);
                        read_word({r[6][5:0],r[7]},IMMEDIATE);
                    end else if ((|operand_form[10:6])) begin state<=SHIFT;
                    end else begin
                        address = {16'b0,iw[5:0]}; cycles <= rd == 7 ? 6 : 5;
                        if (op == 13) write_word(address,r[rd],WRITE_ALU);
                        else begin a<= r[rd]; read_word(address,MEMORY_ALU); end
                    end
                end
                state[$clog2(SHIFT)]: begin
                        shift_index=int'(prepared_shift_index);
                        shift_word=shift_operand;
                        if (operand_form[6]) begin
                            shift_word = 20'($signed(shift_word) >>> shift_amount);
                            capture_b(shift_word[19:4],operand_subtract,operand_status_carry); sb[shift_index] <= shift_word[3:0];
                        end else if (operand_form[7]) begin
                            shift_word = shift_word << shift_amount;
                            capture_b(shift_word[15:0],operand_subtract,operand_status_carry); sb[shift_index] <= shift_word[19:16];
                        end else if (operand_form[8]) begin
                            shift_word = shift_word >> shift_amount;
                            capture_b(shift_word[19:4],operand_subtract,operand_status_carry); sb[shift_index] <= shift_word[3:0];
                        end else if (operand_form[9]) begin
                            shift_word = (shift_word << shift_amount) | (shift_word >> (5'd20-5'(shift_amount)));
                            capture_b(shift_word[15:0],operand_subtract,operand_status_carry); sb[shift_index] <= shift_word[19:16];
                        end else begin
                            shift_word = (shift_word >> shift_amount) | (shift_word << (5'd20-5'(shift_amount)));
                            capture_b(shift_word[19:4],operand_subtract,operand_status_carry); sb[shift_index] <= shift_word[3:0];
                        end
                        a<= r[rd]; cycles <= rd == 7 ? 5 : 3; state <= ALU;
                end
                state[$clog2(INDIRECT)]: begin
                    pointer = r[rs]; segment = r[6][15:10];
                    address = mode[2] ? {segment,pointer} : {6'b0,pointer};
                    if (mode[1:0]==0) begin
                        cycles <= rd == 7 ? 7 : 6;
                        if (op == 13) write_word(address,r[rd],WRITE_ALU);
                        else begin a<=r[rd];read_word(address,MEMORY_ALU);end
                    end else state <= INDIRECT_UPDATE;
                end
                state[$clog2(INDIRECT_UPDATE)]: begin
                    case (mode[1:0])
                        1: begin
                            pointer_wrap=pointer==0;
                            pointer = decrement16(pointer);r[rs]<=pointer;
                            if (mode[2] && pointer_wrap) r[6][15:10]<=rs==6 ? 6'd62 : segment-6'd1;
                        end
                        2: begin
                            pointer_wrap=&pointer;
                            pointer = increment16(pointer);r[rs]<=pointer;
                            if (mode[2] && pointer_wrap) r[6][15:10]<=rs==6 ? 6'd1 : segment+6'd1;
                        end
                        3: begin
                            pointer_wrap=&pointer;
                            pointer = increment16(pointer);r[rs]<=pointer;
                            if (mode[2] && pointer_wrap) r[6][15:10]<=rs==6 ? 6'd1 : segment+6'd1;
                        end
                        default: begin end
                    endcase
                    state <= INDIRECT_ACCESS;
                end
                state[$clog2(INDIRECT_ACCESS)]: begin
                    if (mode[1:0]==3) address = mode[2] ? {r[6][15:10],r[rs]} : {6'b0,r[rs]};
                    cycles <= rd == 7 ? 7 : 6;
                    if (op == 13) write_word(address,r[rd],WRITE_ALU);
                    else begin a<= r[rd]; read_word(address,MEMORY_ALU); end
                end
                state[$clog2(MEMORY_ALU)]: begin capture_b(data_word,operand_subtract,operand_status_carry); state <= ALU; end
                state[$clog2(BRANCH)]: begin
                    branch_low=branch_backwards ? {1'b0,r[7][5:0]}-{1'b0,branch_displacement} :
                        {1'b0,r[7][5:0]}+{1'b0,branch_displacement};
                    next_pc={branch_low[6] ?
                        (branch_backwards ? decrement16({r[6][5:0],r[7][15:6]}) : increment16({r[6][5:0],r[7][15:6]})) :
                        {r[6][5:0],r[7][15:6]},branch_low[5:0]};
                    r[7]<=next_pc[15:0];r[6][5:0]<=next_pc[21:16];finish(4);
                end
                state[$clog2(IMMEDIATE)]: begin
                    advance_pc(); immediate_word = data_word;
                    if (mode == 33) begin
                        capture_b(immediate_word,operand_subtract,operand_status_carry); cycles <= rd == 7 ? 5 : 4; state <= ALU;
                    end else if (mode == 34 && op != 13) begin
                        cycles <= rd == 7 ? 8 : 7; read_word({6'b0,immediate_word},MEMORY_ALU);
                    end else if (mode == 35) begin
                        address = {6'b0,immediate_word}; cycles <= rd == 7 ? 8 : 7;
                        if (op == 13) write_word(address,a,WRITE_ALU); else state <= ALU;
                    end else illegal();
                end
                state[$clog2(ALU)]: begin
                    if (!alu_valid) illegal();
                    else begin
                        r[6] <= status_result;
                        if (mode == 35) write_word(address,alu_saves ? alu_result : 16'b0,WRITE_ALU);
                        else begin
                            if (alu_saves) r[rd] <= alu_result;
                            finish(cycles);
                        end
                    end
                end
                state[$clog2(WRITE_ALU)]: finish(cycles);
                state[$clog2(PUSH)]: if (remaining == 0 || stack_reg[3]) finish(8'(2*total+4));
                    else begin
                        write_word({6'b0,r[rs]},r[stack_reg[2:0]],PUSH_DONE);
                        r[rs] <= stack_decrement;
                    end
                state[$clog2(PUSH_DONE)]: begin remaining = remaining - 5'd1; stack_reg = stack_reg - 4'd1; state <= PUSH; end
                state[$clog2(POP)]: if (remaining == 0 || stack_reg >= 7) finish(8'(2*total+4));
                    else begin
                        stack_reg = stack_reg + 4'd1;pointer=stack_increment;r[rs]<=pointer;
                        read_word({6'b0,pointer},POP_DONE);
                    end
                state[$clog2(POP_DONE)]: begin r[stack_reg[2:0]] <= data_word; remaining = remaining - 5'd1; state <= POP; end
                state[$clog2(ENTRY_PC)]: begin write_return_stack(r[7],ENTRY_SR); r[0] <= r[0] - 16'd1; end
                state[$clog2(ENTRY_SR)]: begin write_return_stack(r[6],ENTRY_VECTOR); r[0] <= r[0] - 16'd1; end
                state[$clog2(ENTRY_VECTOR)]: read_word(address,ENTRY_DONE);
                state[$clog2(ENTRY_DONE)]: begin r[7] <= data_word; r[6] <= 0; finish(10); end
                state[$clog2(TARGET)]: begin
                    advance_pc(); target_pc = {iw[5:0],data_word};
                    if (iw[8:6] == 1) state <= CALL_PC;
                    else begin r[7] <= target_pc[15:0]; r[6][5:0] <= target_pc[21:16]; finish(5); end
                end
                state[$clog2(CALL_PC)]: begin write_return_stack(r[7],CALL_SR); r[0] <= r[0] - 16'd1; end
                state[$clog2(CALL_SR)]: begin write_return_stack(r[6],CALL_DONE); r[0] <= r[0] - 16'd1; end
                state[$clog2(CALL_DONE)]: begin r[7] <= target_pc[15:0]; r[6][5:0] <= target_pc[21:16]; finish(9); end
                state[$clog2(MAC_A)]: read_word({6'b0,mac_rd_address},MAC_B);
                state[$clog2(MAC_B)]: begin a<= data_word; read_word({6'b0,mac_rs_address},MAC_ACC); end
                state[$clog2(MAC_ACC)]: begin
                    if (total==0) begin r[3]<=registered_product[15:0];r[4]<=registered_product[31:16];finish(12);end
                    else begin capture_b(data_word,operand_subtract,operand_status_carry);state <= MAC_PRODUCT;end
                end
                state[$clog2(MAC_PRODUCT)]: begin
                    mac_rd_next<=increment16(r[rd]);mac_rs_next<=increment_pointer(r[rs],rs==rd);
                    state <= total==0 ? MAC_ACC : MAC_WRITE;
                end
                state[$clog2(MAC_WRITE)]: begin
                    accumulator = accumulator + registered_product;
                    if (fir_move && mac_index != 0) write_word({6'b0,mac_rd_address},old_mac,MAC_NEXT);
                    else state <= MAC_NEXT;
                end
                state[$clog2(MAC_NEXT)]: begin
                    old_mac = a;r[rd] <= mac_rd_next;r[rs] <= mac_rs_next;
                    remaining = remaining - 5'd1; mac_index = mac_index + 5'd1;
                    if (remaining == 0) begin r[3] <= accumulator[15:0]; r[4] <= accumulator[31:16]; finish(8'(10*total+6)); end
                    else state <= MAC_A;
                end
                state[$clog2(HALTED)]: begin end
                default: illegal();
            endcase
            if (!bus_valid) begin
                // Interrupt/call pushes select SP without the operand-address mux.
                bus_addr<=stack_bus_select ? {6'b0,r[0]} : next_bus_address;
                // Select preclassified sources alongside their addresses.
                bus_external<=stack_bus_select ? |r[0][15:14] : next_bus_external;
            end
            if (ds_write) r[6][15:10] <= ds_value;
        end
        // Private DSP operands avoid routing the ALU shifter into DSP inputs.
        multiplier_a<=$signed({iw[8] && multiplier_a_value[15],multiplier_a_value});
        multiplier_b<=state[$clog2(MAC_ACC)] && total!=0 ? data_word : state[$clog2(DECODE)] && rs==6 ? r[6] : b;
    end
endmodule
