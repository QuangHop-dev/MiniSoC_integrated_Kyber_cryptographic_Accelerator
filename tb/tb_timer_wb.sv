`timescale 1ns/1ps

module tb_timer_wb;
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
    wire irq;

    timer_wb dut (
        .wb_clk_i(clk), .wb_rst_i(rst), .wb_adr_i(adr), .wb_dat_i(dat_i),
        .wb_dat_o(dat_o), .wb_sel_i(sel), .wb_we_i(we), .wb_cyc_i(cyc),
        .wb_stb_i(stb), .wb_ack_o(ack), .wb_err_o(err), .irq_o(irq)
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

    integer cycles;
    reg [31:0] value;
    initial begin
        rst=1; adr=0; dat_i=0; sel=0; we=0; cyc=0; stb=0;
        repeat (4) @(posedge clk); rst=0;

        $display("REPORT-BEGIN: TIMER");
        $display("");
        $display("==============================================================================");
        $display("* TIMER WISHBONE FUNCTIONAL SIMULATION                                       *");
        $display("==============================================================================");

        test_case("CASE 1 - COUNT UP AND PERIOD MATCH");
        wb_write(8'h04, 32'd0);
        wb_write(8'h08, 32'd3);
        wb_write(8'h00, 32'h0000_0001);
        repeat (5) @(posedge clk);
        wb_write(8'h00, 32'd0);
        wb_read(8'h0c, value);
        if ((value & 1) == 0) $fatal(1, "Timer period status missing");
        $display("| PASS | count-up reached period=3 | status=0x%02x                    |",
                 value[7:0]);

        test_case("CASE 2 - AUTO RELOAD");
        wb_write(8'h04, 32'd0);
        wb_write(8'h08, 32'd2);
        wb_write(8'h00, 32'h0000_0009);
        repeat (8) @(posedge clk);
        wb_write(8'h00, 32'd0);
        wb_read(8'h04, value);
        if (value > 2) $fatal(1, "Timer auto-reload count out of range");
        $display("| PASS | auto-reload kept count in range 0..2 | count=%0d               |",
                 value);
        wb_read(8'h0c, value);

        test_case("CASE 3 - COUNT DOWN AND UNDERFLOW");
        wb_write(8'h04, 32'd2);
        wb_write(8'h08, 32'd5);
        wb_write(8'h00, 32'h0000_0003);
        repeat (5) @(posedge clk);
        wb_write(8'h00, 32'd0);
        wb_read(8'h0c, value);
        if ((value & 4) == 0) $fatal(1, "Timer underflow status missing");
        $display("| PASS | count-down underflow detected | status=0x%02x                 |",
                 value[7:0]);

        test_case("CASE 4 - OVERFLOW");
        wb_write(8'h04, 32'h0000_ffff);
        wb_write(8'h08, 32'h0000_1234);
        wb_write(8'h00, 32'h0000_0001);
        repeat (2) @(posedge clk);
        wb_write(8'h00, 32'd0);
        wb_read(8'h0c, value);
        if ((value & 2) == 0) $fatal(1, "Timer overflow status missing");
        $display("| PASS | overflow detected at 0xFFFF | status=0x%02x                  |",
                 value[7:0]);

        test_case("CASE 5 - PRESCALER AND INTERRUPT");
        wb_write(8'h04, 32'd0);
        wb_write(8'h08, 32'd3);
        wb_write(8'h10, 32'd2);
        wb_write(8'h0c, 32'hffff);
        wb_write(8'h00, 32'h0000_0015);
        cycles = 0;
        while (!irq && cycles < 30) begin @(posedge clk); cycles++; end
        if (!irq) $fatal(1, "Timer IRQ timeout");
        wb_write(8'h00, 32'd0);
        wb_read(8'h0c, value);
        if ((value & 1) == 0) $fatal(1, "Timer IRQ status missing");
        @(posedge clk);
        if (irq) $fatal(1, "Timer IRQ did not clear on status read");
        $display("| PASS | prescaler=2 | period=3 | irq after %0d observed cycles          |",
                 cycles);

        test_case("CASE 6 - RESET");
        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
        if (dut.count_reg !== 16'd0 || dut.count_enable !== 1'b0 ||
            dut.status_reg !== 16'd0)
            $fatal(1, "Timer reset state mismatch");
        $display("| PASS | reset cleared enable, count and status                         |");

        $display("==============================================================================");
        $display("* RESULT: PASS - COUNT, RELOAD, PRESCALER, IRQ, OVERFLOW AND UNDERFLOW.      *");
        $display("==============================================================================");
        $display("REPORT-END: TIMER");
        $display("PASS: timer prescaler, period match, status and interrupt");
        $finish;
    end

endmodule
