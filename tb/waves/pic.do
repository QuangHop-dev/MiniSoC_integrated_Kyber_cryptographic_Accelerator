onerror {resume}
quietly WaveActivateNextPane {}
add wave -divider {Wishbone}
add wave /tb_pic_wb/clk
add wave /tb_pic_wb/rst
add wave -radix hexadecimal /tb_pic_wb/adr
add wave /tb_pic_wb/we
add wave /tb_pic_wb/cyc
add wave /tb_pic_wb/stb
add wave /tb_pic_wb/ack
add wave -radix hexadecimal /tb_pic_wb/dat_i
add wave -radix hexadecimal /tb_pic_wb/dat_o
add wave -divider {Interrupt Controller}
add wave -radix hexadecimal /tb_pic_wb/irq_sources
add wave -radix hexadecimal /tb_pic_wb/dut/pic_status
add wave -radix hexadecimal /tb_pic_wb/dut/pic_enable
add wave -radix hexadecimal /tb_pic_wb/irq_vector
add wave /tb_pic_wb/irq
TreeUpdate [SetDefaultTree]
WaveRestoreZoom {0 ns} {1000 ns}
