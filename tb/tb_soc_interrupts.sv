`timescale 1ns/1ps

module tb_soc_interrupts;
    localparam real CLK_PERIOD_NS = 6.0;
    localparam integer UART_115200_BIT_CYCLES = 1440;
    localparam integer UART_9600_BIT_CYCLES = 17360;

    reg clk;
    reg rst;
    reg [7:0] gpio1_i;
    reg uart_rx_i;

    wire [7:0] gpio0_o;
    wire [7:0] gpio0_oe;
    wire       i2c_scl_o;
    wire       i2c_scl_oe;
    wire       i2c_sda_o;
    wire       i2c_sda_oe;
    wire       uart_tx_o;
    wire       irq_o;
    wire [31:0] irq_vector_o;
    wire       cpu_trap_o;
    wire       cpu_halted_o;
    wire [31:0] cpu_fault_pc_o;
    wire [31:0] cpu_fault_cause_o;
    wire [31:0] cpu_pc_o;

    reg [7:0] i2c_writes [0:5];
    reg [3:0] i2c_write_count;
    reg       i2c_tip_d;
    integer   irq_pulses;
    integer   max_cycles;

    wire [7:0] i2c_read_data = 8'h5a;
    wire i2c_slave_sda_low =
        (dut.u_i2c.state == 4'd7) ||
        ((dut.u_i2c.state == 4'd9) &&
         !i2c_read_data[dut.u_i2c.bit_count]);
    wire i2c_scl_i = i2c_scl_oe ? 1'b0 : 1'b1;
    wire i2c_sda_i = i2c_sda_oe ? 1'b0 :
                     (i2c_slave_sda_low ? 1'b0 : 1'b1);

    soc_top #(
        .CLK_FREQ_HZ(166_666_667),
        .BOOT_INIT_FILE("firmware.hex")
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .gpio0_i(8'd0),
        .gpio0_o(gpio0_o),
        .gpio0_oe(gpio0_oe),
        .gpio1_i(gpio1_i),
        .gpio1_o(),
        .gpio1_oe(),
        .i2c_scl_i(i2c_scl_i),
        .i2c_scl_o(i2c_scl_o),
        .i2c_scl_oe(i2c_scl_oe),
        .i2c_sda_i(i2c_sda_i),
        .i2c_sda_o(i2c_sda_o),
        .i2c_sda_oe(i2c_sda_oe),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o),
        .ext_irq_i(2'b00),
        .irq_o(irq_o),
        .irq_vector_o(irq_vector_o),
        .cpu_trap_o(cpu_trap_o),
        .cpu_halted_o(cpu_halted_o),
        .cpu_fault_pc_o(cpu_fault_pc_o),
        .cpu_fault_cause_o(cpu_fault_cause_o),
        .cpu_pc_o(cpu_pc_o)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2.0) clk = ~clk;
    end

    function automatic bit is_error_marker(input [7:0] value);
        begin
            is_error_marker = (value >= 8'he1) && (value <= 8'he8);
        end
    endfunction

    task automatic wait_marker(input [7:0] value, input string name);
        integer cycles;
        begin
            cycles = 0;
            while ((gpio0_o !== value) && (cycles < max_cycles)) begin
                @(posedge clk);
                cycles = cycles + 1;
                if (is_error_marker(gpio0_o))
                    $fatal(1, "Firmware error marker 0x%02x while waiting for %s",
                           gpio0_o, name);
            end
            if (gpio0_o !== value)
                $fatal(1, "Timeout waiting for %s marker=0x%02x gpio0=0x%02x pc=0x%08x",
                       name, value, gpio0_o, cpu_pc_o);
            $display("| MARK | %-18s | GPIO0=0x%02x | PC=0x%08x | wait=%0d cycles |",
                     name, value, cpu_pc_o, cycles);
        end
    endtask

    task automatic send_uart_byte(input [7:0] value, input integer bit_cycles);
        integer bit_index;
        begin
            uart_rx_i = 1'b0;
            repeat (bit_cycles) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx_i = value[bit_index];
                repeat (bit_cycles) @(posedge clk);
            end
            uart_rx_i = 1'b1;
            repeat (bit_cycles) @(posedge clk);
        end
    endtask

    task automatic receive_uart_byte(
        input [7:0] expected,
        input integer bit_cycles,
        input string label
    );
        reg [7:0] value;
        integer bit_index;
        begin
            @(negedge uart_tx_o);
            repeat (bit_cycles + (bit_cycles / 2)) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                value[bit_index] = uart_tx_o;
                if (bit_index != 7)
                    repeat (bit_cycles) @(posedge clk);
            end
            repeat (bit_cycles) @(posedge clk);
            if (uart_tx_o !== 1'b1)
                $fatal(1, "%s stop bit was not high", label);
            if (value !== expected)
                $fatal(1, "%s expected 0x%02x, got 0x%02x",
                       label, expected, value);
            $display("| UART | %-18s | TX=0x%02x ('%c') | frame=8N1 | PASS          |",
                     label, value, value);
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            irq_pulses <= 0;
            i2c_tip_d <= 1'b0;
            i2c_write_count <= 4'd0;
        end else begin
            if (irq_o)
                irq_pulses <= irq_pulses + 1;

            i2c_tip_d <= dut.u_i2c.transfer_in_progress;
            if (dut.u_i2c.transfer_in_progress && !i2c_tip_d &&
                dut.u_i2c.cmd_write && (i2c_write_count < 6)) begin
                i2c_writes[i2c_write_count] <= dut.u_i2c.txr;
                i2c_write_count <= i2c_write_count + 4'd1;
            end

            if (cpu_trap_o || cpu_halted_o)
                $fatal(1, "CPU fault pc=0x%08x cause=0x%08x",
                       cpu_fault_pc_o, cpu_fault_cause_o);
            if (dut.cpu_wb_err)
                $fatal(1, "Unexpected Wishbone error addr=0x%08x pc=0x%08x",
                       dut.cpu_wb_adr, cpu_pc_o);
        end
    end

    initial begin
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles))
            max_cycles = 2000000;

        rst = 1'b1;
        gpio1_i = 8'd0;
        uart_rx_i = 1'b1;
        irq_pulses = 0;
        i2c_tip_d = 1'b0;
        i2c_write_count = 4'd0;
        repeat (10) @(posedge clk);
        rst = 1'b0;

        $display("REPORT-BEGIN: SOC");
        $display("");
        $display("================================================================================");
        $display("* FULL MICROCONTROLLER SIMULATION - CPU, WISHBONE AND ALL MAIN PERIPHERALS      *");
        $display("================================================================================");
        $display("| Clock=166.667 MHz | CPU=RV32I | UART=8N1 | I2C=100 kHz | IRQ via PIC        |");

        $display("");
        $display("---------------- CASE 1 / GPIO OUTPUT ------------------------------------------");
        wait_marker(8'h11, "GPIO output");
        if ((gpio0_o !== 8'h11) || (gpio0_oe !== 8'hff))
            $fatal(1, "GPIO output mismatch value=0x%02x oe=0x%02x",
                   gpio0_o, gpio0_oe);
        $display("| PASS | GPIO0 output=0x11 | direction=0x%02x                               |",
                 gpio0_oe);

        $display("");
        $display("---------------- CASE 2 / UART 115200, SEND \"Hi\" ------------------------------");
        wait_marker(8'h20, "UART 115200 ready");
        receive_uart_byte("H", UART_115200_BIT_CYCLES, "115200 byte 0");
        receive_uart_byte("i", UART_115200_BIT_CYCLES, "115200 byte 1");
        wait_marker(8'h22, "UART 115200 done");

        $display("");
        $display("---------------- CASE 3 / UART RX INTERRUPT A -> B -----------------------------");
        wait_marker(8'h31, "UART IRQ ready");
        $display("| DRIVE| UART RX <= 'A' at 115200 baud                                       |");
        fork
            receive_uart_byte("B", UART_115200_BIT_CYCLES, "UART IRQ reply");
            send_uart_byte("A", UART_115200_BIT_CYCLES);
        join
        wait_marker(8'h32, "UART IRQ handled");
        $display("| PASS | RX interrupt entered handler and firmware replied with 'B'           |");

        $display("");
        $display("---------------- CASE 4 / I2C 100 kHz MEMORY WRITE AND READ --------------------");
        wait_marker(8'h41, "I2C transaction");
        wait_marker(8'h42, "I2C verified");
        if (i2c_write_count !== 6 ||
            i2c_writes[0] !== 8'ha0 || i2c_writes[1] !== 8'h12 ||
            i2c_writes[2] !== 8'h5a || i2c_writes[3] !== 8'ha0 ||
            i2c_writes[4] !== 8'h12 || i2c_writes[5] !== 8'ha1)
            $fatal(1, "I2C command sequence mismatch count=%0d", i2c_write_count);
        $display("| PASS | slave=0x50 | address=0x12 | write/read data=0x5A                    |");

        $display("");
        $display("---------------- CASE 5 / TIMER INTERRUPT --------------------------------------");
        wait_marker(8'h51, "Timer armed");
        wait_marker(8'h52, "Timer IRQ handled");
        $display("| PASS | Timer -> PIC -> RV32I trap handler -> mret                           |");

        $display("");
        $display("---------------- CASE 6 / GPIO RISING-EDGE INTERRUPT ---------------------------");
        wait_marker(8'h61, "GPIO IRQ armed");
        $display("| DRIVE| GPIO1[0] 0 -> 1 -> 0                                                |");
        gpio1_i[0] = 1'b1;
        repeat (8) @(posedge clk);
        gpio1_i[0] = 1'b0;
        wait_marker(8'h62, "GPIO IRQ handled");
        $display("| PASS | GPIO edge -> PIC -> RV32I trap handler -> mret                       |");

        $display("");
        $display("---------------- CASE 7 / UART 9600, SEND 'C' ---------------------------------");
        wait_marker(8'h71, "UART 9600 ready");
        receive_uart_byte("C", UART_9600_BIT_CYCLES, "9600 transmit");
        wait_marker(8'h72, "UART 9600 done");

        $display("");
        $display("---------------- CASE 8 / UART 9600 RX INTERRUPT D -> E ------------------------");
        wait_marker(8'h81, "UART 9600 IRQ ready");
        $display("| DRIVE| UART RX <= 'D' at 9600 baud                                         |");
        fork
            receive_uart_byte("E", UART_9600_BIT_CYCLES, "9600 IRQ reply");
            send_uart_byte("D", UART_9600_BIT_CYCLES);
        join
        wait_marker(8'h82, "UART 9600 IRQ done");
        wait_marker(8'ha5, "all cases complete");

        if (irq_pulses == 0)
            $fatal(1, "PIC never asserted IRQ");
        if (dut.u_cpu.u_csr.mcause !== 32'h8000_000b)
            $fatal(1, "Unexpected mcause 0x%08x", dut.u_cpu.u_csr.mcause);

        $display("================================================================================");
        $display("* RESULT: PASS - ALL 8 FULL-MICROCONTROLLER CASES COMPLETED.                   *");
        $display("* GPIO + UART 115200/9600 + UART IRQ + I2C + TIMER IRQ + GPIO IRQ VERIFIED.    *");
        $display("================================================================================");
        $display("REPORT-END: SOC");
        $display("PASS: full microcontroller completed all 8 peripheral and interrupt cases");
        $finish;
    end

endmodule
