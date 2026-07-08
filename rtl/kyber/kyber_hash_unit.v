`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// kyber_hash_unit
// Kyber512 RTL source. Comments and unused debug-only code were removed for a
// synthesis-oriented release build.
// -----------------------------------------------------------------------------

module kyber_hash_unit (
    input  wire        clk,
    input  wire        rst,

    input  wire        start,
    input  wire [2:0]  hash_cmd,
    input  wire        prf_eta3,

    input  wire        hash_in_stream_en,
    input  wire        hash_in_valid,
    output wire        hash_in_ready,
    input  wire [63:0] hash_in_data,
    input  wire [3:0]  hash_in_bytes,
    input  wire        hash_in_last,

    input  wire        xof_req_valid,
    input  wire [271:0] xof_req_din,
    output wire        xof_req_ready,
    input  wire        xof_release,
    output wire [63:0] xof_word_data,
    output wire        xof_word_valid,
    input  wire        xof_word_ready,

    output wire [63:0] hash_out_data,
    output wire        hash_out_valid,
    input  wire        hash_out_ready,
    output wire        hash_out_last,
    output wire [4:0]  hash_out_word_idx,

    output wire [511:0] dout,
    output wire          done,
    output wire          busy
);

    localparam CMD_PRF   = 3'd1;
    localparam CMD_H     = 3'd2;
    localparam CMD_G     = 3'd3;
    localparam CMD_RKPRF = 3'd4;

    localparam HASH_H     = 3'd0;
    localparam HASH_G     = 3'd1;
    localparam HASH_PRF2  = 3'd2;
    localparam HASH_PRF3  = 3'd3;
    localparam HASH_RKPRF = 3'd4;

    reg [2:0] hash_mode;

    always @(*) begin
        case (hash_cmd)
            CMD_PRF: begin
                hash_mode = prf_eta3 ? HASH_PRF3 : HASH_PRF2;
            end
            CMD_H: begin
                hash_mode = HASH_H;
            end
            CMD_G: begin
                hash_mode = HASH_G;
            end
            CMD_RKPRF: begin
                hash_mode = HASH_RKPRF;
            end
            default: begin
                hash_mode = HASH_H;
            end
        endcase
    end

    kyber_shake_core u_shake (
        .clk            (clk),
        .rst            (rst),
        .start          (start),
        .hash_mode      (hash_mode),
        .hash_in_stream_en(hash_in_stream_en),
        .hash_in_valid  (hash_in_valid),
        .hash_in_ready  (hash_in_ready),
        .hash_in_data   (hash_in_data),
        .hash_in_bytes  (hash_in_bytes),
        .hash_in_last   (hash_in_last),

        .xof_req_valid  (xof_req_valid),
        .xof_req_din    (xof_req_din),
        .xof_req_ready  (xof_req_ready),
        .xof_release    (xof_release),
        .xof_word_data  (xof_word_data),
        .xof_word_valid (xof_word_valid),
        .xof_word_ready (xof_word_ready),

        .hash_out_data    (hash_out_data),
        .hash_out_valid   (hash_out_valid),
        .hash_out_ready   (hash_out_ready),
        .hash_out_last    (hash_out_last),
        .hash_out_word_idx(hash_out_word_idx),

        .dout           (dout),
        .done           (done),
        .busy           (busy)
    );

endmodule

