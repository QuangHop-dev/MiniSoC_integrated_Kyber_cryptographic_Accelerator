`timescale 1ns/1ps

// Eight logical polynomial slots are packed into one 1024x32 simple dual-port
// memory. The two 16-bit halves preserve the original two-coefficient interface.
module kyber_poly_memory_bank (
    input  wire                    clk,

    input  wire                    rd_en,
    input  wire [2:0]              rd_slot,
    input  wire [6:0]              rd_pair_addr,
    output wire signed [15:0]      rd_c0,
    output wire signed [15:0]      rd_c1,

    input  wire                    wr_en_c0,
    input  wire                    wr_en_c1,
    input  wire [2:0]              wr_slot,
    input  wire [6:0]              wr_pair_addr,
    input  wire signed [15:0]      wr_c0,
    input  wire signed [15:0]      wr_c1
);
    wire [9:0] rd_addr = {rd_slot, rd_pair_addr};
    wire [9:0] wr_addr = {wr_slot, wr_pair_addr};
    reg [31:0] rd_pair;

    (* ram_style = "block" *) reg [31:0] mem [0:1023];

    always @(posedge clk) begin
        if (rd_en)
            rd_pair <= mem[rd_addr];
    end

    always @(posedge clk) begin
        if (wr_en_c0) begin
            mem[wr_addr][7:0] <= wr_c0[7:0];
            mem[wr_addr][15:8] <= wr_c0[15:8];
        end
        if (wr_en_c1) begin
            mem[wr_addr][23:16] <= wr_c1[7:0];
            mem[wr_addr][31:24] <= wr_c1[15:8];
        end
    end

    assign rd_c0 = rd_pair[15:0];
    assign rd_c1 = rd_pair[31:16];
endmodule
