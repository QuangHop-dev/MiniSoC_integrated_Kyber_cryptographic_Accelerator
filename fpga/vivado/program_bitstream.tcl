if {$argc != 1} {
    error "usage: program_bitstream.tcl <bitstream>"
}

set bit_file [file normalize [lindex $argv 0]]
if {![file exists $bit_file]} {
    error "bitstream not found: $bit_file"
}

open_hw_manager
connect_hw_server -allow_non_jtag

proc open_first_target {} {
    set targets [get_hw_targets -quiet *]
    if {[llength $targets] == 0} {
        return 0
    }
    set target [lindex $targets 0]
    puts "Opening hardware target: $target"
    current_hw_target $target
    catch {set_property PARAM.FREQUENCY 6000000 $target}
    open_hw_target $target
    return 1
}

if {![open_first_target]} {
    puts "No hardware target found; reconnecting and rescanning cables..."
    disconnect_hw_server
    after 1000
    connect_hw_server -allow_non_jtag
    if {![open_first_target]} {
        error "ZCU102 JTAG target not detected after rescan. Connect and power the J2 USB-JTAG interface."
    }
}

set all_devices [get_hw_devices -quiet *]
puts "Detected JTAG devices: $all_devices"
set devices {}
foreach candidate $all_devices {
    set part [get_property -quiet PART $candidate]
    puts "  $candidate PART=$part"
    if {[string match -nocase "xczu9eg*" $part] ||
        [string match -nocase "*xczu9*" $candidate]} {
        lappend devices $candidate
    }
}
if {[llength $devices] == 0} {
    error "no XCZU9EG device detected in JTAG chain; verify board power and JTAG mode"
}

set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device

puts "Programmed $device with $bit_file"
close_hw_manager
