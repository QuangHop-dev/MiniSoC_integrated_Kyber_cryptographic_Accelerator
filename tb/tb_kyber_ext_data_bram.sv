`timescale 1ns/1ps

module tb_kyber_ext_data_bram;
    reg clk;
    reg wb_en;
    reg wb_we;
    reg [31:0] wb_addr;
    reg [31:0] wb_wdata;
    reg [3:0] wb_sel;
    wire [31:0] wb_rdata;
    reg core_re;
    reg core_we;
    reg [31:0] core_addr;
    reg [63:0] core_wdata;
    reg [7:0] core_wstrb;
    wire [63:0] core_rdata;

    kyber_ext_data_bram dut (
        .clk(clk),
        .wb_en(wb_en),
        .wb_we(wb_we),
        .wb_addr(wb_addr),
        .wb_wdata(wb_wdata),
        .wb_sel(wb_sel),
        .wb_rdata(wb_rdata),
        .core_re(core_re),
        .core_we(core_we),
        .core_addr(core_addr),
        .core_wdata(core_wdata),
        .core_wstrb(core_wstrb),
        .core_rdata(core_rdata)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        wb_en = 1'b0;
        wb_we = 1'b0;
        wb_addr = 32'd0;
        wb_wdata = 32'd0;
        wb_sel = 4'd0;
        core_re = 1'b0;
        core_we = 1'b0;
        core_addr = 32'd0;
        core_wdata = 64'd0;
        core_wstrb = 8'd0;

        repeat (2) @(posedge clk);

        core_addr = 32'd0;
        core_wdata = 64'h0807_0605_0403_0201;
        core_wstrb = 8'hff;
        core_we = 1'b1;
        @(negedge clk);
        core_addr = 32'd8;
        core_wdata = 64'h1817_1615_1413_1211;
        @(negedge clk);
        core_we = 1'b0;

        core_addr = 32'd0;
        core_re = 1'b1;
        @(negedge clk);
        core_re = 1'b0;
        #1;
        if (core_rdata !== 64'h0807_0605_0403_0201)
            $fatal(1, "core read row0 got %016x", core_rdata);

        core_addr = 32'd8;
        core_re = 1'b1;
        @(negedge clk);
        core_re = 1'b0;
        #1;
        if (core_rdata !== 64'h1817_1615_1413_1211)
            $fatal(1, "core read row1 got %016x", core_rdata);

        wb_addr = 32'd8;
        wb_en = 1'b1;
        wb_we = 1'b0;
        wb_sel = 4'hf;
        @(posedge clk);
        wb_en = 1'b0;
        #1;
        if (wb_rdata !== 32'h1413_1211)
            $fatal(1, "wb read row1 got %08x", wb_rdata);

        $display("PASS: kyber_ext_data_bram core/wb reads");
        $finish;
    end
endmodule
