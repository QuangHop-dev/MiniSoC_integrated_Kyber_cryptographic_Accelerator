onerror {resume}
quietly WaveActivateNextPane {}
add wave -divider {Wishbone}
add wave /tb_i2c_wb/clk
add wave /tb_i2c_wb/rst
add wave -radix hexadecimal /tb_i2c_wb/adr
add wave /tb_i2c_wb/we
add wave /tb_i2c_wb/cyc
add wave /tb_i2c_wb/stb
add wave /tb_i2c_wb/ack
add wave -radix hexadecimal /tb_i2c_wb/dat_i
add wave -radix hexadecimal /tb_i2c_wb/dat_o
add wave -divider {I2C Bus}
add wave /tb_i2c_wb/scl_i
add wave /tb_i2c_wb/scl_oe
add wave /tb_i2c_wb/sda_i
add wave /tb_i2c_wb/sda_oe
add wave -divider {Command Engine}
add wave -radix hexadecimal /tb_i2c_wb/dut/state
add wave -radix unsigned /tb_i2c_wb/dut/bit_count
add wave -radix hexadecimal /tb_i2c_wb/dut/shifter
add wave -radix hexadecimal /tb_i2c_wb/dut/rxr
add wave /tb_i2c_wb/dut/busy
add wave /tb_i2c_wb/dut/transfer_in_progress
add wave /tb_i2c_wb/dut/rxack
add wave /tb_i2c_wb/dut/arbitration_lost
add wave /tb_i2c_wb/dut/irq_flag
add wave /tb_i2c_wb/irq
TreeUpdate [SetDefaultTree]
WaveRestoreZoom {0 ns} {5000 ns}
