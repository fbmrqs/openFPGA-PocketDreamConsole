package require ::quartus::project
package require ::quartus::sta
set channel [open output_files/ap_core.map.rpt r]
set report [read $channel]
close $channel
foreach {pattern depth width bits} {
    {*|pdc_ppu:ppu|altsyncram:line_scroll_rtl_0|*} 256 9 2304
    {*|pdc_ppu:ppu|altsyncram:line_compress_rtl_0|*} 256 16 4096
    {*|pdc_ppu:ppu|altsyncram:palette_rtl_0|*} 256 16 4096
    {*|pdc_ppu:ppu|altsyncram:pixels_rtl_0|*} 320 16 5120
    {*|pdc_ppu:ppu|pdc_sprite_bank:sprites_0|*} 256 16 4096
    {*|pdc_ppu:ppu|pdc_sprite_bank:sprites_1|*} 256 16 4096
    {*|pdc_ppu:ppu|pdc_sprite_bank:sprites_2|*} 256 16 4096
    {*|pdc_ppu:ppu|pdc_sprite_bank:sprites_3|*} 256 16 4096
} {
    set found 0
    foreach row [split $report "\n"] {
        set fields [split $row {;}]
        if {[llength $fields] < 10} {continue}
        if {[string match $pattern [string trim [lindex $fields 1]]] &&
            [string trim [lindex $fields 2]] eq "M10K block" &&
            [string trim [lindex $fields 4]] eq $depth &&
            [string trim [lindex $fields 5]] eq $width &&
            [string trim [lindex $fields 8]] eq $bits} {set found 1}
    }
    if {!$found} {error "Missing required native graphics M10K mapping: $pattern"}
    puts "Native graphics M10K verified: $pattern ($depth x $width)"
}
project_open ap_core -revision ap_core
create_timing_netlist -post_map
read_sdc
update_timing_netlist
check_timing -include no_clock -file output_files/native-mapping-clocks.rpt
set channel [open output_files/native-mapping-clocks.rpt r]
set report [read $channel]
close $channel
if {![regexp {; no_clock *; *0 *;} $report]} {
    error "Native mapped netlist contains clockless registers"
}
delete_timing_netlist
project_close
puts "Native synthesis mapping and clock audit passed"
