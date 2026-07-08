`timescale 1ns/1ps

module tb_uart_wb;
    reg clk;
    reg rst;
    reg [31:0] adr;
    reg [31:0] dat_i;
    wire [31:0] dat_o;
    reg [3:0] sel;
    reg we;
    reg cyc;
    reg stb;
    wire ack;
    wire err;
    wire tx;
    wire irq;
    reg rx_drive;
    reg loopback_enable;
    wire rx = loopback_enable ? tx : rx_drive;

    uart_wb #(.CLK_FREQ_HZ(16_000_000), .BAUD_DEFAULT(1_000_000)) dut (
        .wb_clk_i(clk), .wb_rst_i(rst), .wb_adr_i(adr), .wb_dat_i(dat_i),
        .wb_dat_o(dat_o), .wb_sel_i(sel), .wb_we_i(we), .wb_cyc_i(cyc),
        .wb_stb_i(stb), .wb_ack_o(ack), .wb_err_o(err), .uart_rx_i(rx),
        .uart_tx_o(tx), .irq_o(irq)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    task automatic wb_write(input [7:0] offset, input [31:0] value);
        begin
            @(posedge clk);
            adr <= offset; dat_i <= value; sel <= 4'hf; we <= 1; cyc <= 1; stb <= 1;
            do @(posedge clk); while (!ack);
            cyc <= 0; stb <= 0; we <= 0;
        end
    endtask

    task automatic wb_read(input [7:0] offset, output [31:0] value);
        begin
            @(posedge clk);
            adr <= offset; sel <= 4'hf; we <= 0; cyc <= 1; stb <= 1;
            do @(posedge clk); while (!ack);
            #1;
            value = dat_o;
            cyc <= 0; stb <= 0;
        end
    endtask

    task automatic wait_rx;
        integer n;
        reg [31:0] count;
        begin
            count = 0;
            for (n = 0; (n < 500) && (count == 0); n = n + 1) begin
                wb_read(8'h14, count);
            end
            if (count == 0) $fatal(1, "UART loopback RX timeout");
        end
    endtask

    task automatic drive_serial_bit(input bit_value);
        begin
            @(negedge clk);
            rx_drive = bit_value;
            repeat (16) @(posedge clk);
        end
    endtask

    task automatic send_serial_frame(
        input [7:0] data,
        input integer data_bits,
        input parity_enable,
        input parity_bit,
        input stop_bit
    );
        integer bit_index;
        begin
            drive_serial_bit(1'b0);
            for (bit_index = 0; bit_index < data_bits; bit_index = bit_index + 1)
                drive_serial_bit(data[bit_index]);
            if (parity_enable)
                drive_serial_bit(parity_bit);
            drive_serial_bit(stop_bit);
            rx_drive = 1'b1;
            repeat (4) @(posedge clk);
        end
    endtask

    task automatic test_case(input string title);
        begin
            $display("");
            $display("-------------------- %-56s", title);
        end
    endtask

    reg [31:0] value;
    integer fifo_index;
    initial begin
        rst=1; adr=0; dat_i=0; sel=0; we=0; cyc=0; stb=0;
        rx_drive=1; loopback_enable=1;
        repeat (4) @(posedge clk); rst=0;

        $display("REPORT-BEGIN: UART");
        $display("");
        $display("==============================================================================");
        $display("* UART WISHBONE FUNCTIONAL SIMULATION                                        *");
        $display("==============================================================================");
        $display("| Clock=16 MHz | Baud=1 Mbit/s | Oversampling=16x | FIFO depth=32           |");

        wb_write(8'h20, 32'd1);
        wb_write(8'h1c, 32'h20);

        test_case("CASE 1 - 8 DATA BITS, NO PARITY, 1 STOP BIT");
        wb_write(8'h08, 32'h0000_00e3);
        wb_write(8'h08, 32'h0000_0083);
        wb_write(8'h00, 32'h0000_00a5);
        wait_rx();
        if (!irq) $fatal(1, "UART RX interrupt missing");
        wb_read(8'h04, value);
        if (value[7:0] !== 8'ha5)
            $fatal(1, "UART 8N1 loopback mismatch: got 0x%02x", value[7:0]);
        $display("| PASS | TX=0xA5 | RX=0x%02x | frame=8N1 | RX interrupt observed       |",
                 value[7:0]);

        test_case("CASE 2 - 7 DATA BITS, EVEN PARITY, 1 STOP BIT");
        wb_write(8'h08, 32'h0000_00aa);
        wb_write(8'h08, 32'h0000_008a);
        wb_write(8'h00, 32'h0000_0055);
        wait_rx();
        wb_read(8'h04, value);
        if (value[6:0] !== 7'h55)
            $fatal(1, "UART 7E1 loopback mismatch: got 0x%02x", value[7:0]);
        wb_read(8'h0c, value);
        if (value[2:0] !== 3'b000) $fatal(1, "UART error flags set: 0x%02x", value[7:0]);
        $display("| PASS | TX=0x55 | RX=0x55 | frame=7E1 | errors=0x%01x                   |",
                 value[2:0]);

        loopback_enable = 1'b0;

        test_case("CASE 3 - PARITY ERROR DETECTION");
        wb_write(8'h08, 32'h0000_00ab);
        wb_write(8'h08, 32'h0000_008b);
        send_serial_frame(8'h3c, 8, 1'b1, 1'b1, 1'b1);
        wait_rx();
        wb_read(8'h04, value);
        if (value[7:0] !== 8'h3c) $fatal(1, "UART parity test data mismatch");
        wb_read(8'h0c, value);
        if (!value[2]) $fatal(1, "UART parity error was not detected");
        $display("| PASS | RX=0x3C | deliberately wrong parity | parity_error=%0d          |",
                 value[2]);

        test_case("CASE 4 - FRAMING ERROR DETECTION");
        wb_write(8'h08, 32'h0000_00a3);
        wb_write(8'h08, 32'h0000_0083);
        send_serial_frame(8'h96, 8, 1'b0, 1'b0, 1'b0);
        wait_rx();
        wb_read(8'h04, value);
        if (value[7:0] !== 8'h96) $fatal(1, "UART framing test data mismatch");
        wb_read(8'h0c, value);
        if (!value[0]) $fatal(1, "UART framing error was not detected");
        $display("| PASS | RX=0x96 | stop bit forced low | framing_error=%0d               |",
                 value[0]);

        test_case("CASE 5 - MULTI-BYTE RX FIFO ORDERING");
        wb_write(8'h08, 32'h0000_00a3);
        wb_write(8'h08, 32'h0000_0083);
        send_serial_frame(8'h12, 8, 1'b0, 1'b0, 1'b1);
        send_serial_frame(8'h34, 8, 1'b0, 1'b0, 1'b1);
        send_serial_frame(8'h56, 8, 1'b0, 1'b0, 1'b1);
        wb_read(8'h14, value);
        if (value !== 32'd3) $fatal(1, "UART RX FIFO count mismatch: %0d", value);
        wb_read(8'h04, value);
        if (value[7:0] !== 8'h12) $fatal(1, "UART RX FIFO byte 0 mismatch");
        wb_read(8'h04, value);
        if (value[7:0] !== 8'h34) $fatal(1, "UART RX FIFO byte 1 mismatch");
        wb_read(8'h04, value);
        if (value[7:0] !== 8'h56) $fatal(1, "UART RX FIFO byte 2 mismatch");
        $display("| PASS | RX FIFO order = 0x12 / 0x34 / 0x56                              |");

        test_case("CASE 6 - RX FIFO OVERRUN");
        wb_write(8'h08, 32'h0000_00a3);
        wb_write(8'h08, 32'h0000_0083);
        for (fifo_index = 0; fifo_index < 33; fifo_index = fifo_index + 1)
            send_serial_frame(fifo_index[7:0], 8, 1'b0, 1'b0, 1'b1);
        wb_read(8'h14, value);
        if (value !== 32'd32)
            $fatal(1, "UART RX FIFO expected full count=32, got=%0d", value);
        wb_read(8'h0c, value);
        if (!value[1]) $fatal(1, "UART overrun error was not detected");
        $display("| PASS | sent=33 bytes | stored=32 bytes | overrun_error=%0d             |",
                 value[1]);

        $display("==============================================================================");
        $display("* RESULT: PASS - FRAME MODES, IRQ, ERROR FLAGS AND RX FIFO.                  *");
        $display("==============================================================================");
        $display("REPORT-END: UART");
        $display("PASS: UART 8N1, 7E1, parity/framing/overrun errors, RX FIFO and interrupt");
        $finish;
    end

endmodule
