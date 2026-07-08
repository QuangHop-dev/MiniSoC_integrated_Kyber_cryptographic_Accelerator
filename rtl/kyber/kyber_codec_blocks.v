`timescale 1ns/1ps

`ifdef KYBER_CODEC_KEEP_HIERARCHY
`define KYBER_CODEC_HIER (* keep_hierarchy = "yes" *)
`else
`define KYBER_CODEC_HIER
`endif

// -----------------------------------------------------------------------------
// Thesis-shaped Encode/Decode/Compress/Decompress blocks.
//
// The SoC stores coefficients in signed 16-bit RAM words, but the thesis
// diagrams use 12-bit coefficient lanes and 24-bit two-lane datapaths. Keep the
// adapters outside these modules so the hierarchy can be drawn directly from:
//   Encode1, Encode12, Decode1, Decode12
//   Compress_du, Compress_dv, Decompress_du, Decompress_dv
// -----------------------------------------------------------------------------

`KYBER_CODEC_HIER
module kyber_buffer_20to32 (
    input  wire [19:0] din,
    output wire [31:0] dout
);
    assign dout = {12'd0, din};
endmodule


`KYBER_CODEC_HIER
module kyber_buffer_8to32 (
    input  wire [7:0] din,
    output wire [31:0] dout
);
    assign dout = {24'd0, din};
endmodule


`KYBER_CODEC_HIER
module kyber_buffer_32to20 (
    input  wire [31:0] din,
    output wire [19:0] dout
);
    assign dout = din[19:0];
endmodule


`KYBER_CODEC_HIER
module kyber_buffer_32to8 (
    input  wire [31:0] din,
    output wire [7:0] dout
);
    assign dout = din[7:0];
endmodule


`KYBER_CODEC_HIER
module kyber_buffer_2to32 (
    input  wire [1:0] din,
    output wire [31:0] dout
);
    assign dout = {30'd0, din};
endmodule


`KYBER_CODEC_HIER
module kyber_shift_register_buffer_32to2 (
    input  wire [31:0] din,
    output wire [1:0] dout
);
    assign dout = din[1:0];
endmodule


`KYBER_CODEC_HIER
module kyber_compress_divider #(
    parameter integer D = 10
) (
    input  wire [21:0] c,
    output wire [D-1:0] quo
);
    function [39:0] mul_scale_shiftadd;
        input [21:0] x;
        reg [39:0] xs;
        begin
            xs = {18'd0, x};
            mul_scale_shiftadd =
                (xs << 17) + (xs << 14) + (xs << 13) + (xs << 12) +
                (xs << 10) + (xs << 8)  + (xs << 7)  + (xs << 6)  +
                (xs << 5)  + (xs << 4)  + (xs << 2)  + (xs << 1)  + xs;
        end
    endfunction

    wire [39:0] prod = mul_scale_shiftadd(c);
    wire [10:0] q = prod[39:29];

    assign quo = q[D-1:0];
endmodule


`KYBER_CODEC_HIER
module kyber_compress_du (
    input  wire [23:0] din,
    output wire [31:0] dout
);
    wire [21:0] c0_shift_round = ({10'd0, din[11:0]}  << 10) + 22'd1664;
    wire [21:0] c1_shift_round = ({10'd0, din[23:12]} << 10) + 22'd1664;
    wire [9:0]  q0;
    wire [9:0]  q1;
    wire [19:0] compressed_pair;

    kyber_compress_divider #(.D(10)) u_divider_coeff0 (
        .c(c0_shift_round),
        .quo(q0)
    );

    kyber_compress_divider #(.D(10)) u_divider_coeff1 (
        .c(c1_shift_round),
        .quo(q1)
    );

    assign compressed_pair = {q1, q0};

    kyber_buffer_20to32 u_buffer_20to32 (
        .din(compressed_pair),
        .dout(dout)
    );
endmodule


`KYBER_CODEC_HIER
module kyber_compress_dv (
    input  wire [23:0] din,
    output wire [31:0] dout
);
    wire [15:0] c0_shift_round = ({4'd0, din[11:0]}  << 4) + 16'd1664;
    wire [15:0] c1_shift_round = ({4'd0, din[23:12]} << 4) + 16'd1664;
    wire [3:0]  q0;
    wire [3:0]  q1;
    wire [7:0]  compressed_pair;

    kyber_compress_divider #(.D(4)) u_divider_coeff0 (
        .c({6'd0, c0_shift_round}),
        .quo(q0)
    );

    kyber_compress_divider #(.D(4)) u_divider_coeff1 (
        .c({6'd0, c1_shift_round}),
        .quo(q1)
    );

    assign compressed_pair = {q1, q0};

    kyber_buffer_8to32 u_buffer_8to32 (
        .din(compressed_pair),
        .dout(dout)
    );
endmodule


`KYBER_CODEC_HIER
module kyber_multiplier_by_q (
    input  wire [10:0] c,
    output wire [31:0] product
);
    wire [31:0] c_ext = {21'd0, c};

    assign product = (c_ext << 11) + (c_ext << 10) + (c_ext << 8) + c_ext;
endmodule


`KYBER_CODEC_HIER
module kyber_decompress_du (
    input  wire [31:0] din,
    output wire [23:0] dout
);
    wire [19:0] compressed_pair;
    wire [10:0] c0 = compressed_pair[9:0];
    wire [10:0] c1 = compressed_pair[19:10];
    wire [31:0] c0_mul_q;
    wire [31:0] c1_mul_q;
    wire [31:0] c0_round_shift;
    wire [31:0] c1_round_shift;

    kyber_buffer_32to20 u_buffer_32to20 (
        .din(din),
        .dout(compressed_pair)
    );

    kyber_multiplier_by_q u_mul_q_coeff0 (
        .c(c0),
        .product(c0_mul_q)
    );

    kyber_multiplier_by_q u_mul_q_coeff1 (
        .c(c1),
        .product(c1_mul_q)
    );

    assign c0_round_shift = (c0_mul_q + 32'd512) >> 10;
    assign c1_round_shift = (c1_mul_q + 32'd512) >> 10;
    assign dout = {c1_round_shift[11:0], c0_round_shift[11:0]};
endmodule


`KYBER_CODEC_HIER
module kyber_decompress_dv (
    input  wire [31:0] din,
    output wire [23:0] dout
);
    wire [7:0] compressed_pair;
    wire [10:0] c0 = {7'd0, compressed_pair[3:0]};
    wire [10:0] c1 = {7'd0, compressed_pair[7:4]};
    wire [31:0] c0_mul_q;
    wire [31:0] c1_mul_q;
    wire [31:0] c0_round_shift;
    wire [31:0] c1_round_shift;

    kyber_buffer_32to8 u_buffer_32to8 (
        .din(din),
        .dout(compressed_pair)
    );

    kyber_multiplier_by_q u_mul_q_coeff0 (
        .c(c0),
        .product(c0_mul_q)
    );

    kyber_multiplier_by_q u_mul_q_coeff1 (
        .c(c1),
        .product(c1_mul_q)
    );

    assign c0_round_shift = (c0_mul_q + 32'd8) >> 4;
    assign c1_round_shift = (c1_mul_q + 32'd8) >> 4;
    assign dout = {c1_round_shift[11:0], c0_round_shift[11:0]};
endmodule


`KYBER_CODEC_HIER
module kyber_encode1 (
    input  wire [23:0] din,
    output wire [31:0] dout
);
    wire [11:0] coeff0 = din[11:0];
    wire [11:0] coeff1 = din[23:12];
    wire bit0 = (coeff0 >= 12'd832) && (coeff0 <= 12'd2496);
    wire bit1 = (coeff1 >= 12'd832) && (coeff1 <= 12'd2496);

    kyber_buffer_2to32 u_buffer_2to32 (
        .din({bit1, bit0}),
        .dout(dout)
    );
endmodule


`KYBER_CODEC_HIER
module kyber_decode1 (
    input  wire [31:0] din,
    output wire [23:0] dout
);
    wire [1:0] bits;
    wire [11:0] coeff0 = bits[0] ? 12'd1665 : 12'd0;
    wire [11:0] coeff1 = bits[1] ? 12'd1665 : 12'd0;

    kyber_shift_register_buffer_32to2 u_shift_register_buffer (
        .din(din),
        .dout(bits)
    );

    assign dout = {coeff1, coeff0};
endmodule


`KYBER_CODEC_HIER
module kyber_encode12 (
    input  wire [23:0] din,
    output wire [23:0] dout
);
    wire [11:0] coeff0 = din[11:0];
    wire [11:0] coeff1 = din[23:12];

    assign dout = {coeff1[11:4], {coeff1[3:0], coeff0[11:8]}, coeff0[7:0]};
endmodule


`KYBER_CODEC_HIER
module kyber_decode12 (
    input  wire [23:0] din,
    output wire [23:0] dout
);
    assign dout = {{din[23:16], din[15:12]}, {din[11:8], din[7:0]}};
endmodule

`undef KYBER_CODEC_HIER
