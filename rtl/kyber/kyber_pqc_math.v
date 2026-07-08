`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Pipelined Kyber arithmetic units.
//
// The SoC keeps its existing NTT/PWMA controllers and memory interfaces, while
// these leaf datapaths use:
//   - registered 16x16 LUT multipliers, no DSP inference
//   - pipelined Montgomery reduction from mont_reduce.v
//   - pipelined Barrett reduction from barrett_reduce.v
//   - direct five-product basemul datapath from basemul.v
// -----------------------------------------------------------------------------

module kyber_delay_line #(
    parameter integer WIDTH = 16,
    parameter integer DEPTH = 1
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire signed [WIDTH-1:0] din,
    output wire signed [WIDTH-1:0] dout
);
    reg signed [WIDTH-1:0] data [0:DEPTH-1];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < DEPTH; i = i + 1)
                data[i] <= {WIDTH{1'b0}};
        end else begin
            data[0] <= din;
            for (i = 1; i < DEPTH; i = i + 1)
                data[i] <= data[i-1];
        end
    end

    assign dout = data[DEPTH-1];
endmodule

module kyber_mul16_pipe (
    input  wire clk,
    input  wire signed [15:0] a,
    input  wire signed [15:0] b,
    output reg  signed [31:0] p
);
    (* use_dsp = "no" *) wire signed [31:0] product = a * b;

    always @(posedge clk) begin
        p <= product;
    end
endmodule

module kyber_mul_qinv_pipe (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] din,
    output wire [15:0] dout
);
    wire [7:0] d0, d1, d2, d3, d4, d5, d6, sum;
    reg  [15:0] data_output;

    assign d0   = din[15:8];
    assign d1   = din[7:0];
    assign d2   = {din[6:0], 1'b0};
    assign d3   = {din[3:0], 4'b0};
    assign d4   = {din[2:0], 5'b0};
    assign d5   = {din[1:0], 6'b0};
    assign d6   = {din[0], 7'b0};
    assign sum  = d0 + d1 + d2 + d3 + d4 + d5 + d6;
    assign dout = data_output;

    always @(posedge clk) begin
        if (rst)
            data_output <= 16'h0000;
        else
            data_output <= {sum, din[7:0]};
    end
endmodule

module kyber_mul_q_pipe (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] din,
    output wire [31:0] dout
);
    wire [19:0] d0, d1, d2, d3, sum;
    reg  [31:0] data_output;

    assign d0   = {din[15], din, 3'b000};
    assign d1   = {{2{din[15]}}, din, 2'b00};
    assign d2   = {{4{din[15]}}, din};
    assign d3   = {{16{din[15]}}, din[15:8]};
    assign sum  = d0 + d1 + d2 + d3;
    assign dout = data_output;

    always @(posedge clk) begin
        if (rst)
            data_output <= 32'h00000000;
        else
            data_output <= {{4{sum[19]}}, sum, din[7:0]};
    end
endmodule

module kyber_mul_barrett_v_pipe (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] din,
    output wire [15:0] dout
);
    reg signed [31:0] sum0, sum1, sum2, sum;

    assign dout = {{10{sum[31]}}, sum[31:26]};

    always @(posedge clk) begin
        if (rst) begin
            sum0 <= 32'sd0;
            sum1 <= 32'sd0;
            sum2 <= 32'sd0;
            sum  <= 32'sd0;
        end else begin
            sum0 <= {{2{din[15]}}, din, 14'b0} + {{5{din[15]}}, din, 11'b0} +
                    {{6{din[15]}}, din, 10'b0} + {{7{din[15]}}, din, 9'b0};
            sum1 <= {{9{din[15]}}, din, 7'b0}  + {{11{din[15]}}, din, 5'b0} +
                    {{12{din[15]}}, din, 4'b0} + {{13{din[15]}}, din, 3'b0};
            sum2 <= {{14{din[15]}}, din, 2'b0} + {{15{din[15]}}, din, 1'b0} +
                    {{16{din[15]}}, din};
            sum  <= sum0 + sum1 + sum2;
        end
    end
endmodule

module kyber_montgomery_pipe (
    input  wire        clk,
    input  wire        rst,
    input  wire signed [31:0] din,
    output wire signed [15:0] dout
);
    wire [15:0] p0;
    wire signed [31:0] p1;
    wire signed [31:0] q;
    reg  signed [31:0] diff;

    kyber_mul_qinv_pipe u_qinv (
        .clk(clk), .rst(rst), .din(din), .dout(p0)
    );

    kyber_mul_q_pipe u_q (
        .clk(clk), .rst(rst), .din(p0), .dout(p1)
    );

    kyber_delay_line #(.WIDTH(32), .DEPTH(2)) u_delay (
        .clk(clk), .rst(rst), .din(din), .dout(q)
    );

    assign dout = diff[31:16];

    always @(posedge clk) begin
        if (rst)
            diff <= 32'sd0;
        else
            diff <= q - p1;
    end
endmodule

module kyber_barrett_pipe (
    input  wire        clk,
    input  wire        rst,
    input  wire signed [15:0] din,
    output wire signed [15:0] dout
);
    wire signed [15:0] p0;
    wire signed [15:0] q;
    wire signed [31:0] p1;
    reg  signed [15:0] diff;

    kyber_mul_barrett_v_pipe u_v (
        .clk(clk), .rst(rst), .din(din), .dout(p0)
    );

    kyber_mul_q_pipe u_q (
        .clk(clk), .rst(rst), .din(p0), .dout(p1)
    );

    kyber_delay_line #(.WIDTH(16), .DEPTH(3)) u_delay (
        .clk(clk), .rst(rst), .din(din), .dout(q)
    );

    assign dout = diff;

    always @(posedge clk) begin
        if (rst)
            diff <= 16'sd0;
        else
            diff <= q - $signed(p1[15:0]);
    end
endmodule

module kyber_ntt_butterfly (
    input  wire clk,
    input  wire rst,
    input  wire mode,
    input  wire signed [15:0] a,
    input  wire signed [15:0] b,
    input  wire signed [15:0] zeta,
    output wire signed [15:0] out_a,
    output wire signed [15:0] out_b
);
    wire signed [15:0] sum_a_b = a + b;
    wire signed [15:0] diff_b_a = b - a;
    wire signed [15:0] mult_op1 = (mode == 1'b0) ? b : diff_b_a;
    wire signed [15:0] mult_op2 = zeta;
    wire signed [31:0] prod;
    wire signed [15:0] mont_res;

    kyber_mul16_pipe u_mult (
        .clk(clk), .a(mult_op1), .b(mult_op2), .p(prod)
    );

    kyber_montgomery_pipe u_mont (
        .clk(clk), .rst(rst), .din(prod), .dout(mont_res)
    );

    wire signed [15:0] a_delay;
    wire signed [15:0] sum_delay;
    wire signed [0:0]  mode_delay;

    kyber_delay_line #(.WIDTH(16), .DEPTH(4)) u_a_delay (
        .clk(clk), .rst(rst), .din(a), .dout(a_delay)
    );

    kyber_delay_line #(.WIDTH(16), .DEPTH(4)) u_sum_delay (
        .clk(clk), .rst(rst), .din(sum_a_b), .dout(sum_delay)
    );

    kyber_delay_line #(.WIDTH(1), .DEPTH(4)) u_mode_delay (
        .clk(clk), .rst(rst), .din(mode), .dout(mode_delay)
    );

    wire signed [15:0] raw_a = (mode_delay[0] == 1'b0) ? (a_delay + mont_res) : sum_delay;
    wire signed [15:0] raw_b = (mode_delay[0] == 1'b0) ? (a_delay - mont_res) : mont_res;

    kyber_barrett_pipe u_barrett_a (
        .clk(clk), .rst(rst), .din(raw_a), .dout(out_a)
    );

    kyber_barrett_pipe u_barrett_b (
        .clk(clk), .rst(rst), .din(raw_b), .dout(out_b)
    );
endmodule

module kyber_basemul_pipe #(
    parameter OUTPUT_BARRETT = 1
)(
    input  wire clk,
    input  wire rst,
    input  wire signed [15:0] a0,
    input  wire signed [15:0] a1,
    input  wire signed [15:0] b0,
    input  wire signed [15:0] b1,
    input  wire signed [15:0] zeta,
    output wire signed [15:0] c0,
    output wire signed [15:0] c1
);
    wire signed [31:0] p0, p1, p2, p3, p4;
    wire signed [15:0] zeta_d;
    wire signed [15:0] red0, red1, red2, red3, red4;
    wire signed [15:0] red0_d;
    wire signed [15:0] sum1_d;
    reg  signed [15:0] sum0;
    reg  signed [15:0] sum1;

    kyber_mul16_pipe u_mult_0 (.clk(clk), .a(a0),  .b(b0),   .p(p0));
    kyber_mul16_pipe u_mult_1 (.clk(clk), .a(a1),  .b(b1),   .p(p1));
    kyber_mul16_pipe u_mult_2 (.clk(clk), .a(a0),  .b(b1),   .p(p2));
    kyber_mul16_pipe u_mult_3 (.clk(clk), .a(a1),  .b(b0),   .p(p3));
    kyber_mul16_pipe u_mult_4 (.clk(clk), .a(zeta_d), .b(red1), .p(p4));

    kyber_montgomery_pipe u_mont_0 (.clk(clk), .rst(rst), .din(p0), .dout(red0));
    kyber_montgomery_pipe u_mont_1 (.clk(clk), .rst(rst), .din(p1), .dout(red1));
    kyber_montgomery_pipe u_mont_2 (.clk(clk), .rst(rst), .din(p2), .dout(red2));
    kyber_montgomery_pipe u_mont_3 (.clk(clk), .rst(rst), .din(p3), .dout(red3));
    kyber_montgomery_pipe u_mont_4 (.clk(clk), .rst(rst), .din(p4), .dout(red4));

    kyber_delay_line #(.WIDTH(16), .DEPTH(4)) u_zeta_delay (
        .clk(clk), .rst(rst), .din(zeta), .dout(zeta_d)
    );

    kyber_delay_line #(.WIDTH(16), .DEPTH(4)) u_red0_delay (
        .clk(clk), .rst(rst), .din(red0), .dout(red0_d)
    );

    kyber_delay_line #(.WIDTH(16), .DEPTH(4)) u_sum1_delay (
        .clk(clk), .rst(rst), .din(sum1), .dout(sum1_d)
    );

    always @(posedge clk) begin
        if (rst) begin
            sum0 <= 16'sd0;
            sum1 <= 16'sd0;
        end else begin
            sum0 <= red0_d + red4;
            sum1 <= red2 + red3;
        end
    end

    generate
        if (OUTPUT_BARRETT) begin : gen_output_barrett
            kyber_barrett_pipe u_barrett_c0 (
                .clk(clk), .rst(rst), .din(sum0), .dout(c0)
            );

            kyber_barrett_pipe u_barrett_c1 (
                .clk(clk), .rst(rst), .din(sum1_d), .dout(c1)
            );
        end else begin : gen_raw_output
            assign c0 = sum0;
            assign c1 = sum1_d;
        end
    endgenerate
endmodule
