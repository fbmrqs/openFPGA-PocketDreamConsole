source validate-mapping.tcl
package require ::quartus::project
package require ::quartus::sta
project_open ap_core -revision ap_core
file delete -force output_files/native-timing-pass.json
create_timing_netlist
read_sdc
derive_clock_uncertainty
update_timing_netlist
report_clocks -file output_files/native-clocks.rpt
report_sdc -file output_files/native-sdc.rpt
report_ucp -file output_files/native-unconstrained.rpt
check_timing -include {no_clock generated_clock loops latches partial_multicycle partial_min_max_delay} -file output_files/native-constraint-checks.rpt
set failed 0
foreach report {native-unconstrained.rpt native-constraint-checks.rpt} {
    set channel [open output_files/$report r]
    set contents [read $channel]
    close $channel
    if {$report eq "native-unconstrained.rpt"} {
        foreach row [split $contents "\n"] {
            if {[regexp {; (Illegal Clocks|Unconstrained [^;]+) *; *([0-9]+) *; *([0-9]+) *;} $row match property setup hold]} {
                if {$setup != 0 || $hold != 0} {puts "Unconstrained paths: $property ($setup/$hold)";set failed 1}
            }
        }
    } else {
        foreach row [split $contents "\n"] {
            if {[regexp {; (no_clock|generated_clock|loops|latches|partial_multicycle|partial_min_max_delay) *; *([0-9]+) *;} $row match check count]} {
                if {$count != 0} {puts "Invalid constraint check: $check ($count)";set failed 1}
            }
        }
    }
}
set corner 0
foreach_in_collection condition [get_available_operating_conditions] {
    set_operating_conditions $condition
    update_timing_netlist
    report_timing -setup -to $sound_read_registers \
        -npaths 3 -detail full_path -file output_files/native-$corner-sound-read.rpt
    # Require real setup AND hold paths for every SDRAM data input/output.
    # A clock-group cut must fail validation, not silently look like closure.
    foreach analysis {setup hold} {
        foreach direction {input output} {
            if {$direction eq "input"} {
                set ports [get_ports {dram_dq[*]}]
                set endpoint -from
                set required 16
            } else {
                set ports [get_ports {dram_a[*] dram_ba[*] dram_dq[*] dram_dqm[*] dram_ras_n dram_cas_n dram_we_n dram_cke}]
                set endpoint -to
                set required 37
            }
            if {[get_collection_size $ports] != $required} {error "Missing SDRAM $direction ports"}
            set checked 0
            set worst 1e9
            foreach_in_collection port $ports {
                set paths [get_timing_paths -$analysis $endpoint $port -npaths 1]
                if {[get_collection_size $paths] == 0} {error "SDRAM $direction $analysis path was cut or unconstrained"}
                foreach_in_collection path $paths {
                    set slack [get_path_info -slack $path]
                    if {$slack<$worst} {set worst $slack}
                    if {$slack<0.0} {set failed 1}
                }
                incr checked
            }
            report_timing -$analysis $endpoint $ports -npaths $required -detail full_path \
                -file output_files/native-$corner-sdram-$direction-$analysis.rpt
            puts "Native corner $corner SDRAM $direction $analysis: $worst ns ($checked/$required ports)"
        }
    }
    # These asynchronous pin paths have no meaningful external launch/capture
    # clock relationship. Check their complete data budget without adding the
    # internal PLL clock insertion delay to a fictitious board clock.
    foreach direction {input output} {
        if {$direction eq "input"} {
            set sources [get_ports {cram0_dq[*] cram1_dq[*]}]
            set targets [get_registers {*|psram0|data_out[*] *|psram1|data_out[*]}]
        } else {
            set sources [get_registers {*|psram0|* *|psram1|*}]
            set targets $psram_outputs
        }
        report_timing -setup -false_path -from $sources -to $targets -npaths 0 -detail full_path \
            -file output_files/native-$corner-psram-$direction.rpt
        set count 0
        set worst 0.0
        foreach_in_collection path [get_timing_paths -setup -false_path -from $sources -to $targets -npaths 0] {
            set delay [get_path_info -data_delay $path]
            if {$direction eq "output"} {
                set driver [get_path_info -from $path]
                set delay [expr {$delay+[get_register_info -tco $driver]}]
            }
            if {$delay>$worst} {set worst $delay}
            if {$delay>6.0} {set failed 1}
            incr count
        }
        set required 32
        if {$direction eq "input"} {set required [get_collection_size $targets]}
        if {$required==0 || $count<$required} {error "PSRAM $direction pin-delay constraints were not fully analyzed ($count/$required)."}
        puts "Native corner $corner PSRAM $direction pin-data delay: $worst ns ($count paths, 6 ns budget)"
    }
    set pad_sources [get_registers {*|pad_1wire*}]
    set pad_targets [get_ports bridge_1wire]
    report_timing -setup -false_path -from $pad_sources -to $pad_targets -npaths 0 -detail full_path \
        -file output_files/native-$corner-pad-output.rpt
    set pad_count 0
    set pad_worst 0.0
    foreach_in_collection path [get_timing_paths -setup -false_path -from $pad_sources -to $pad_targets -npaths 0] {
        set driver [get_path_info -from $path]
        set delay [expr {[get_path_info -data_delay $path]+[get_register_info -tco $driver]}]
        if {$delay>$pad_worst} {set pad_worst $delay}
        if {$delay>6.0} {set failed 1}
        incr pad_count
    }
    if {$pad_count<2} {error "PAD output-enable and data paths were not fully analyzed."}
    puts "Native corner $corner PAD output pin-data delay: $pad_worst ns ($pad_count paths, 6 ns budget)"
    report_net_delay -nworst 1 -file output_files/native-$corner-net-delay.rpt
    set channel [open output_files/native-$corner-net-delay.rpt r]
    set contents [read $channel]
    close $channel
    if {![regexp {; set_net_delay *; *(-?[0-9]+[.][0-9]+) *;} $contents match slack]} {
        error "Gray-code net-delay constraints were not analyzed."
    }
    puts "Native corner $corner Gray-code net-delay slack: $slack ns"
    if {$slack < 0.0} {set failed 1}
    report_min_pulse_width -file output_files/native-$corner-pulse-width.rpt
    foreach pulse [get_min_pulse_width -nworst 1] {
        set slack [lindex $pulse 0]
        puts "Native corner $corner minimum pulse-width slack: $slack ns"
        if {$slack < 0.0} {set failed 1}
    }
    foreach analysis {setup hold recovery removal} {
        report_timing -$analysis -npaths 10 -detail full_path -file output_files/native-$corner-$analysis.rpt
        foreach_in_collection path [get_timing_paths -$analysis -npaths 1] {
            set slack [get_path_info -slack $path]
            puts "Native corner $corner $analysis worst slack: $slack ns"
            if {$slack < 0.0} {set failed 1}
        }
    }
    incr corner
}
project_close
if {$failed} {error "Native design fails timing; packaging is disabled."}
set rbf_hash [lindex [exec sha256sum output_files/ap_core.rbf] 0]
set channel [open output_files/native-timing-pass.json w]
puts $channel "{\"passed\":true,\"corners\":$corner,\"rbf_sha256\":\"$rbf_hash\"}"
close $channel
