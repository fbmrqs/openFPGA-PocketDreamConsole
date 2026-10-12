//
// User core top-level
//
// Instantiated by the real top-level: apf_top
//

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1 

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable, 

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,
 
///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus 

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,
    
output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
// 
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig
    
);

assign port_ir_tx=0;
assign port_ir_rx_disable=1;
assign bridge_endian_little=1;
assign cart_tran_bank3=8'hzz;
assign cart_tran_bank3_dir=0;
assign cart_tran_bank2=8'hzz;
assign cart_tran_bank2_dir=0;
assign cart_tran_bank1=8'hzz;
assign cart_tran_bank1_dir=0;
assign cart_tran_bank0=4'hf;
assign cart_tran_bank0_dir=1;
assign cart_tran_pin30=0;
assign cart_tran_pin30_dir=1'bz;
assign cart_pin30_pwroff_reset=0;
assign cart_tran_pin31=1'bz;
assign cart_tran_pin31_dir=0;
assign port_tran_so=1'bz;
assign port_tran_so_dir=0;
assign port_tran_si=1'bz;
assign port_tran_si_dir=0;
assign port_tran_sck=1'bz;
assign port_tran_sck_dir=0;
assign port_tran_sd=1'bz;
assign port_tran_sd_dir=0;
assign sram_a=0;
assign sram_dq=16'hzzzz;
assign sram_oe_n=1;
assign sram_we_n=1;
assign sram_ub_n=1;
assign sram_lb_n=1;
assign dbg_tx=1'bz;
assign user1=1'bz;
assign aux_scl=1'bz;
assign vpll_feed=1'bz;
assign video_skip=0;

wire clk_system, clk_sdram, clk_chip, clk_video, clk_video_90, clk_psram, clk_audio;
wire system_locked, video_locked;
wire global_reset=!(system_locked && video_locked);
wire reset_bridge, reset_system, reset_sdram;
pdc_reset_sync bridge_reset_sync (.clk(clk_74a),.async_reset(global_reset),.reset(reset_bridge));
pdc_reset_sync system_reset_sync (.clk(clk_system),.async_reset(global_reset),.reset(reset_system));
pdc_reset_sync sdram_reset_sync (.clk(clk_sdram),.async_reset(global_reset),.reset(reset_sdram));
altera_pll #(
    .fractional_vco_multiplier("true"),.reference_clock_frequency("74.25 MHz"),
    .operation_mode("normal"),.number_of_clocks(4),.pll_type("General"),.pll_subtype("General"),
    .output_clock_frequency0("98.304 MHz"),.phase_shift0("0 ps"),
    .output_clock_frequency1("49.152 MHz"),.phase_shift1("0 ps"),
    .output_clock_frequency2("49.152 MHz"),.phase_shift2("13733 ps"),
    .output_clock_frequency3("12.288 MHz"),.phase_shift3("0 ps")
) system_pll (.refclk(clk_74a),.rst(1'b0),.outclk({clk_audio,clk_chip,clk_sdram,clk_system}),.locked(system_locked),.fbclk(1'b0),.fboutclk());
altera_pll #(
    .fractional_vco_multiplier("true"),.reference_clock_frequency("74.25 MHz"),
    .operation_mode("normal"),.number_of_clocks(3),.pll_type("General"),.pll_subtype("General"),
    .output_clock_frequency0("12.299150 MHz"),.phase_shift0("0 ps"),
    .output_clock_frequency1("12.299150 MHz"),.phase_shift1("20326 ps"),
    .output_clock_frequency2("133.240790 MHz"),.phase_shift2("0 ps")
) video_pll (.refclk(clk_74a),.rst(1'b0),.outclk({clk_psram,clk_video_90,clk_video}),.locked(video_locked),.fbclk(1'b0),.fboutclk());
assign video_rgb_clock=clk_video;
assign video_rgb_clock_90=clk_video_90;

