onerror {resume}
quietly WaveActivateNextPane {}
add wave -divider {Wishbone}
add wave /tb_uart_wb/clk
add wave /tb_uart_wb/rst
add wave -radix hexadecimal /tb_uart_wb/adr
add wave /tb_uart_wb/we
add wave /tb_uart_wb/cyc
add wave /tb_uart_wb/stb
add wave /tb_uart_wb/ack
add wave -radix hexadecimal /tb_uart_wb/dat_i
add wave -radix hexadecimal /tb_uart_wb/dat_o
add wave -divider {UART serial and FIFO}
add wave /tb_uart_wb/tx
add wave /tb_uart_wb/rx
add wave -radix unsigned /tb_uart_wb/dut/tx_count
add wave -radix unsigned /tb_uart_wb/dut/rx_count
add wave -radix unsigned /tb_uart_wb/dut/tx_state
add wave -radix unsigned /tb_uart_wb/dut/rx_state
add wave -radix hexadecimal /tb_uart_wb/dut/tx_shift
add wave -radix hexadecimal /tb_uart_wb/dut/rx_shift
add wave /tb_uart_wb/dut/parity_error
add wave /tb_uart_wb/dut/overrun_error
add wave /tb_uart_wb/dut/framing_error
add wave /tb_uart_wb/irq
TreeUpdate [SetDefaultTree]
WaveRestoreZoom {0 ns} {70000 ns}
