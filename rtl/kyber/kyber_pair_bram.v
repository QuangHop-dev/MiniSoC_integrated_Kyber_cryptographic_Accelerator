`timescale 1ns/1ps

module kyber_pair_sdp_bram #(
    parameter integer WIDTH = 32,
    parameter integer ADDR_W = 8,
    parameter integer DEPTH = 256
) (
    input  wire                   clk,
    input  wire [ADDR_W-1:0]      rd_addr,
    output reg  [WIDTH-1:0]       rd_data,
    input  wire                   wr_en,
    input  wire [ADDR_W-1:0]      wr_addr,
    input  wire [WIDTH-1:0]       wr_data
);
    (* ram_style = "block" *) reg [WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk)
        rd_data <= mem[rd_addr];

    always @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end
endmodule

module kyber_pair_sdp_lutram #(
    parameter integer WIDTH = 32,
    parameter integer ADDR_W = 8,
    parameter integer DEPTH = 256
) (
    input  wire                   clk,
    input  wire [ADDR_W-1:0]      rd_addr,
    output reg  [WIDTH-1:0]       rd_data,
    input  wire                   wr_en,
    input  wire [ADDR_W-1:0]      wr_addr,
    input  wire [WIDTH-1:0]       wr_data
);
    (* ram_style = "distributed" *) reg [WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk)
        rd_data <= mem[rd_addr];

    always @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end
endmodule
