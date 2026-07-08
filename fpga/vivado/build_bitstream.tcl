set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir "create_project.tcl"]

proc get_arg_build {name default} {
    global argv
    set idx [lsearch -exact $argv $name]
    if {$idx < 0} {
        return $default
    }
    set val_idx [expr {$idx + 1}]
    if {$val_idx >= [llength $argv]} {
        error "missing value for $name"
    }
    return [lindex $argv $val_idx]
}

set jobs [get_arg_build "-jobs" "4"]
set allow_unconstrained_io [get_arg_build "-allow_unconstrained_io" "0"]
set report_dir [file join $out_dir "reports"]
file mkdir $report_dir

if {$allow_unconstrained_io eq "1"} {
    puts "WARNING: lowering UCIO-1/NSTD-1 DRC severity for unconstrained bring-up bitstream"
    set drc_hook [file join $out_dir "allow_unconstrained_io_pre_bitstream.tcl"]
    set fh [open $drc_hook "w"]
    puts $fh {set_property SEVERITY Warning [get_drc_checks UCIO-1]}
    puts $fh {set_property SEVERITY Warning [get_drc_checks NSTD-1]}
    close $fh
    set_property STEPS.WRITE_BITSTREAM.TCL.PRE $drc_hook [get_runs impl_1]
}

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
open_run synth_1
report_utilization -file [file join $report_dir "post_synth_utilization.rpt"]
report_timing_summary -file [file join $report_dir "post_synth_timing_summary.rpt"]

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
open_run impl_1
report_utilization -file [file join $report_dir "post_impl_utilization.rpt"]
report_timing_summary -file [file join $report_dir "post_impl_timing_summary.rpt"]
report_power -file [file join $report_dir "post_impl_power.rpt"]

set bit_file [lindex [glob -nocomplain [file join $out_dir "kyber_soc_zcu102.runs" "impl_1" "*.bit"]] 0]
if {$bit_file ne ""} {
    file copy -force $bit_file [file join $out_dir "kyber_soc_zcu102.bit"]
    puts "Bitstream: [file join $out_dir "kyber_soc_zcu102.bit"]"
} else {
    error "bitstream not found under implementation run directory"
}