wire reset_n, slot_write, slot_complete, slot_ok, rom_ready, load_fault;
wire [15:0] slot_id;
wire [31:0] slot_size, command_read;
logic [15:0] init_count;
logic memory_initialized;
(* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] initialized_sync, host_reset_sync, running_sync;
(* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [31:0] keys_sync_1, keys_sync_2;
always_ff @(posedge clk_sdram or posedge reset_sdram)
    if (reset_sdram) begin init_count<=0;memory_initialized<=0;end
    else if (!memory_initialized) begin
        init_count<=init_count+16'd1;
        if (init_count==32767) memory_initialized<=1;
    end
always_ff @(posedge clk_74a or posedge reset_bridge)
    if (reset_bridge) begin initialized_sync<=0;running_sync<=0;end
    else begin initialized_sync<={initialized_sync[0],memory_initialized};running_sync<={running_sync[0],native_ready && rom_ready};end
always_ff @(posedge clk_system or posedge reset_system)
    if (reset_system) begin host_reset_sync<=0;keys_sync_1<=0;keys_sync_2<=0;end
    else begin host_reset_sync<={host_reset_sync[0],reset_n};keys_sync_1<=cont1_key;keys_sync_2<=keys_sync_1;end
wire grayscale, grayscale_active;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] grayscale_ack;
always_ff @(posedge clk_74a or posedge reset_bridge)
    if (reset_bridge) grayscale_ack<=0;
    else grayscale_ack<={grayscale_ack[0],grayscale_active};
