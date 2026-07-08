onerror {resume}
quietly WaveActivateNextPane {}
add wave -divider {Wishbone host interface}
add wave /tb_kyber_wb_slave_kat/clk
add wave /tb_kyber_wb_slave_kat/rst
add wave -radix hexadecimal /tb_kyber_wb_slave_kat/wb_adr
add wave /tb_kyber_wb_slave_kat/wb_we
add wave /tb_kyber_wb_slave_kat/wb_cyc
add wave /tb_kyber_wb_slave_kat/wb_stb
add wave /tb_kyber_wb_slave_kat/wb_ack
add wave -radix hexadecimal /tb_kyber_wb_slave_kat/wb_dat_i
add wave -radix hexadecimal /tb_kyber_wb_slave_kat/wb_dat_o
add wave -divider {Kyber accelerator}
add wave /tb_kyber_wb_slave_kat/irq
add wave -radix unsigned /tb_kyber_wb_slave_kat/dut/u_core/state
add wave -radix unsigned /tb_kyber_wb_slave_kat/dut/u_core/op_reg
add wave -radix hexadecimal /tb_kyber_wb_slave_kat/dut/u_core/status_reg
add wave -radix unsigned /tb_kyber_wb_slave_kat/dut/u_core/cycle_counter
add wave /tb_kyber_wb_slave_kat/dut/u_core/hash_start
add wave /tb_kyber_wb_slave_kat/dut/u_core/hash_done
add wave /tb_kyber_wb_slave_kat/dut/u_core/gm_start
add wave /tb_kyber_wb_slave_kat/dut/u_core/gm_done
add wave /tb_kyber_wb_slave_kat/dut/u_core/cbd_start
add wave /tb_kyber_wb_slave_kat/dut/u_core/cbd_done
TreeUpdate [SetDefaultTree]
wave zoom full
