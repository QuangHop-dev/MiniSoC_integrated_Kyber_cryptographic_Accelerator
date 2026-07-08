onerror {resume}
quietly WaveActivateNextPane {}
add wave -divider {Wishbone}
add wave /tb_timer_wb/clk
add wave /tb_timer_wb/rst
add wave -radix hexadecimal /tb_timer_wb/adr
add wave /tb_timer_wb/we
add wave /tb_timer_wb/cyc
add wave /tb_timer_wb/stb
add wave /tb_timer_wb/ack
add wave -radix hexadecimal /tb_timer_wb/dat_i
add wave -radix hexadecimal /tb_timer_wb/dat_o
add wave -divider {Timer}
add wave /tb_timer_wb/dut/count_enable
add wave /tb_timer_wb/dut/prescaler_enable
add wave -radix unsigned /tb_timer_wb/dut/prescaler_count
add wave -radix unsigned /tb_timer_wb/dut/count_reg
add wave -radix unsigned /tb_timer_wb/dut/period_reg
add wave -radix hexadecimal /tb_timer_wb/dut/status_reg
add wave /tb_timer_wb/irq
TreeUpdate [SetDefaultTree]
WaveRestoreZoom {0 ns} {1500 ns}
