`timescale 1ns/1ps

module tb_soc_top;
    localparam real CLK_PERIOD_NS = 6.0;

    reg clk;
    reg rst;
    reg i2c_scl_i;
    reg i2c_sda_i;
    reg uart_rx_i;
    reg [1:0] ext_irq_i;

    wire [7:0] gpio0_o;
    wire [7:0] gpio0_oe;
    wire [7:0] gpio1_o;
    wire [7:0] gpio1_oe;
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

    int max_cycles;
    int boot_reads;
    int sram_accesses;
    int gpio0_accesses;
    int uart_accesses;
    int kyber_accesses;
    int marker_count;
    reg [7:0] last_marker;

    soc_top #(
        .CLK_FREQ_HZ(166_666_667),
        .BOOT_INIT_FILE("firmware.hex")
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .gpio0_i(8'd0),
        .gpio0_o(gpio0_o),
        .gpio0_oe(gpio0_oe),
        .gpio1_i(8'd0),
        .gpio1_o(gpio1_o),
        .gpio1_oe(gpio1_oe),
        .i2c_scl_i(i2c_scl_i),
        .i2c_scl_o(i2c_scl_o),
        .i2c_scl_oe(i2c_scl_oe),
        .i2c_sda_i(i2c_sda_i),
        .i2c_sda_o(i2c_sda_o),
        .i2c_sda_oe(i2c_sda_oe),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o),
        .ext_irq_i(ext_irq_i),
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

    function automatic bit is_error_marker(input [7:0] marker);
        begin
            is_error_marker = (marker >= 8'hE1) && (marker <= 8'hE5);
        end
    endfunction

    task automatic wait_marker(input [7:0] marker, input string name);
        int cycles;
        begin
            cycles = 0;
            while ((gpio0_o !== marker) && (cycles < max_cycles)) begin
                @(posedge clk);
                cycles++;
                if (cpu_trap_o || cpu_halted_o) begin
                    $fatal(1, "CPU stopped before marker %s pc=0x%08x cause=0x%08x gpio0=0x%02x",
                           name, cpu_fault_pc_o, cpu_fault_cause_o, gpio0_o);
                end
                if (is_error_marker(gpio0_o)) begin
                    $fatal(1, "Firmware error marker 0x%02x while waiting for %s pc=0x%08x",
                           gpio0_o, name, cpu_pc_o);
                end
            end

            if (gpio0_o !== marker) begin
                $fatal(1, "Timeout waiting marker %s/0x%02x pc=0x%08x gpio0=0x%02x",
                       name, marker, cpu_pc_o, gpio0_o);
            end

            marker_count++;
            last_marker = marker;
            $display("tb_soc_top marker %-14s gpio0=0x%02x pc=0x%08x cycles=%0d",
                     name, gpio0_o, cpu_pc_o, cycles);
        end
    endtask

    always @(posedge clk) begin
        if (!rst) begin
            if (dut.boot_cyc && dut.boot_stb && dut.boot_ack && !dut.boot_we)
                boot_reads++;
            if (dut.sram_cyc && dut.sram_stb && dut.sram_ack)
                sram_accesses++;
            if (dut.gpio0_cyc && dut.gpio0_stb && dut.gpio0_ack)
                gpio0_accesses++;
            if (dut.uart_cyc && dut.uart_stb && dut.uart_ack)
                uart_accesses++;
            if (dut.kyber_cyc && dut.kyber_stb && dut.kyber_ack)
                kyber_accesses++;
            if (dut.cpu_wb_err) begin
                $fatal(1, "Unexpected Wishbone error addr=0x%08x pc=0x%08x",
                       dut.cpu_wb_adr, cpu_pc_o);
            end
        end
    end

    initial begin
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles))
            max_cycles = 80000000;

        i2c_scl_i = 1'b1;
        i2c_sda_i = 1'b1;
        uart_rx_i = 1'b1;
        ext_irq_i = 2'b00;
        boot_reads = 0;
        sram_accesses = 0;
        gpio0_accesses = 0;
        uart_accesses = 0;
        kyber_accesses = 0;
        marker_count = 0;
        last_marker = 8'h00;

        rst = 1'b1;
        repeat (10) @(posedge clk);
        rst = 1'b0;

        wait_marker(8'h01, "boot");
        wait_marker(8'h11, "keygen");
        wait_marker(8'h22, "encaps");
        wait_marker(8'h33, "decaps_valid");
        wait_marker(8'h44, "decaps_invalid");
        wait_marker(8'hA5, "done");

        if (gpio0_oe !== 8'hff)
            $fatal(1, "GPIO0 direction mismatch got=0x%02x", gpio0_oe);
        if (gpio1_oe !== 8'h00)
            $fatal(1, "GPIO1 direction mismatch got=0x%02x", gpio1_oe);
        if (i2c_scl_o !== 1'b0 || i2c_sda_o !== 1'b0)
            $fatal(1, "I2C open-drain outputs must drive only low values");
        if (marker_count != 6 || last_marker != 8'hA5)
            $fatal(1, "Marker sequence incomplete count=%0d last=0x%02x",
                   marker_count, last_marker);
        if (boot_reads == 0 || sram_accesses == 0 || gpio0_accesses == 0 ||
            uart_accesses == 0 || kyber_accesses == 0) begin
            $fatal(1, "Missing bus coverage boot=%0d sram=%0d gpio0=%0d uart=%0d kyber=%0d",
                   boot_reads, sram_accesses, gpio0_accesses, uart_accesses, kyber_accesses);
        end

        $display("tb_soc_top bus coverage boot=%0d sram=%0d gpio0=%0d uart=%0d kyber=%0d",
                 boot_reads, sram_accesses, gpio0_accesses, uart_accesses, kyber_accesses);
        $display("PASS: tb_soc_top full-system firmware simulation completed");
        $finish;
    end
endmodule
