onerror {resume}
quietly WaveActivateNextPane {}
add wave -divider {Full microcontroller}
add wave soc:/tb_soc_interrupts/clk
add wave soc:/tb_soc_interrupts/rst
add wave -radix hexadecimal soc:/tb_soc_interrupts/cpu_pc_o
add wave -radix hexadecimal soc:/tb_soc_interrupts/gpio0_o
add wave -radix hexadecimal soc:/tb_soc_interrupts/gpio1_i
add wave soc:/tb_soc_interrupts/irq_o
add wave -radix hexadecimal soc:/tb_soc_interrupts/irq_vector_o
add wave soc:/tb_soc_interrupts/cpu_trap_o
add wave soc:/tb_soc_interrupts/cpu_halted_o
add wave -divider {CPU interrupt state}
add wave -radix hexadecimal soc:/tb_soc_interrupts/dut/u_cpu/u_csr/mstatus
add wave -radix hexadecimal soc:/tb_soc_interrupts/dut/u_cpu/u_csr/mie
add wave -radix hexadecimal soc:/tb_soc_interrupts/dut/u_cpu/u_csr/mepc
add wave -radix hexadecimal soc:/tb_soc_interrupts/dut/u_cpu/u_csr/mcause
add wave -divider {PIC, GPIO and timer}
add wave -radix hexadecimal soc:/tb_soc_interrupts/dut/u_pic/pic_status
add wave -radix hexadecimal soc:/tb_soc_interrupts/dut/u_pic/pic_enable
add wave -radix hexadecimal soc:/tb_soc_interrupts/dut/u_gpio1/int_status
add wave -radix unsigned soc:/tb_soc_interrupts/dut/u_timer/count_reg
add wave -radix hexadecimal soc:/tb_soc_interrupts/dut/u_timer/status_reg
add wave soc:/tb_soc_interrupts/dut/u_timer/irq_o
add wave -divider {UART 115200 and 9600}
add wave soc:/tb_soc_interrupts/uart_rx_i
add wave soc:/tb_soc_interrupts/uart_tx_o
add wave -radix unsigned soc:/tb_soc_interrupts/dut/u_uart/baud_div
add wave -radix unsigned soc:/tb_soc_interrupts/dut/u_uart/tx_count
add wave -radix unsigned soc:/tb_soc_interrupts/dut/u_uart/rx_count
add wave -radix hexadecimal soc:/tb_soc_interrupts/dut/u_uart/int_status
add wave -divider {I2C 100 kHz}
add wave soc:/tb_soc_interrupts/i2c_scl_i
add wave soc:/tb_soc_interrupts/i2c_sda_i
add wave soc:/tb_soc_interrupts/i2c_scl_oe
add wave soc:/tb_soc_interrupts/i2c_sda_oe
add wave -radix unsigned soc:/tb_soc_interrupts/dut/u_i2c/state
add wave -radix hexadecimal soc:/tb_soc_interrupts/dut/u_i2c/txr
add wave -radix hexadecimal soc:/tb_soc_interrupts/dut/u_i2c/rxr
TreeUpdate [SetDefaultTree]
wave zoom full
