`timescale 1ns/1ps

module boot_rom_wb #(
    parameter integer ROM_BYTES = 16*1024,
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
    localparam integer WORDS = ROM_BYTES / 4;

    (* rom_style = "block" *) reg [31:0] rom [0:WORDS-1];
    wire [31:0] word_addr = wb_adr_i[31:2];

    integer k;
    initial begin
        for (k = 0; k < WORDS; k = k + 1)
            rom[k] = 32'h0000_0013; // RISC-V NOP
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, rom);
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
                if (wb_we_i || word_addr >= WORDS) begin
                    wb_err_o <= 1'b1;
                    wb_dat_o <= 32'd0;
                end else begin
                    wb_dat_o <= rom[word_addr];
                end
            end
        end
    end
endmodule