pdc_bridge_cmd commands (
    .clk(clk_74a),.reset_n,.bridge_endian_little,.bridge_addr,.bridge_rd,.bridge_rd_data(command_read),.bridge_wr,.bridge_wr_data,
    .status_boot_done(!reset_bridge),.status_setup_done(initialized_sync[1]),.status_running(running_sync[1]),
    .dataslot_requestread(),.dataslot_requestread_id(),.dataslot_requestread_ack(1'b1),.dataslot_requestread_ok(1'b1),
    .dataslot_requestwrite(slot_write),.dataslot_requestwrite_id(slot_id),.dataslot_requestwrite_size(slot_size),
    .dataslot_requestwrite_ack(slot_write),.dataslot_requestwrite_ok(slot_id!=1 || slot_ok),
    .dataslot_update(),.dataslot_update_id(),.dataslot_update_size(),.dataslot_allcomplete(slot_complete),
    .rtc_epoch_seconds(),.rtc_date_bcd(),.rtc_time_bcd(),.rtc_valid(),.osnotify_inmenu(),
    .video_grayscale(grayscale),.video_grayscale_active(grayscale_ack[1]),
    .savestate_supported(1'b0),.savestate_addr(32'b0),.savestate_size(32'b0),.savestate_maxloadsize(32'b0),
    .savestate_start(),.savestate_start_ack(1'b0),.savestate_start_busy(1'b0),.savestate_start_ok(1'b0),.savestate_start_err(1'b0),
    .savestate_load(),.savestate_load_ack(1'b0),.savestate_load_busy(1'b0),.savestate_load_ok(1'b0),.savestate_load_err(1'b0),
    .target_dataslot_read(1'b0),.target_dataslot_write(1'b0),.target_dataslot_getfile(1'b0),.target_dataslot_openfile(1'b0),
    .target_dataslot_ack(),.target_dataslot_done(),.target_dataslot_err(),
    .target_dataslot_id(16'b0),.target_dataslot_slotoffset(32'b0),.target_dataslot_bridgeaddr(32'b0),.target_dataslot_length(32'b0),
    .target_buffer_param_struct(32'b0),.target_buffer_resp_struct(32'b0),
    .datatable_addr(10'b0),.datatable_wren(1'b0),.datatable_data(32'b0),.datatable_q());

wire rom_request, rom_ack, word_write, word_done, burst_read, burst_valid, burst_done;
wire machine_rom_request, check_rom_request, check_done, check_passed;
wire [24:0] machine_rom_address, check_rom_address;
wire [3:0] check_status;
wire [15:0] checked_reset_vector;
wire [31:0] load_crc, write_crc, first_crc, second_crc, memory_debug_data;
wire [24:0] rom_address, burst_address;
wire [23:0] word_address;
wire [31:0] word_data, burst_data;
wire [15:0] rom_data;
wire rom_line_valid;
wire [255:0] rom_line_data;
wire [2:0] final_bank, bank;
assign rom_request=check_done ? machine_rom_request : check_rom_request;
assign rom_address=check_done ? machine_rom_address : check_rom_address;

pdc_rom_check memory_check (
    .clk(clk_system),.reset(reset_system),.rom_ready,.final_bank,
    .rom_request(check_rom_request),.rom_address(check_rom_address),.rom_ack,.rom_line_valid,.rom_line_data,
    .done(check_done),.passed(check_passed),.status(check_status),.reset_vector(checked_reset_vector),.first_crc,.second_crc);
pdc_rom_store store (
    .reset(global_reset),.bridge_clk(clk_74a),.system_clk(clk_system),.memory_clk(clk_sdram),
    .slot_write,.slot_complete,.slot_id,.slot_size,.bridge_address(bridge_addr),.bridge_data(bridge_wr_data),.bridge_write(bridge_wr),
    .slot_ok,.rom_ready,.final_bank,.load_fault,.load_crc,.write_crc,.rom_request,.rom_address,.rom_ack,.rom_data,.rom_line_valid,.rom_line_data,
    .word_write,.word_address,.word_data,.word_done,.burst_read,.burst_address,.burst_valid,.burst_done,.burst_data(burst_data[15:0]));
pdc_memory_debug memory_debug (
    .clk(clk_74a),.reset(reset_bridge),.done(check_done),.status(check_status),
    .reset_vector(checked_reset_vector),.load_crc,.write_crc,.first_crc,.second_crc,
    .bridge_address(bridge_addr),.bridge_data(memory_debug_data));
io_sdram #(.REFRESH_INTERVAL(10'd368)) sdram (
    .controller_clk(clk_sdram),.chip_clk(clk_chip),.clk_90(clk_sdram),.reset_n(!reset_sdram),
    .phy_cke(dram_cke),.phy_clk(dram_clk),.phy_cas(dram_cas_n),.phy_ras(dram_ras_n),.phy_we(dram_we_n),
    .phy_ba(dram_ba),.phy_a(dram_a),.phy_dq(dram_dq),.phy_dqm(dram_dqm),
    .burst_rd(burst_read),.burst_addr(burst_address),.burst_len(11'd8),.burst_32bit(1'b0),.burst_data,.burst_data_valid(burst_valid),.burst_data_done(burst_done),
    .burstwr(1'b0),.burstwr_addr(25'b0),.burstwr_ready(),.burstwr_strobe(1'b0),.burstwr_data(16'b0),.burstwr_done(1'b0),
    .word_rd(1'b0),.word_wr(word_write),.word_addr(word_address),.word_data,.word_wstrb(4'hf),
    .word_data_next(32'b0),.word_wstrb_next(4'b0),.word_burst_len(4'b0),.word_burst_wr_len(4'b0),
    .word_q(),.word_busy(),.word_q_valid(),.word_wr_data_next(),.word_wr_done(word_done),.word_queue_pending(),
    .burst_wr_direct_data(32'b0),.burst_wr_direct_strb(4'b0),.dbg_io());

wire native_ready, cpu_fault, pixel_valid, pixel_ready, audio_valid, frame_done;
wire [21:0] fault_pc;
wire [15:0] fault_opcode;
wire [31:0] fault_read;
wire [8:0] pixel_x;
wire [7:0] pixel_y;
wire [14:0] pixel_data;
wire signed [15:0] audio_left, audio_right;
wire [15:0] cycle_backlog;
wire cycle_overflow;
(* preserve, dont_merge *) logic core_reset;
always_ff @(posedge clk_system or posedge reset_system)
    if (reset_system) core_reset<=1;
    else core_reset<=!host_reset_sync[1] || (keys_sync_2[14] && keys_sync_2[15]);
pdc_system #(.CLOCK_KHZ(98304),.REALTIME(1'b1)) machine (
    .clk(clk_system),.reset(core_reset),.rom_ready(rom_ready && check_passed),.final_bank,
    .buttons({keys_sync_2[9:8],keys_sync_2[15],keys_sync_2[5:0]}),
    .rom_request(machine_rom_request),.rom_address(machine_rom_address),.rom_ack(rom_ack && check_done),.rom_data,.rom_line_valid,.rom_line_data,.pixel_valid,.pixel_ready,.pixel_x,.pixel_y,.pixel_data,
    .audio_valid,.audio_left,.audio_right,.frame_done,.ready(native_ready),.cycle_backlog,.cycle_overflow,
    .cpu_fault,.fault_pc,.fault_opcode,.bank,.retired(),.registers());
pdc_fault_debug fault_debug (
    .clk(clk_74a),.reset(reset_bridge),.cpu_fault,.fault_pc,.fault_opcode,
    .bridge_address(bridge_addr),.bridge_data(fault_read));

wire [1:0] ps_read, ps_write, ps_busy, ps_valid;
wire [43:0] ps_address;
wire [31:0] ps_data, ps_q;
wire video_underflow, frame_fault, audio_overflow, audio_underflow;
wire [15:0] dropped_frames;
wire output_reset=core_reset || !native_ready || !rom_ready;
pdc_framebuffer display (
    .reset(output_reset),.video_reset(global_reset),.grayscale,.grayscale_active,
    .system_clk(clk_system),.memory_clk(clk_psram),.video_clk(clk_video),
    .pixel_valid,.pixel_ready,.pixel_x,.pixel_y,.pixel_data,
    .memory_read(ps_read),.memory_write(ps_write),.memory_address(ps_address),.memory_data(ps_data),.memory_busy(ps_busy),.memory_valid(ps_valid),.memory_q(ps_q),
    .video_rgb,.video_de,.video_hs,.video_vs,.underflow(video_underflow),.write_fault(frame_fault),.dropped_frames);
psram #(.CLOCK_SPEED(133.240790),.MIN_CE_BEFORE_ADV_HIGH(13),.MIN_ADDRESS_HOLD_AFTER_ADV_HIGH(8),.MAX_ACCESS_TIME_FROM_ADV(95)) psram0 (
    .clk(clk_psram),.bank_sel(1'b0),.addr(ps_address[21:0]),.write_en(ps_write[0]),.data_in(ps_data[15:0]),.write_high_byte(1'b1),.write_low_byte(1'b1),
    .read_en(ps_read[0]),.read_avail(ps_valid[0]),.data_out(ps_q[15:0]),.busy(ps_busy[0]),
    .cram_a(cram0_a),.cram_dq(cram0_dq),.cram_wait(cram0_wait),.cram_clk(cram0_clk),.cram_adv_n(cram0_adv_n),.cram_cre(cram0_cre),
    .cram_ce0_n(cram0_ce0_n),.cram_ce1_n(cram0_ce1_n),.cram_oe_n(cram0_oe_n),.cram_we_n(cram0_we_n),.cram_ub_n(cram0_ub_n),.cram_lb_n(cram0_lb_n));
psram #(.CLOCK_SPEED(133.240790),.MIN_CE_BEFORE_ADV_HIGH(13),.MIN_ADDRESS_HOLD_AFTER_ADV_HIGH(8),.MAX_ACCESS_TIME_FROM_ADV(95)) psram1 (
    .clk(clk_psram),.bank_sel(1'b0),.addr(ps_address[43:22]),.write_en(ps_write[1]),.data_in(ps_data[31:16]),.write_high_byte(1'b1),.write_low_byte(1'b1),
    .read_en(ps_read[1]),.read_avail(ps_valid[1]),.data_out(ps_q[31:16]),.busy(ps_busy[1]),
    .cram_a(cram1_a),.cram_dq(cram1_dq),.cram_wait(cram1_wait),.cram_clk(cram1_clk),.cram_adv_n(cram1_adv_n),.cram_cre(cram1_cre),
    .cram_ce0_n(cram1_ce0_n),.cram_ce1_n(cram1_ce1_n),.cram_oe_n(cram1_oe_n),.cram_we_n(cram1_we_n),.cram_ub_n(cram1_ub_n),.cram_lb_n(cram1_lb_n));
pdc_audio sound (
    .reset(output_reset),.system_clk(clk_system),.audio_clk(clk_audio),.sample_valid(audio_valid),.sample_left(audio_left),.sample_right(audio_right),
    .audio_mclk,.audio_lrck,.audio_dac,.overflow(audio_overflow),.underflow(audio_underflow));
always_comb begin
    bridge_rd_data=fault_read;
    if (bridge_addr[31:24]==8'hf8) bridge_rd_data=command_read;
    else if (bridge_addr==32'h20000000) bridge_rd_data={cycle_backlog,cycle_overflow,4'b0,bank,load_fault,frame_fault,video_underflow,audio_overflow,audio_underflow,cpu_fault,native_ready,rom_ready};
    else if (bridge_addr==32'h20000004) bridge_rd_data={16'b0,dropped_frames};
    else if (bridge_addr>=32'h20000010 && bridge_addr<=32'h20000024) bridge_rd_data=memory_debug_data;
end
endmodule
