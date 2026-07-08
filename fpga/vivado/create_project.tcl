set script_dir [file dirname [file normalize [info script]]]

proc env_or_default {name default} {
    global env
    if {[info exists env($name)] && $env($name) ne ""} {
        return $env($name)
    }
    return $default
}

proc get_arg {name default} {
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

set repo_root_default [env_or_default "SOC_REPO_ROOT" [file normalize [file join $script_dir ".." ".."]]]
set repo_root [file normalize [get_arg "-repo" $repo_root_default]]
set out_dir_default [env_or_default "SOC_VIVADO_OUT_DIR" [file join $repo_root "build" "vivado" "zcu102"]]
set out_dir [file normalize [get_arg "-out" $out_dir_default]]
set firmware_default [env_or_default "SOC_FIRMWARE_HEX" [file join $repo_root "sw" "build" "kyber_demo" "firmware.hex"]]
set firmware_hex [file normalize [get_arg "-firmware" $firmware_default]]
set bootloader_enable [get_arg "-bootloader_enable" [env_or_default "SOC_BOOTLOADER_ENABLE" "0"]]
set boot_bytes [get_arg "-boot_bytes" [env_or_default "SOC_BOOT_BYTES" "16384"]]
set boot_rom_bytes [get_arg "-boot_rom_bytes" [env_or_default "SOC_BOOT_ROM_BYTES" "16384"]]
set sram_bytes [get_arg "-sram_bytes" [env_or_default "SOC_SRAM_BYTES" "16384"]]
set clock_profile [get_arg "-clock_profile" [env_or_default "SOC_CLOCK_PROFILE" "167"]]
set part_name [get_arg "-part" "xczu9eg-ffvb1156-2-e"]
set board_part [get_arg "-board_part" "xilinx.com:zcu102:part0:3.3"]

if {![file exists $firmware_hex]} {
    error "firmware hex does not exist: $firmware_hex"
}

file mkdir $out_dir
create_project -force kyber_soc_zcu102 $out_dir -part $part_name
set_property target_language Verilog [current_project]

if {$board_part ne ""} {
    set matching_board_parts [get_board_parts -quiet $board_part]
    if {[llength $matching_board_parts] != 0} {
        set_property board_part $board_part [current_project]
    } else {
        puts "WARNING: board_part not installed in Vivado board store: $board_part"
    }
}

set rtl_files [list]
foreach cpu_file [lsort [glob -nocomplain [file join $repo_root "rtl" "cpu" "*.v"]]] {
    lappend rtl_files $cpu_file
}
set rtl_files [concat $rtl_files [list \
    [file join $repo_root "rtl" "mem" "boot_rom_wb.v"] \
    [file join $repo_root "rtl" "mem" "bootloader_mem_wb.v"] \
    [file join $repo_root "rtl" "mem" "imem_wb.v"] \
    [file join $repo_root "rtl" "mem" "sram_wb.v"] \
    [file join $repo_root "rtl" "periph" "gpio_wb.v"] \
    [file join $repo_root "rtl" "periph" "i2c_wb.v"] \
    [file join $repo_root "rtl" "periph" "pic_wb.v"] \
    [file join $repo_root "rtl" "periph" "timer_wb.v"] \
    [file join $repo_root "rtl" "periph" "uart_wb.v"] \
    [file join $repo_root "rtl" "bus" "wb_interconnect.v"] \
]]
foreach kyber_file [lsort [glob -nocomplain [file join $repo_root "rtl" "kyber" "*.v"]]] {
    lappend rtl_files $kyber_file
}
lappend rtl_files [file join $repo_root "rtl" "soc_top.v"]
lappend rtl_files [file join $repo_root "rtl" "board" "zcu102_soc_wrapper.v"]

foreach rtl_file $rtl_files {
    read_verilog -sv [list $rtl_file]
}

set xdc_file [file join $script_dir "constraints" "zcu102_pl_only.xdc"]
if {[file exists $xdc_file]} {
    read_xdc [list $xdc_file]
}

set_property top zcu102_soc_wrapper [current_fileset]
set_property generic [list \
    SOC_CLOCK_PROFILE=$clock_profile \
    BOOT_INIT_FILE=$firmware_hex \
    BOOTLOADER_ENABLE=$bootloader_enable \
    BOOT_BYTES=$boot_bytes \
    BOOT_ROM_BYTES=$boot_rom_bytes \
    SRAM_BYTES=$sram_bytes \
] [current_fileset]
update_compile_order -fileset sources_1

# Synthesis/implementation strategies
set_property strategy Flow_AreaOptimized_high [get_runs synth_1]
set_property strategy Performance_ExtraTimingOpt [get_runs impl_1]

puts "Created Vivado project in $out_dir"
puts "BOOT_INIT_FILE=$firmware_hex"
puts "SOC_CLOCK_PROFILE=$clock_profile"
puts "BOOTLOADER_ENABLE=$bootloader_enable BOOT_BYTES=$boot_bytes BOOT_ROM_BYTES=$boot_rom_bytes SRAM_BYTES=$sram_bytes"
