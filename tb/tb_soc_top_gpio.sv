`timescale 1ns/1ps

module tb_soc_top_gpio;
    localparam real CLK_PERIOD_NS = 6.0;

    reg clk;
    reg rst;

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

    soc_top #(
        .CLK_FREQ_HZ(166_666_667),
        .BOOT_INIT_FILE("../../tb/fixtures/soc_gpio_boot.hex")
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .gpio0_i(8'd0),
        .gpio0_o(gpio0_o),
        .gpio0_oe(gpio0_oe),
        .gpio1_i(8'd0),
        .gpio1_o(gpio1_o),
        .gpio1_oe(gpio1_oe),
        .i2c_scl_i(1'b1),
        .i2c_scl_o(i2c_scl_o),
        .i2c_scl_oe(i2c_scl_oe),
        .i2c_sda_i(1'b1),
        .i2c_sda_o(i2c_sda_o),
        .i2c_sda_oe(i2c_sda_oe),
        .uart_rx_i(1'b1),
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

    initial begin
        rst = 1'b1;
        repeat (10) @(posedge clk);
        rst = 1'b0;

        repeat (500) begin
            @(posedge clk);
            if (cpu_trap_o || cpu_halted_o) begin
                $fatal(1, "CPU trapped unexpectedly pc=0x%08x cause=0x%08x",
                       cpu_fault_pc_o, cpu_fault_cause_o);
            end
        end

        if (gpio0_oe !== 8'hff)
            $fatal(1, "GPIO0 direction mismatch got=0x%02x", gpio0_oe);
        if (gpio0_o !== 8'ha5)
            $fatal(1, "GPIO0 value mismatch got=0x%02x", gpio0_o);

        $display("PASS: soc_top CPU wrote GPIO0 through Wishbone, pc=0x%08x", cpu_pc_o);
        $finish;
    end
endmodule
