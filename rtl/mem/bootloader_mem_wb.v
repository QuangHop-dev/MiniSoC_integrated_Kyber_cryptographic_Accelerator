`timescale 1ns/1ps

// Bootloader memory for the UART-load flow.
//
// Address layout inside the implemented BOOT memory:
//   0x0000_0000..ROM_BYTES-1      read-only bootloader ROM
//   ROM_BYTES..BOOT_BYTES-1       writable IMEM for uploaded programs
//
// The CPU resets into the ROM. The bootloader can load a payload either into
// this IMEM window or into SRAM, then jump to the payload entry point.
module bootloader_mem_wb #(
    parameter integer BOOT_BYTES = 32*1024,
    parameter integer ROM_BYTES  = 16*1024,
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
    localparam integer ROM_WORDS  = ROM_BYTES / 4;
    localparam integer IMEM_BYTES = BOOT_BYTES - ROM_BYTES;
    localparam integer IMEM_WORDS = (IMEM_BYTES > 0) ? (IMEM_BYTES / 4) : 1;

    (* rom_style = "block" *) reg [31:0] rom [0:ROM_WORDS-1];
    (* ram_style = "block" *) reg [7:0] imem_b0 [0:IMEM_WORDS-1];
    (* ram_style = "block" *) reg [7:0] imem_b1 [0:IMEM_WORDS-1];
    (* ram_style = "block" *) reg [7:0] imem_b2 [0:IMEM_WORDS-1];
    (* ram_style = "block" *) reg [7:0] imem_b3 [0:IMEM_WORDS-1];

    wire [31:0] word_addr = wb_adr_i[31:2];
    wire in_rom  = (wb_adr_i < ROM_BYTES);
    wire in_imem = (wb_adr_i >= ROM_BYTES) && (wb_adr_i < BOOT_BYTES);
    wire [31:0] imem_word_addr = word_addr - ROM_WORDS;

    reg        req_valid;
    reg        req_err;
    reg        req_rom;
    reg        req_imem;
    reg [31:0] rom_rdata;
    reg [31:0] imem_rdata;

    wire wb_fire = wb_cyc_i && wb_stb_i && !wb_ack_o && !req_valid;

    integer k;
    initial begin
        for (k = 0; k < ROM_WORDS; k = k + 1)
            rom[k] = 32'h0000_0013; // RISC-V NOP
        for (k = 0; k < IMEM_WORDS; k = k + 1) begin
            imem_b0[k] = 8'h13; // RISC-V NOP
            imem_b1[k] = 8'h00;
            imem_b2[k] = 8'h00;
            imem_b3[k] = 8'h00;
        end
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, rom);
    end

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;
            wb_dat_o <= 32'd0;
            req_valid <= 1'b0;
            req_err <= 1'b0;
            req_rom <= 1'b0;
            req_imem <= 1'b0;
            rom_rdata <= 32'd0;
            imem_rdata <= 32'd0;
        end else begin
            wb_ack_o <= req_valid;
            wb_err_o <= req_valid && req_err;
            if (req_valid) begin
                if (req_rom)
                    wb_dat_o <= rom_rdata;
                else if (req_imem)
                    wb_dat_o <= imem_rdata;
                else
                    wb_dat_o <= 32'd0;
            end
            req_valid <= 1'b0;
            req_err <= 1'b0;
            req_rom <= 1'b0;
            req_imem <= 1'b0;

            if (wb_fire) begin
                req_valid <= 1'b1;
                req_rom <= in_rom;
                req_imem <= in_imem && (imem_word_addr < IMEM_WORDS);
                req_err <= (in_rom && wb_we_i) ||
                           (!in_rom && !(in_imem && (imem_word_addr < IMEM_WORDS)));
                if (in_rom) begin
                    rom_rdata <= rom[word_addr];
                    imem_rdata <= 32'd0;
                end else if (in_imem && (imem_word_addr < IMEM_WORDS)) begin
                    imem_rdata <= {imem_b3[imem_word_addr], imem_b2[imem_word_addr],
                                   imem_b1[imem_word_addr], imem_b0[imem_word_addr]};
                    rom_rdata <= 32'd0;
                    if (wb_we_i) begin
                        if (wb_sel_i[0]) imem_b0[imem_word_addr] <= wb_dat_i[7:0];
                        if (wb_sel_i[1]) imem_b1[imem_word_addr] <= wb_dat_i[15:8];
                        if (wb_sel_i[2]) imem_b2[imem_word_addr] <= wb_dat_i[23:16];
                        if (wb_sel_i[3]) imem_b3[imem_word_addr] <= wb_dat_i[31:24];
                    end
                end else begin
                    rom_rdata <= 32'd0;
                    imem_rdata <= 32'd0;
                end
            end
        end
    end
endmodule
