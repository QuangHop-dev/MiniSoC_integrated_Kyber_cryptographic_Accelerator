`timescale 1ns/1ps

module tb_gpio_wb;
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
    reg [7:0] gpio_i;
    wire [7:0] gpio_o;
    wire [7:0] gpio_oe;
    wire irq;

    gpio_wb dut (
        .wb_clk_i(clk), .wb_rst_i(rst), .wb_adr_i(adr), .wb_dat_i(dat_i),
        .wb_dat_o(dat_o), .wb_sel_i(sel), .wb_we_i(we), .wb_cyc_i(cyc),
        .wb_stb_i(stb), .wb_ack_o(ack), .wb_err_o(err), .gpio_i(gpio_i),
        .gpio_o(gpio_o), .gpio_oe(gpio_oe), .irq_o(irq)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    task automatic wb_write(input [7:0] offset, input [31:0] value);
        begin
            @(posedge clk);
            adr <= offset; dat_i <= value; sel <= 4'hf; we <= 1; cyc <= 1; stb <= 1;
            do @(posedge clk); while (!ack);
            cyc <= 0; stb <= 0; we <= 0;
            $display("| WB-W | addr=0x%02x | data=0x%08x | time=%0t ps |",
                     offset, value, $time);
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
            $display("| WB-R | addr=0x%02x | data=0x%08x | time=%0t ps |",
                     offset, value, $time);
        end
    endtask

    task automatic test_case(input string title);
        begin
            $display("");
            $display("-------------------- %-56s", title);
        end
    endtask

    reg [31:0] value;
    initial begin
        rst=1; adr=0; dat_i=0; sel=0; we=0; cyc=0; stb=0; gpio_i=0;
        repeat (4) @(posedge clk); rst=0;

        $display("REPORT-BEGIN: GPIO");
        $display("");
        $display("==============================================================================");
        $display("* GPIO WISHBONE FUNCTIONAL SIMULATION                                        *");
        $display("==============================================================================");

        test_case("CASE 1 - BASIC OUTPUT");
        wb_write(8'h00, 32'h0000_00f0);
        wb_write(8'h04, 32'h0000_00a0);
        if (gpio_oe !== 8'hf0 || gpio_o !== 8'ha0)
            $fatal(1, "GPIO output mismatch");
        $display("| PASS | gpio_oe=0x%02x | gpio_o=0x%02x                              |",
                 gpio_oe, gpio_o);

        test_case("CASE 2 - MIXED INPUT/OUTPUT");
        gpio_i = 8'h05;
        repeat (4) @(posedge clk);
        wb_read(8'h04, value);
        if (value[7:0] !== 8'ha5)
            $fatal(1, "GPIO mixed input/output mismatch");
        $display("| PASS | upper nibble output=0xA | lower nibble input=0x5              |");

        test_case("CASE 3 - ATOMIC SET/CLEAR");
        wb_write(8'h1c, 32'h0000_000f);
        if (gpio_o !== 8'haf) $fatal(1, "GPIO set mismatch");
        $display("| PASS | SET   mask=0x0F | gpio_o=0x%02x                               |",
                 gpio_o);
        wb_write(8'h20, 32'h0000_000c);
        if (gpio_o !== 8'ha3) $fatal(1, "GPIO clear mismatch");
        $display("| PASS | CLEAR mask=0x0C | gpio_o=0x%02x                               |",
                 gpio_o);

        test_case("CASE 4 - RISING-EDGE INTERRUPT");
        gpio_i = 8'h00;
        repeat (4) @(posedge clk);
        wb_write(8'h0c, 32'h0000_00ff);
        wb_write(8'h10, 32'h0000_0001);
        wb_write(8'h14, 32'h0000_00ff);
        wb_write(8'h08, 32'h0000_0001);
        gpio_i[0] = 1'b1;
        repeat (4) @(posedge clk);
        if (!irq) $fatal(1, "GPIO rising-edge IRQ missing");
        wb_read(8'h14, value);
        if ((value & 1) == 0) $fatal(1, "GPIO edge IRQ status missing");
        $display("| PASS | edge trigger bit0 | status=0x%02x | irq=%0d                    |",
                 value[7:0], irq);
        gpio_i[0] = 1'b0;
        repeat (4) @(posedge clk);
        wb_write(8'h14, 32'h0000_0001);
        @(posedge clk);
        if (irq) $fatal(1, "GPIO edge IRQ did not clear");

        test_case("CASE 5 - HIGH-LEVEL INTERRUPT");
        wb_write(8'h08, 32'h0000_0000);
        wb_write(8'h0c, 32'h0000_00fd);
        wb_write(8'h10, 32'h0000_0002);
        wb_write(8'h14, 32'h0000_00ff);
        wb_write(8'h08, 32'h0000_0002);
        gpio_i[1] = 1'b1;
        repeat (4) @(posedge clk);
        if (!irq) $fatal(1, "GPIO high-level IRQ missing");
        wb_read(8'h14, value);
        if ((value & 2) == 0) $fatal(1, "GPIO level IRQ status missing");
        $display("| PASS | level trigger bit1 | status=0x%02x | irq=%0d                   |",
                 value[7:0], irq);
        gpio_i[1] = 1'b0;
        repeat (4) @(posedge clk);
        wb_write(8'h14, 32'h0000_0002);
        @(posedge clk);
        if (irq) $fatal(1, "GPIO level IRQ did not clear");

        test_case("CASE 6 - MIXED PER-PIN EDGE POLARITY");
        wb_write(8'h08, 32'h0000_0000);
        gpio_i = 8'h04;
        repeat (4) @(posedge clk);
        wb_write(8'h0c, 32'h0000_000c);
        wb_write(8'h10, 32'h0000_0008);
        wb_write(8'h14, 32'h0000_00ff);
        wb_write(8'h08, 32'h0000_000c);
        gpio_i = 8'h08;
        repeat (4) @(posedge clk);
        if (!irq) $fatal(1, "GPIO mixed-polarity IRQ missing");
        wb_read(8'h14, value);
        if ((value & 8'h0c) !== 8'h0c)
            $fatal(1, "GPIO mixed-polarity status mismatch");
        $display("| PASS | bit2 falling + bit3 rising | status=0x%02x | irq=%0d          |",
                 value[7:0], irq);
        gpio_i = 8'h00;
        repeat (4) @(posedge clk);
        wb_write(8'h14, 32'h0000_000c);
        @(posedge clk);
        if (irq) $fatal(1, "GPIO mixed-polarity IRQ did not clear");

        $display("==============================================================================");
        $display("* RESULT: PASS - OUTPUT, INPUT, SET/CLEAR, LEVEL AND PER-PIN EDGE IRQ.       *");
        $display("==============================================================================");
        $display("REPORT-END: GPIO");
        $display("PASS: GPIO direction, output, synchronized input and edge interrupt");
        $finish;
    end

endmodule
