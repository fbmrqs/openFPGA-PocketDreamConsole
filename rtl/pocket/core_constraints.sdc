# Synchronizer heads are asynchronous; subsequent stages retain normal timing.
set_false_path -to [get_registers {*|*_sync[0] *|*_sync_1[*]}]
# Cut only the asynchronous control pins of reset synchronizers. Their
# stage-to-stage data paths and reset distribution remain timed.
set_false_path -to [get_pins -hierarchical {read_reset[*]|clrn write_reset[*]|clrn pipeline[*]|clrn}]
# A 3 ns bound on every direct Gray-code net also bounds bus skew below
# the fastest 5.085 ns source period, including clock-to-output margin.
# Standard Edition cuts max-skew analysis on these asynchronous paths.
set_net_delay -max -from [get_registers {*|write_gray[*] *|read_gray[*]}] \
    -to [get_registers {*|write_sync_1[*] *|read_sync_1[*]}] 3.0

create_generated_clock -name dram_clk_pin \
    -source [get_pins {ic|system_pll|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    [get_ports dram_clk]
set_output_delay -clock dram_clk_pin -max 3.0 [get_ports {dram_a[*] dram_ba[*] dram_dq[*] dram_dqm[*] dram_ras_n dram_cas_n dram_we_n dram_cke}]
set_output_delay -clock dram_clk_pin -min -1.0 [get_ports {dram_a[*] dram_ba[*] dram_dq[*] dram_dqm[*] dram_ras_n dram_cas_n dram_we_n dram_cke}]
set_input_delay -clock dram_clk_pin -max 6.0 [get_ports {dram_dq[*]}]
set_input_delay -clock dram_clk_pin -min 2.3 [get_ports {dram_dq[*]}]
# ALTDDIO_IN's rising-edge output is physically present but unconnected.
# The falling-edge output carries every SDRAM read and remains timed.
set_false_path -from [get_ports {dram_dq[*]}] -to [get_registers {*|u_dq_ddio_in|*|dataout_h[*]}]

# PSRAM has no external sampling clock. The controller's counted strobe,
# access and hold intervals provide its setup/hold contract. TimeQuest's
# absolute min/max delays include FPGA clock insertion, so audit complete
# pin data delays separately in validate-timing.tcl, at every corner. The
# virtual clock lets TimeQuest enumerate these cut paths; it does not impose
# a synchronous memory timing model.
create_clock -name psram_protocol_reference -period 7.5
set psram_outputs [get_ports {cram0_a[*] cram1_a[*] cram0_dq[*] cram1_dq[*] cram*_clk cram*_adv_n cram*_cre cram*_ce0_n cram*_ce1_n cram*_oe_n cram*_we_n cram*_ub_n cram*_lb_n}]
set_input_delay -clock psram_protocol_reference -max 0.0 [get_ports {cram0_dq[*] cram1_dq[*]}]
set_input_delay -clock psram_protocol_reference -min 0.0 [get_ports {cram0_dq[*] cram1_dq[*]}]
set_output_delay -clock psram_protocol_reference -max 0.0 $psram_outputs
set_output_delay -clock psram_protocol_reference -min 0.0 $psram_outputs
set_false_path -from [get_registers {*}] -to $psram_outputs
set_false_path -from [get_ports {cram0_dq[*] cram1_dq[*]}] -to [get_registers {*|psram0|data_out[*] *|psram1|data_out[*]}]

# APF transfers RGB on both edges of the forwarded scaler clock.
create_generated_clock -name scaler_clock_pin \
    -source [get_pins {ic|video_pll|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    [get_ports scal_clk]
set_output_delay -clock scaler_clock_pin -max 2.0 [get_ports {scal_vid[*] scal_de scal_hs scal_vs scal_skip}]
set_output_delay -clock scaler_clock_pin -min 0.0 [get_ports {scal_vid[*] scal_de scal_hs scal_vs scal_skip}]
set_output_delay -clock scaler_clock_pin -clock_fall -add_delay -max 2.0 [get_ports {scal_vid[*] scal_de scal_hs scal_vs scal_skip}]
set_output_delay -clock scaler_clock_pin -clock_fall -add_delay -min 0.0 [get_ports {scal_vid[*] scal_de scal_hs scal_vs scal_skip}]

create_generated_clock -name audio_master_pin \
    -source [get_pins {ic|system_pll|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    [get_ports scal_audmclk]
set_output_delay -clock audio_master_pin -max 2.0 [get_ports {scal_auddac scal_audlrck}]
set_output_delay -clock audio_master_pin -min 0.0 [get_ports {scal_auddac scal_audlrck}]

# Conservative board-delay allowance for the framework's clocked SPI link.
set_input_delay -clock bridge_spiclk -max 2.0 [get_ports {bridge_spimosi bridge_spimiso bridge_spiss}]
set_input_delay -clock bridge_spiclk -min 0.0 [get_ports {bridge_spimosi bridge_spimiso bridge_spiss}]
set_output_delay -clock bridge_spiclk -max 2.0 [get_ports {bridge_spimiso bridge_spimosi}]
set_output_delay -clock bridge_spiclk -min 0.0 [get_ports {bridge_spimiso bridge_spimosi}]

# Keep system, SDRAM controller and forwarded chip clocks in one related
# group: Quartus can merge equal PLL outputs. Never cut the SDRAM I/O paths.
set_clock_groups -asynchronous \
    -group [get_clocks {clk_74a}] \
    -group [get_clocks {clk_74b}] \
    -group [get_clocks {bridge_spiclk}] \
    -group [get_clocks {ic|system_pll|general[0].gpll~PLL_OUTPUT_COUNTER|divclk ic|system_pll|general[1].gpll~PLL_OUTPUT_COUNTER|divclk ic|system_pll|general[2].gpll~PLL_OUTPUT_COUNTER|divclk dram_clk_pin}] \
    -group [get_clocks {ic|system_pll|general[3].gpll~PLL_OUTPUT_COUNTER|divclk audio_master_pin}] \
    -group [get_clocks {ic|video_pll|general[0].gpll~PLL_OUTPUT_COUNTER|divclk ic|video_pll|general[1].gpll~PLL_OUTPUT_COUNTER|divclk scaler_clock_pin}] \
    -group [get_clocks {ic|video_pll|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}]

# PAD is an asynchronous pulse protocol. Only its first input synchronizer
# stage is exempt; subsequent stages and output pulse generation remain timed.
set_false_path -from [get_ports bridge_1wire] -to [get_registers {*|synch_3:s01|stage_1[*]}]
# The framework encodes each PAD third-bit interval with 20 clk_74a cycles
# (269 ns). Bound the physical output path to 6 ns, as audited below, rather
# than counting global-clock insertion against a nonexistent board clock.
set_output_delay -clock clk_74a -max 0.0 [get_ports bridge_1wire]
set_output_delay -clock clk_74a -min 0.0 [get_ports bridge_1wire]
set_false_path -from [get_registers {*}] -to [get_ports bridge_1wire]

# Local MMIO payloads are captured two clocks before the access pulse.
# Assertions check stability and transaction identity on every simulated access.
# Registered sound reads consume their address after one clock and are
# excluded from the access-update exception. Other reads retain one-clock timing.
set sound_read_payloads [get_registers {*|spu_address[*]}]
set sound_read_registers [get_registers {*|spu|channel_read* *|spu|global_read* *|spu|read_capture*wave_select* *|spu|read_capture*pitch_select*}]
foreach pattern {*|spu|channel_read* *|spu|global_read* *|spu|read_capture*wave_select* *|spu|read_capture*pitch_select*} {
    if {[get_collection_size [get_registers $pattern]] == 0} {
        error "Missing single-clock sound-read timing endpoints: $pattern"
    }
}
puts "Single-clock sound-read registers: [get_collection_size $sound_read_registers]"
foreach {payloads destination minimum} {
    {*|spu_address[*] *|spu_data[*]} {*|spu|*} 30
    {*|io_address[*] *|io_data[*] *|io_pc[*]} {*|io|*} 41
    {*|ppu_data[*]} {*|ppu|*} 16
} {
    set sources [get_registers $payloads]
    set targets [get_registers $destination]
    if {$destination eq {*|spu|*}} {
        set targets [remove_from_collection $targets $sound_read_registers]
    }
    if {[get_collection_size $sources] < $minimum || [get_collection_size $targets] == 0} {
        error "Missing registered MMIO payload timing endpoints: $payloads -> $destination"
    }
    set_multicycle_path -setup -end -from $sources -to $targets 2
    set_multicycle_path -hold -end -from $sources -to $targets 1
}
