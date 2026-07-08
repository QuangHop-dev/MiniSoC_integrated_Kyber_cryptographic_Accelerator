`timescale 1ns/1ps

module tb_i2c_wb;
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
    wire scl_o;
    wire scl_oe;
    wire sda_o;
    wire sda_oe;
    wire irq;
    reg [7:0] read_data;
    reg ack_low;
    reg force_arbitration_low;

    wire scl_i = scl_oe ? 1'b0 : 1'b1;
    wire read_bit = read_data[dut.bit_count];
    wire slave_sda_low =
        ((dut.state == 4'd7) && ack_low) ||
        ((dut.state == 4'd9) && !read_bit) ||
        ((dut.state == 4'd5) && force_arbitration_low);
    wire sda_i = sda_oe ? 1'b0 : (slave_sda_low ? 1'b0 : 1'b1);

    i2c_wb dut (
        .wb_clk_i(clk), .wb_rst_i(rst), .wb_adr_i(adr), .wb_dat_i(dat_i),
        .wb_dat_o(dat_o), .wb_sel_i(sel), .wb_we_i(we), .wb_cyc_i(cyc),
        .wb_stb_i(stb), .wb_ack_o(ack), .wb_err_o(err),
        .scl_i(scl_i), .scl_o(scl_o), .scl_oe(scl_oe),
        .sda_i(sda_i), .sda_o(sda_o), .sda_oe(sda_oe), .irq_o(irq)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    task automatic wb_write8(input [7:0] offset, input [7:0] value);
        begin
            @(posedge clk);
            adr <= offset; dat_i <= {24'd0, value}; sel <= 4'b0001;
            we <= 1; cyc <= 1; stb <= 1;
            do @(posedge clk); while (!ack);
            cyc <= 0; stb <= 0; we <= 0;
        end
    endtask

    task automatic wb_read8(input [7:0] offset, output [7:0] value);
        reg [31:0] word;
        begin
            @(posedge clk);
            adr <= offset; sel <= 4'b0001; we <= 0; cyc <= 1; stb <= 1;
            do @(posedge clk); while (!ack);
            #1;
            word = dat_o;
            value = word[7:0];
            cyc <= 0; stb <= 0;
        end
    endtask

    task automatic wait_done;
        integer timeout;
        begin
            timeout = 0;
            while (dut.transfer_in_progress && timeout < 1000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 1000) $fatal(1, "I2C command timeout");
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic test_case(input string title);
        begin
            $display("");
            $display("-------------------- %-56s", title);
        end
    endtask

    reg [7:0] value;
    initial begin
        rst=1; adr=0; dat_i=0; sel=0; we=0; cyc=0; stb=0;
        read_data=8'h00; ack_low=1'b1; force_arbitration_low=1'b0;
        repeat (4) @(posedge clk); rst=0;

        $display("REPORT-BEGIN: I2C");
        $display("");
        $display("==============================================================================");
        $display("* I2C WISHBONE MASTER FUNCTIONAL SIMULATION                                  *");
        $display("==============================================================================");

        test_case("CASE 1 - PRESCALER AND CORE ENABLE");
        wb_write8(8'h00, 8'h01);
        wb_write8(8'h01, 8'h00);
        wb_write8(8'h02, 8'hc0);
        wb_read8(8'h00, value);
        if (value !== 8'h01) $fatal(1, "I2C prescaler readback mismatch");
        wb_read8(8'h02, value);
        if (value !== 8'hc0) $fatal(1, "I2C control readback mismatch");
        $display("| PASS | prescaler=1 | core enabled | interrupt enabled                  |");

        test_case("CASE 2 - START, WRITE, ACK AND STOP");
        ack_low = 1'b1;
        wb_write8(8'h03, 8'h00);
        wb_write8(8'h04, 8'hd0);
        wait_done();
        wb_read8(8'h04, value);
        if (value[7] || value[6] || value[1] || !value[0])
            $fatal(1, "I2C write/stop status mismatch: 0x%02x", value);
        if (!irq) $fatal(1, "I2C IRQ missing after command");
        $display("| PASS | START+WRITE+STOP | ACK received | IF=%0d | BUSY=%0d            |",
                 value[0], value[6]);

        test_case("CASE 3 - INTERRUPT ACKNOWLEDGE");
        wb_write8(8'h04, 8'h01);
        @(posedge clk);
        if (irq) $fatal(1, "I2C interrupt acknowledge failed");
        wb_read8(8'h04, value);
        if (value[0]) $fatal(1, "I2C interrupt flag still set");
        $display("| PASS | IACK cleared interrupt flag                                    |");

        test_case("CASE 4 - READ BYTE AND NACK");
        read_data = 8'h5a;
        wb_write8(8'h04, 8'h68);
        wait_done();
        wb_read8(8'h03, value);
        if (value !== 8'h5a) $fatal(1, "I2C read data mismatch: 0x%02x", value);
        $display("| PASS | READ+NACK+STOP | RXR=0x%02x                                   |",
                 value);
        wb_write8(8'h04, 8'h01);

        test_case("CASE 5 - NACK AND ARBITRATION STATUS");
        ack_low = 1'b0;
        wb_write8(8'h03, 8'h00);
        wb_write8(8'h04, 8'hd0);
        wait_done();
        wb_read8(8'h04, value);
        if (!value[7]) $fatal(1, "I2C RXACK did not report NACK");
        ack_low = 1'b1;
        force_arbitration_low = 1'b1;
        wb_write8(8'h03, 8'h80);
        wb_write8(8'h04, 8'hd0);
        wait_done();
        wb_read8(8'h04, value);
        if (!value[5]) $fatal(1, "I2C arbitration-lost flag missing");
        force_arbitration_low = 1'b0;
        $display("| PASS | NACK and arbitration-lost status detected                      |");

        $display("==============================================================================");
        $display("* RESULT: PASS - COMMAND, ACK/NACK, READ, IRQ AND ARBITRATION STATUS.         *");
        $display("==============================================================================");
        $display("REPORT-END: I2C");
        $display("PASS: I2C prescaler, write/read commands, ACK/NACK, IRQ and arbitration status");
        $finish;
    end

endmodule
