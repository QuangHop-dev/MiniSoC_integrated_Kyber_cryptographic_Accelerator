if {$argc != 3} {
    error "usage: vivado -mode batch -source report_hier_util.tcl -tclargs <project.xpr> <run> <output.rpt>"
}

set project_file [file normalize [lindex $argv 0]]
set run_name [lindex $argv 1]
set output_file [file normalize [lindex $argv 2]]

open_project $project_file
open_run $run_name
report_utilization -hierarchical -hierarchical_depth 8 -file $output_file
close_project
