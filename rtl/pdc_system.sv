module pdc_system #(
    parameter integer CLOCK_KHZ = 196608,
    parameter logic REALTIME = 0
) (
    input logic clk, reset, rom_ready,
    input logic [2:0] final_bank,
    input logic videojet_controls,
    input logic [8:0] buttons,
    output logic rom_request,
    output logic [24:0] rom_address,
    input logic rom_ack,
    input logic [15:0] rom_data,
    input logic rom_line_valid,
    input logic [255:0] rom_line_data,
    output logic pixel_valid,
    input logic pixel_ready,
    output logic [8:0] pixel_x,
    output logic [7:0] pixel_y,
    output logic [14:0] pixel_data,
    output logic audio_valid,
    output logic signed [15:0] audio_left, audio_right,
    output logic frame_done,
    output logic ready,
    output logic [15:0] cycle_backlog,
    output logic cycle_overflow,
    output logic cpu_fault,
    output logic [21:0] fault_pc,
    output logic [15:0] fault_opcode,
    output logic [2:0] bank,
    output logic retired,
    output logic [127:0] registers
);
    (* preserve, dont_merge, maxfan = 8 *) logic system_reset = 1'b1, cpu_reset = 1'b1;
    logic run;
    logic [7:0] cpu_cycles, irq, cpu_irq;
    logic cpu_fiq;
    logic [21:0] cpu_pc;
    logic [5:0] ds, ds_value;
    logic ds_write, fiq, interrupt_entry;
    logic [11:0] shifts;
    logic [4:0] modes;
    logic [3:0] requests, writes, acks;
    logic [87:0] addresses;
    logic [63:0] write_values;
    logic [15:0] shared_data;
    logic memory_request, memory_write, memory_ack;
    logic cpu_bus_external;
    wire [21:0] memory_lookahead_address;
    logic [21:0] memory_address;
    logic [15:0] memory_write_data, memory_read_data;
    logic ram_request, ram_ack, ram_ready;
    logic [15:0] ram_data;
    logic cache_request, cache_ack, bank_changed;
    logic [15:0] cache_data;
    logic [24:0] cache_address;
    logic cpu_rom_selected, cpu_response_rom, cpu_rom_ack, cpu_rom_request;
    logic [15:0] cpu_rom_data, external_rom_data;
    logic [24:0] cpu_cache_address, cpu_external_address, shared_external_address;
    logic shared_rom_request;
    logic ppu_cache_request,ppu_rom_selected,ppu_response_rom,ppu_rom_ack,ppu_rom_request;
    logic [15:0] ppu_rom_data;
    logic [255:0] ppu_rom_line;
    logic [24:0] ppu_cache_address,ppu_external_address;
    logic [2:0] external_acks;
    logic [3:0] shared_requests;
    logic [1:0] address_decode;
    logic mmio_access, mmio_write;
    logic [13:0] mmio_address;
    (* preserve, dont_merge *) logic [13:0] spu_address,io_address;
    (* preserve, dont_merge *) logic [21:0] io_pc;
    (* preserve, dont_merge *) logic [15:0] ppu_data,spu_data,io_data;
    logic [15:0] mmio_data, io_read, ppu_read, spu_read, video_read;
    logic advance, io_busy, ppu_busy, spu_busy, ppu_ready;
    logic ppu_irq, spu_channel_irq, spu_beat_irq, watchdog_reset;
    logic start_line, timing_frame_done, line_done;
    logic [8:0] scanline;
    logic [7:0] render_line;
    logic sample_valid;
    logic signed [15:0] sample_left, sample_right;
    logic dma_start, dma_busy, dma_done, dma_sprite, sprite_dma_done;
    logic [21:0] dma_source, dma_current_source, dma_source_register;
    logic [13:0] dma_target, dma_current_target, dma_target_register;
    logic [15:0] dma_length, dma_remaining;
    logic [15:0] sprite_source, sprite_target;
    logic [7:0] elapsed;
    logic last_line;
    typedef enum logic [1:0] {WAIT_READY, EXECUTE, WAIT_DMA, WAIT_PERIPHERALS} scheduler_t;
    scheduler_t scheduler;
    logic mmio_ack, mmio_release, mmio_prepare, mmio_pending;
    logic [1:0] mmio_bank, response_bank;
    logic mmio_dma;
    logic [15:0] ppu_read_pipe, spu_read_pipe, io_read_pipe, dma_read_pipe;
    logic [15:0] mmio_read_data;
    logic [21:0] held_address;
    logic held_write;
    logic [15:0] held_data;
    localparam integer PHASE_BITS=$clog2(CLOCK_KHZ);
    localparam integer CREDIT_BITS=REALTIME ? 18 : 32;
    logic [PHASE_BITS-1:0] phase;
    logic signed [CREDIT_BITS-1:0] credit;
    wire [8:0] credit_debit={1'b0,cpu_cycles}-9'(cycle_tick);
    wire [8:0] credit_low={1'b0,credit[7:0]}-credit_debit;
    logic cycle_tick;
    wire [7:0] peripheral_cycles=cpu_cycles;
    assign advance=(scheduler==EXECUTE && retired && !dma_busy && !dma_start) ||
        (scheduler==WAIT_DMA && !dma_busy && !dma_start);

    always_ff @(posedge clk) begin
        system_reset <= reset || !rom_ready;
        cpu_reset <= reset || system_reset || !ram_ready || !ppu_ready || watchdog_reset;
    end
    assign ready = !cpu_reset;
    assign run = scheduler == EXECUTE && !retired && (!REALTIME || !credit[CREDIT_BITS-1]);
    assign cycle_tick = phase>=PHASE_BITS'(CLOCK_KHZ-27000);
    assign cycle_backlog = credit[CREDIT_BITS-1] ? 16'b0 : |credit[CREDIT_BITS-2:16] ? 16'hffff : credit[15:0];
    always_ff @(posedge clk) begin
        if (cpu_reset) begin phase<=0;credit<=0;cycle_overflow<=0;end
        else begin
            phase<=cycle_tick ? phase-PHASE_BITS'(CLOCK_KHZ-27000) : phase+PHASE_BITS'(27000);
            if (retired) credit<={ (CREDIT_BITS-8)'(credit[CREDIT_BITS-1:8]-(CREDIT_BITS-8)'(credit_low[8])),credit_low[7:0]};
            // 131071 modeled cycles cover 4.854 ms, below the 256-sample
            // audio startup reserve (5.333 ms). Retain short graphics bursts.
            else if (credit<CREDIT_BITS'(131071)) credit<={ (CREDIT_BITS-8)'(credit[CREDIT_BITS-1:8]+(CREDIT_BITS-8)'(cycle_tick && &credit[7:0])),8'(credit[7:0]+8'(cycle_tick))};
            else if (cycle_tick) cycle_overflow<=1;
        end
    end
    assign cache_address = {bank, address_decode==0 ? memory_address : address_decode==1 ? {1'b0,memory_address[20:0]} : {2'b0,memory_address[19:0]}};
    assign cpu_cache_address = {bank, address_decode==0 ? addresses[21:0] : address_decode==1 ? {1'b0,addresses[20:0]} : {2'b0,addresses[19:0]}};
    assign ppu_cache_address = {bank, address_decode==0 ? addresses[43:22] : address_decode==1 ? {1'b0,addresses[42:22]} : {2'b0,addresses[41:22]}};
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (!cpu_reset && run && cpu.state[2] &&
            ((cpu.irq_enable && cpu_irq!=irq) || (cpu.fiq_enable && cpu_fiq!=fiq)))
            $fatal(1,"Interrupt snapshot changed an enabled instruction-boundary source");
`endif
    always_ff @(posedge clk) begin cpu_irq<=irq;cpu_fiq<=fiq;end
    assign cpu_rom_selected = requests[0] && !writes[0] && cpu_bus_external;
    always_ff @(posedge clk) ppu_cache_request<=!system_reset && ppu_rom_selected;
    assign ppu_rom_selected=requests[1] && !writes[1] && addresses[43:22]>=22'h4000;
    assign shared_requests = {requests[3:2],requests[1] && !ppu_rom_selected,requests[0] && !cpu_rom_selected};
    assign ram_request = memory_request && memory_address<22'h2800;
    assign cache_request = memory_request && memory_address>=22'h4000 && !memory_write;
    assign memory_ack = response_bank==0 ? ram_ack : response_bank==1 ? cache_ack : mmio_ack;
    assign memory_read_data = response_bank==0 ? ram_data : response_bank==1 ? cache_data : mmio_read_data;
    always_ff @(posedge clk) begin
        // MMIO already settles before access; only RAM needs the combinational
        // arbitration address for a two-clock hit.
        io_pc<=cpu_pc;
        spu_address<=memory_address[13:0];io_address<=memory_address[13:0];
        ppu_data<=memory_write_data;spu_data<=memory_write_data;io_data<=memory_write_data;
    end
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (advance && scheduler==WAIT_DMA && !system_reset)
            if (cpu_cycles!=elapsed) $fatal(1,"CPU cycle count changed during DMA wait");
`endif
    assign mmio_address = held_address[13:0];
    assign mmio_data = held_data;
    assign sprite_dma_done = dma_done && dma_sprite;

    unsp_cpu cpu(
        .clk, .reset(cpu_reset), .run, .prefetch_enable(advance || scheduler==WAIT_PERIPHERALS),
        .irq(cpu_irq), .fiq(cpu_fiq), .ds_write, .ds_value, .ds, .pc(cpu_pc),
        .bus_valid(requests[0]), .bus_write(writes[0]), .bus_external(cpu_bus_external), .bus_addr(addresses[21:0]), .bus_wdata(write_values[15:0]),
        .bus_ack(cpu_response_rom ? cpu_rom_ack : acks[0]), .bus_rdata(cpu_response_rom ? cpu_rom_data : shared_data),
        .retired, .interrupt_entry, .cycles(cpu_cycles),
        .fault(cpu_fault), .fault_pc, .fault_opcode, .registers, .shifts, .modes);
    pdc_ppu ppu(
        .clk, .reset(system_reset), .ready(ppu_ready), .register_write(mmio_write),
        .register_address(memory_address[13:0]), .register_data(ppu_data), .register_read_data(ppu_read),
        .start_line, .line(render_line), .busy(ppu_busy), .line_done,
        .memory_request(requests[1]), .memory_address(addresses[43:22]), .memory_ack(ppu_response_rom ? ppu_rom_ack : acks[1]), .memory_data(ppu_response_rom ? ppu_rom_data : shared_data),
        .memory_line_valid(ppu_response_rom && ppu_rom_ack), .memory_line_data(ppu_rom_line),
        .pixel_valid, .pixel_ready, .pixel_x, .pixel_y, .pixel_data);
    assign writes[1] = 0;
    assign write_values[31:16] = 0;
    pdc_spu #(.ADDRESS_LOOKAHEAD(1'b1)) spu(
        .clk, .reset(system_reset), .register_write(mmio_write), .register_address(spu_address),
        .register_read_lookahead(memory_address[13:0]),
        .register_data(spu_data), .register_read_data(spu_read), .advance, .cycles(peripheral_cycles), .busy(spu_busy),
        .channel_irq(spu_channel_irq), .beat_irq(spu_beat_irq), .memory_request(requests[2]),
        .memory_address(addresses[65:44]), .memory_ack(acks[2]), .memory_data(shared_data),
        .sample_valid, .sample_left, .sample_right);
    assign writes[2] = 0;
    assign write_values[47:32] = 0;
    pdc_resampler resampler(.clk, .reset(system_reset), .sample_valid, .sample_left, .sample_right,
        .output_valid(audio_valid), .output_left(audio_left), .output_right(audio_right));
    pdc_dma dma(
        .clk, .reset(system_reset), .start(dma_start), .source(dma_source), .target(dma_target), .length(dma_length),
        .sprite_transfer(dma_sprite), .busy(dma_busy), .done(dma_done), .current_source(dma_current_source),
        .current_target(dma_current_target), .remaining(dma_remaining), .request(requests[3]), .write(writes[3]),
        .address(addresses[87:66]), .write_data(write_values[63:48]), .ack(acks[3]), .read_data(shared_data));
    pdc_io io(
        .clk, .reset(system_reset), .final_bank, .videojet_controls, .buttons, .pc(io_pc), .ds, .ds_write, .ds_value,
        .access(mmio_access), .write(mmio_write), .address(io_address), .write_data(io_data), .read_data(io_read),
        .advance, .cycles(peripheral_cycles), .busy(io_busy), .ppu_irq, .spu_channel_irq, .spu_beat_irq, .scanline,
        .irq, .fiq, .bank, .bank_changed, .address_decode, .watchdog_reset);
    pdc_video_timing video(
        .clk, .reset(system_reset), .advance, .cycles(peripheral_cycles), .register_write(mmio_write),
        .address(mmio_address), .write_data(mmio_data), .read_data(video_read), .sprite_dma_done,
        .irq(ppu_irq), .start_line, .frame_done(timing_frame_done), .scanline, .render_line);
    pdc_bus_arbiter #(.REGISTER_RESPONSE(1'b0)) arbiter(
        .clk, .reset(system_reset), .request(shared_requests), .write(writes), .address(addresses), .write_data(write_values),
        .ack(acks), .read_data(shared_data), .memory_request, .memory_write, .memory_address, .memory_lookahead_address, .memory_write_data,
        .memory_ack, .memory_read_data);
    pdc_ram ram(.clk, .reset(system_reset), .ready(ram_ready), .request(ram_request), .write(memory_write),
        .address(memory_address[13:0]), .read_address(memory_lookahead_address[13:0]), .write_data(memory_write_data), .ack(ram_ack), .read_data(ram_data));
    pdc_rom_cache #(.INDEX_BITS(9),.BURST_LINES(1'b1)) cache(
        .clk, .reset(system_reset), .invalidate(1'b0), .request(cache_request), .address(cache_address),
        .ack(cache_ack), .data(cache_data), .line_data(), .memory_request(shared_rom_request), .memory_address(shared_external_address),
        .memory_ack(external_acks[0]), .memory_data(external_rom_data),
        .memory_line_valid(rom_line_valid), .memory_line_data(rom_line_data));
    // CPU and graphics ROM hits bypass RAM/MMIO arbitration. Each cache tags
    // the ROM bank; sound and DMA retain a smaller shared cache.
    pdc_rom_cache #(.INDEX_BITS(10),.BURST_LINES(1'b1),.FAST_LINE(1'b1)) cpu_cache(
        .clk, .reset(system_reset), .invalidate(1'b0), .request(cpu_rom_selected), .address(cpu_cache_address),
        .ack(cpu_rom_ack), .data(cpu_rom_data), .line_data(), .memory_request(cpu_rom_request), .memory_address(cpu_external_address),
        .memory_ack(external_acks[2]), .memory_data(external_rom_data),
        .memory_line_valid(rom_line_valid), .memory_line_data(rom_line_data));
    pdc_rom_cache #(.BURST_LINES(1'b1),.REQUEST_STAGED(1'b1)) ppu_cache(
        .clk, .reset(system_reset), .invalidate(1'b0), .request(ppu_cache_request), .address(ppu_cache_address),
        .ack(ppu_rom_ack), .data(ppu_rom_data), .line_data(ppu_rom_line), .memory_request(ppu_rom_request), .memory_address(ppu_external_address),
        .memory_ack(external_acks[1]), .memory_data(external_rom_data),
        .memory_line_valid(rom_line_valid), .memory_line_data(rom_line_data));
    pdc_bus_arbiter #(.CLIENTS(3),.ADDRESS_WIDTH(25)) rom_arbiter(
        .clk, .reset(system_reset), .request({cpu_rom_request,ppu_rom_request,shared_rom_request}), .write(3'b0),
        .address({cpu_external_address,ppu_external_address,shared_external_address}), .write_data(48'b0),
        .ack(external_acks), .read_data(external_rom_data), .memory_request(rom_request),
        .memory_write(), .memory_address(rom_address), .memory_lookahead_address(), .memory_write_data(),
        .memory_ack(rom_ack), .memory_read_data(rom_data));

    always_ff @(posedge clk) begin
        frame_done <= 0;
        if (system_reset) begin scheduler <= WAIT_READY; elapsed <= 0; last_line <= 0; end
        else begin
            if (timing_frame_done) last_line <= 1;
            if (last_line && line_done) begin frame_done <= 1; last_line <= 0; end
            case (scheduler)
                WAIT_READY: if (!cpu_reset) scheduler <= EXECUTE;
                EXECUTE: if (retired) begin
                    elapsed <= cpu_cycles;
                    if (dma_busy || dma_start) scheduler <= WAIT_DMA;
                    else scheduler<=WAIT_PERIPHERALS;
                end
                WAIT_DMA: if (!dma_busy && !dma_start) scheduler<=WAIT_PERIPHERALS;
                WAIT_PERIPHERALS: if (!io_busy && !spu_busy && !ppu_busy && !start_line) scheduler <= EXECUTE;
                default: scheduler <= WAIT_READY;
            endcase
        end
    end
    // Decode and capture peripheral reads before the response mux. The bus
    // keeps its address stable throughout the registered acknowledgment.
    always_ff @(posedge clk) begin
        // Both responders acknowledge after this address classification is captured.
        cpu_response_rom<=!writes[0] && cpu_bus_external;
        ppu_response_rom<=!writes[1] && addresses[43:22]>=22'h4000;
        response_bank<=memory_address<22'h2800 ? 2'd0 :
            memory_address>=22'h4000 && !memory_write ? 2'd1 : 2'd2;
        ppu_read_pipe<=ppu_read | video_read;spu_read_pipe<=spu_read;io_read_pipe<=io_read;
    end
    always_ff @(posedge clk) begin
        mmio_ack <= 0; mmio_prepare <= 0; mmio_access <= 0; mmio_write <= 0; dma_start <= 0;
        if (system_reset) begin
            mmio_release<=0;mmio_prepare<=0;mmio_pending<=0;mmio_bank<=0;mmio_dma<=0;dma_read_pipe<=0;held_address<=0;held_write<=0;held_data<=0;mmio_read_data<=0;
            dma_source <= 0; dma_target <= 0; dma_length <= 0; dma_sprite <= 0;
            dma_source_register <= 0; dma_target_register <= 0; sprite_source <= 0; sprite_target <= 0;
        end else begin
            if (dma_done) begin
                if (dma_sprite) begin sprite_source <= dma_current_source[15:0]; sprite_target <= {6'b0,dma_current_target[9:0]}; end
                else begin dma_source_register <= dma_current_source; dma_target_register <= dma_current_target; end
            end
            if (mmio_release) begin
                if (!memory_request) mmio_release<=0;
            end else if (memory_request && !ram_request && !cache_request) begin
                    held_address <= memory_address; held_write <= memory_write; held_data <= memory_write_data;
                    mmio_release<=1;mmio_prepare<=1;
                    mmio_bank<=memory_address<22'h3000 ? 2'd0 : memory_address<22'h3500 ? 2'd1 : 2'd2;
                    case(memory_address)
                        22'h2870,22'h2871,22'h2872,22'h3e00,22'h3e01,22'h3e02,22'h3e03:mmio_dma<=1;
                        default:mmio_dma<=0;
                    endcase
            end
            // Settle the registered graphics/sound address before access.
            if (memory_request && mmio_release && !mmio_access && !mmio_ack && !mmio_prepare && !mmio_pending) begin
                    mmio_access <= held_address<22'h4000; mmio_write <= held_write && held_address<22'h4000;
                    mmio_pending<=1;
                    case (held_address)
                        22'h2870: begin dma_read_pipe <= sprite_source; if (held_write) sprite_source <= held_data & 16'h3fff; end
                        22'h2871: begin dma_read_pipe <= sprite_target; if (held_write) sprite_target <= held_data & 16'h3ff; end
                        22'h2872: begin
                            dma_read_pipe <= dma_busy && dma_sprite ? dma_remaining : 16'b0;
                            if (held_write) begin dma_source <= {6'b0,sprite_source}; dma_target <= sprite_target[13:0]; dma_length <= held_data; dma_sprite <= 1; dma_start <= 1; end
                        end
                        22'h3e00: begin dma_read_pipe <= dma_source_register[15:0]; if (held_write) dma_source_register[15:0] <= held_data; end
                        22'h3e01: begin dma_read_pipe <= {10'b0,dma_source_register[21:16]}; if (held_write) dma_source_register[21:16] <= held_data[5:0]; end
                        22'h3e02: begin
                            dma_read_pipe <= dma_busy && !dma_sprite ? dma_remaining : 16'b0;
                            if (held_write) begin dma_source <= dma_source_register; dma_target <= dma_target_register; dma_length <= held_data; dma_sprite <= 0; dma_start <= 1; end
                        end
                        22'h3e03: begin dma_read_pipe <= {2'b0,dma_target_register}; if (held_write) dma_target_register <= held_data[13:0]; end
                        default: begin end
                    endcase
            end
            if (mmio_pending) begin
                mmio_read_data<=mmio_dma ? dma_read_pipe : mmio_bank==0 ? ppu_read_pipe : mmio_bank==1 ? spu_read_pipe : io_read_pipe;
                mmio_pending<=0;
                    mmio_ack <= 1;
            end
        end
    end
`ifdef PDC_VERIFY_MMIO_CYCLES
    logic [13:0] previous_spu_address,earlier_spu_address,previous_io_address;
    logic [21:0] previous_io_pc;
    logic [15:0] previous_spu_data,previous_io_data,previous_ppu_data;
    always_ff @(posedge clk) begin
        if (mmio_access && !system_reset) begin
            if (mmio_bank==1 && spu_address!=earlier_spu_address)
                $fatal(1,"Sound address did not settle before its read pipeline");
            if (io_pc!=previous_io_pc || io_pc!=cpu_pc)
                $fatal(1,"GPIO PC did not settle two clocks before access");
            if (spu_address!=previous_spu_address || io_address!=previous_io_address ||
                spu_data!=previous_spu_data || io_data!=previous_io_data || ppu_data!=previous_ppu_data)
                $fatal(1,"MMIO payload did not settle two clocks before access");
            if (spu_address!=held_address[13:0] || io_address!=held_address[13:0] ||
                spu_data!=held_data || io_data!=held_data || ppu_data!=held_data)
                $fatal(1,"MMIO local payload does not match the held transaction");
        end
        earlier_spu_address<=previous_spu_address;
        previous_io_pc<=io_pc;
        previous_spu_address<=spu_address;previous_io_address<=io_address;
        previous_spu_data<=spu_data;previous_io_data<=io_data;previous_ppu_data<=ppu_data;
    end
`endif

endmodule
