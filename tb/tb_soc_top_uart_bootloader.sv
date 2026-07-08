`timescale 1ns/1ps

module tb_soc_top_uart_bootloader;
    localparam real CLK_PERIOD_NS = 6.0;
    localparam integer BIT_CYCLES = 1440; // divider 90 x 16 at 166.667 MHz
    localparam integer MAX_PAYLOAD_BYTES = 4096;

    reg clk;
    reg rst;
    reg uart_rx_i;
    reg i2c_scl_i;
    reg i2c_sda_i;
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

    reg [31:0] payload_words [0:(MAX_PAYLOAD_BYTES/4)-1];
    int payload_bytes;
    int max_cycles;

    soc_top #(
        .CLK_FREQ_HZ(166_666_667),
        .BOOTLOADER_ENABLE(1),
        .BOOT_BYTES(32*1024),
        .BOOT_ROM_BYTES(16*1024),
        .SRAM_BYTES(16*1024),
        .BOOT_INIT_FILE("bootloader.hex")
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

    function automatic [7:0] payload_byte(input int index);
        reg [31:0] word;
        begin
            word = payload_words[index >> 2];
            case (index & 3)
                0: payload_byte = word[7:0];
                1: payload_byte = word[15:8];
                2: payload_byte = word[23:16];
                default: payload_byte = word[31:24];
            endcase
        end
    endfunction

    task automatic send_uart_byte(input [7:0] value);
        int bit_i;
        begin
            uart_rx_i = 1'b0;
            repeat (BIT_CYCLES) @(posedge clk);
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                uart_rx_i = value[bit_i];
                repeat (BIT_CYCLES) @(posedge clk);
            end
            uart_rx_i = 1'b1;
            repeat (BIT_CYCLES) @(posedge clk);
        end
    endtask

    task automatic send_u32_le(input [31:0] value);
        begin
            send_uart_byte(value[7:0]);
            send_uart_byte(value[15:8]);
            send_uart_byte(value[23:16]);
            send_uart_byte(value[31:24]);
        end
    endtask

    task automatic send_binary_packet;
        int i;
        reg [31:0] checksum;
        begin
            checksum = 32'd0;
            for (i = 0; i < payload_bytes; i = i + 1)
                checksum = checksum + payload_byte(i);

            send_uart_byte("K");
            send_uart_byte("B");
            send_uart_byte("L");
            send_uart_byte("1");
            send_u32_le(32'h0000_4000);
            send_u32_le(payload_bytes[31:0]);
            send_u32_le(32'h0000_4000);
            send_u32_le(checksum);
            for (i = 0; i < payload_bytes; i = i + 1)
                send_uart_byte(payload_byte(i));
        end
    endtask

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
            end
            if (gpio0_o !== marker)
                $fatal(1, "Timeout waiting marker %s/0x%02x pc=0x%08x gpio0=0x%02x",
                       name, marker, cpu_pc_o, gpio0_o);
            $display("tb_soc_top_uart_bootloader marker %-8s gpio0=0x%02x pc=0x%08x cycles=%0d",
                     name, gpio0_o, cpu_pc_o, cycles);
        end
    endtask

    always @(posedge clk) begin
        if (!rst && dut.cpu_wb_err) begin
            $fatal(1, "Unexpected Wishbone error addr=0x%08x pc=0x%08x",
                   dut.cpu_wb_adr, cpu_pc_o);
        end
    end

    initial begin
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles))
            max_cycles = 12000000;
        if (!$value$plusargs("PAYLOAD_BYTES=%d", payload_bytes))
            $fatal(1, "Missing +PAYLOAD_BYTES");
        if (payload_bytes <= 0 || payload_bytes > MAX_PAYLOAD_BYTES)
            $fatal(1, "Invalid payload size %0d", payload_bytes);

        $readmemh("payload.hex", payload_words);

        i2c_scl_i = 1'b1;
        i2c_sda_i = 1'b1;
        uart_rx_i = 1'b1;
        ext_irq_i = 2'b00;

        rst = 1'b1;
        repeat (20) @(posedge clk);
        rst = 1'b0;

        wait_marker(8'hB0, "ready");
        send_binary_packet();
        wait_marker(8'hB3, "jump");
        wait_marker(8'hA5, "payload");

        if (gpio0_oe !== 8'hff)
            $fatal(1, "GPIO0 direction mismatch got=0x%02x", gpio0_oe);

        $display("PASS: UART bootloader loaded an IMEM payload and jumped to it");
        $finish;
    end
endmodule
