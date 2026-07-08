onerror {resume}
quietly WaveActivateNextPane {}
add wave -divider {Clock and bus}
add wave /tb_rv32i_datapath/clk
add wave /tb_rv32i_datapath/rst
add wave -radix hexadecimal /tb_rv32i_datapath/pc
add wave /tb_rv32i_datapath/wb_cyc
add wave /tb_rv32i_datapath/wb_stb
add wave /tb_rv32i_datapath/wb_we
add wave /tb_rv32i_datapath/wb_ack
add wave -radix hexadecimal /tb_rv32i_datapath/wb_adr
add wave -radix hexadecimal /tb_rv32i_datapath/wb_dat_o
add wave -radix hexadecimal /tb_rv32i_datapath/wb_dat_i
add wave -divider {Two-stage datapath}
add wave -radix hexadecimal /tb_rv32i_datapath/dut/fetch_pc
add wave /tb_rv32i_datapath/dut/if_id_valid
add wave -radix hexadecimal /tb_rv32i_datapath/dut/if_id_instr
add wave /tb_rv32i_datapath/dut/id_ex_valid
add wave -radix hexadecimal /tb_rv32i_datapath/dut/id_ex_instr
add wave -radix hexadecimal /tb_rv32i_datapath/dut/id_ex_a
add wave -radix hexadecimal /tb_rv32i_datapath/dut/id_ex_b
add wave -radix hexadecimal /tb_rv32i_datapath/dut/id_ex_imm
add wave -divider {Forwarding}
add wave /tb_rv32i_datapath/dut/forward_sel1
add wave /tb_rv32i_datapath/dut/forward_sel2
add wave -radix hexadecimal /tb_rv32i_datapath/dut/decode_data_a
add wave -radix hexadecimal /tb_rv32i_datapath/dut/decode_data_b
add wave -divider {Execute}
add wave -radix hexadecimal /tb_rv32i_datapath/dut/alu_result
add wave /tb_rv32i_datapath/dut/rf_write_enable
add wave -radix unsigned /tb_rv32i_datapath/dut/rf_write_addr
add wave -radix hexadecimal /tb_rv32i_datapath/dut/rf_write_data
add wave -divider {PC Execute and Control}
add wave -radix unsigned /tb_rv32i_datapath/dut/pcsel
add wave -radix hexadecimal /tb_rv32i_datapath/dut/pc_execute_next
add wave /tb_rv32i_datapath/dut/dec_branch
add wave /tb_rv32i_datapath/dut/dec_jal
add wave /tb_rv32i_datapath/dut/branch_taken
add wave /tb_rv32i_datapath/dut/jump_taken
add wave /tb_rv32i_datapath/dut/id_ex_flush
add wave /tb_rv32i_datapath/dut/pipeline_stall
add wave -divider {CSR and Trap}
add wave /tb_rv32i_datapath/dut/trap_taken
add wave -radix hexadecimal /tb_rv32i_datapath/dut/trap_pc
add wave -radix hexadecimal /tb_rv32i_datapath/dut/trap_cause
add wave -radix hexadecimal /tb_rv32i_datapath/dut/csr_mepc
add wave -radix hexadecimal /tb_rv32i_datapath/dut/csr_mcause
add wave /tb_rv32i_datapath/trap
add wave /tb_rv32i_datapath/halted
TreeUpdate [SetDefaultTree]
WaveRestoreZoom {0 ns} {1450 ns}
