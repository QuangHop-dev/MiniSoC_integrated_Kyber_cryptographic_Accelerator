`timescale 1ns/1ps

module sram_wb #(
    parameter integer SRAM_BYTES = 16*1024,
    parameter INIT_FILE = ""
)(
    input  wire        wb_clk_i,
    input  wire        wb_rst_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    input  wire [3:0]  wb_sel_i,
    input  wire        wb_we_i,
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    output reg         wb_ack_o,
    output reg         wb_err_o
);
    localparam integer WORDS = SRAM_BYTES / 4;

    (* ram_style = "block", ram_decomp = "power" *) reg [31:0] ram [0:WORDS-1];
    wire [31:0] word_addr = wb_adr_i[31:2];

    integer k;
    initial begin
        for (k = 0; k < WORDS; k = k + 1)
            ram[k] = 32'd0;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, ram);
    end

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;
            wb_dat_o <= 32'd0;
        end else begin
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;
            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                if (word_addr >= WORDS) begin
                    wb_err_o <= 1'b1;
                    wb_dat_o <= 32'd0;
                end else begin
                    wb_dat_o <= ram[word_addr];
                    if (wb_we_i) begin
                        if (wb_sel_i[0]) ram[word_addr][7:0]   <= wb_dat_i[7:0];
                        if (wb_sel_i[1]) ram[word_addr][15:8]  <= wb_dat_i[15:8];
                        if (wb_sel_i[2]) ram[word_addr][23:16] <= wb_dat_i[23:16];
                        if (wb_sel_i[3]) ram[word_addr][31:24] <= wb_dat_i[31:24];
                    end
                end
            end
        end
    end
endmodule
