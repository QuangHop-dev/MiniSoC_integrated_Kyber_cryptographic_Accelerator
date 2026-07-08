`timescale 1ns/1ps

// Stateless two-lane modular arithmetic used directly in the polynomial
// streaming paths. Inputs must be canonical coefficients in [0, q-1].
module kyber_unified_addsub_modq (
    input  wire [23:0] a,
    input  wire [23:0] b,
    input  wire [23:0] c,
    input  wire        subtract,
    input  wire        add_c,
    output wire [23:0] y
);
    function [11:0] reduce_lane;
        input [11:0] a_lane;
        input [11:0] b_lane;
        input [11:0] c_lane;
        input        do_subtract;
        input        do_add_c;
        reg signed [14:0] value;
        begin
            if (do_subtract)
                value = $signed({1'b0, a_lane}) -
                        $signed({1'b0, b_lane});
            else
                value = $signed({1'b0, a_lane}) +
                        $signed({1'b0, b_lane}) +
                        (do_add_c ? $signed({1'b0, c_lane}) : 15'sd0);

            if (value < 15'sd0)
                value = value + 15'sd3329;
            else begin
                if (value >= 15'sd3329)
                    value = value - 15'sd3329;
                if (value >= 15'sd3329)
                    value = value - 15'sd3329;
            end
            reduce_lane = value[11:0];
        end
    endfunction

    assign y[11:0] = reduce_lane(
        a[11:0], b[11:0], c[11:0], subtract, add_c);
    assign y[23:12] = reduce_lane(
        a[23:12], b[23:12], c[23:12], subtract, add_c);
endmodule
