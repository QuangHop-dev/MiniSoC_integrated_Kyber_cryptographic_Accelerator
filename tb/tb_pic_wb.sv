`timescale 1ns/1ps

module tb_pic_wb;
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
    reg [7:0] irq_sources;
    wire irq;
    wire [31:0] irq_vector;

    pic_wb dut (
        .wb_clk_i(clk), .wb_rst_i(rst), .wb_adr_i(adr), .wb_dat_i(dat_i),
        .wb_dat_o(dat_o), .wb_sel_i(sel), .wb_we_i(we), .wb_cyc_i(cyc),
        .wb_stb_i(stb), .wb_ack_o(ack), .wb_err_o(err),
        .irq_sources_i(irq_sources), .irq_o(irq), .irq_vector_o(irq_vector)
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

    task automatic test_case(input string title);
        begin
            $display("");
            $display("-------------------- %-56s", title);
        end
    endtask

    reg [31:0] value;
    initial begin
        rst=1; adr=0; dat_i=0; sel=0; we=0; cyc=0; stb=0; irq_sources=0;
        repeat (4) @(posedge clk); rst=0;

        $display("REPORT-BEGIN: PIC");
        $display("");
        $display("==============================================================================");
        $display("* PROGRAMMABLE INTERRUPT CONTROLLER SIMULATION                               *");
        $display("==============================================================================");

        test_case("CASE 1 - RAW SOURCE AND STICKY PENDING");
        irq_sources = 8'h04;
        repeat (2) @(posedge clk);
        irq_sources = 8'h00;
        wb_read(8'h08, value);
        if (value[7:0] !== 8'h00) $fatal(1, "PIC raw input did not deassert");
        wb_read(8'h00, value);
        if (value[7:0] !== 8'h04) $fatal(1, "PIC pending did not latch");
        if (irq) $fatal(1, "PIC IRQ asserted while source disabled");
        $display("| PASS | source bit2 latched while disabled | pending=0x%02x             |",
                 value[7:0]);

        test_case("CASE 2 - ENABLE MASK AND VECTOR");
        wb_write(8'h04, 32'h0000_0004);
        @(posedge clk);
        if (!irq || irq_vector[7:0] !== 8'h04)
            $fatal(1, "PIC enable/vector mismatch");
        $display("| PASS | enable=0x04 | irq=%0d | vector=0x%02x                           |",
                 irq, irq_vector[7:0]);

        test_case("CASE 3 - W1C CLEAR");
        wb_write(8'h00, 32'h0000_0004);
        @(posedge clk);
        if (irq || irq_vector[7:0] !== 8'h00)
            $fatal(1, "PIC W1C clear failed");
        $display("| PASS | pending bit2 cleared after source deasserted                    |");

        test_case("CASE 4 - SIMULTANEOUS SOURCES");
        wb_write(8'h04, 32'h0000_00a1);
        irq_sources = 8'ha1;
        repeat (2) @(posedge clk);
        irq_sources = 8'h00;
        if (!irq || irq_vector[7:0] !== 8'ha1)
            $fatal(1, "PIC simultaneous source vector mismatch");
        wb_read(8'h00, value);
        if (value[7:0] !== 8'ha1)
            $fatal(1, "PIC simultaneous pending mismatch");
        $display("| PASS | pending bitmap=0x%02x | all enabled sources preserved          |",
                 value[7:0]);

        test_case("CASE 5 - ACTIVE LEVEL REASSERTS");
        wb_write(8'h00, 32'h0000_00a1);
        irq_sources = 8'h01;
        repeat (2) @(posedge clk);
        wb_write(8'h00, 32'h0000_0001);
        repeat (2) @(posedge clk);
        if (!irq || irq_vector[0] !== 1'b1)
            $fatal(1, "PIC active source did not reassert");
        irq_sources = 8'h00;
        wb_write(8'h00, 32'h0000_0001);
        @(posedge clk);
        if (irq) $fatal(1, "PIC final clear failed");
        $display("| PASS | active level source reasserted until peripheral cleared        |");

        $display("==============================================================================");
        $display("* RESULT: PASS - RAW, PENDING, ENABLE, VECTOR AND W1C BEHAVIOR.              *");
        $display("==============================================================================");
        $display("REPORT-END: PIC");
        $display("PASS: PIC raw inputs, sticky pending, enable mask, vector and W1C clear");
        $finish;
    end

endmodule
