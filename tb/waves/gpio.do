onerror {resume}
quietly WaveActivateNextPane {}
add wave -divider {Wishbone}
add wave /tb_gpio_wb/clk
add wave /tb_gpio_wb/rst
add wave -radix hexadecimal /tb_gpio_wb/adr
add wave /tb_gpio_wb/we
add wave /tb_gpio_wb/cyc
add wave /tb_gpio_wb/stb
add wave /tb_gpio_wb/ack
add wave -radix hexadecimal /tb_gpio_wb/dat_i
add wave -radix hexadecimal /tb_gpio_wb/dat_o
add wave -divider {GPIO}
add wave -radix hexadecimal /tb_gpio_wb/gpio_i
add wave -radix hexadecimal /tb_gpio_wb/gpio_o
add wave -radix hexadecimal /tb_gpio_wb/gpio_oe
add wave -radix hexadecimal /tb_gpio_wb/dut/int_enable
add wave -radix hexadecimal /tb_gpio_wb/dut/int_type
add wave -radix hexadecimal /tb_gpio_wb/dut/int_method
add wave -radix hexadecimal /tb_gpio_wb/dut/int_status
add wave /tb_gpio_wb/irq
TreeUpdate [SetDefaultTree]
WaveRestoreZoom {0 ns} {900 ns}
