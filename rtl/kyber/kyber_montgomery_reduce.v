`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// kyber_montgomery_reduce
// Kyber512 RTL source. Comments and unused debug-only code were removed for a
// synthesis-oriented release build.
// -----------------------------------------------------------------------------

module kyber_montgomery_reduce (
    input  wire signed [31:0] a,    
    output wire signed [15:0] t     
);

    
    
    
    localparam signed [15:0] KYBER_Q    = 16'd3329;
    localparam signed [15:0] KYBER_QINV = -16'd3327; 

    function signed [31:0] mul_qinv_shiftadd;
        input signed [31:0] x;
        reg signed [31:0] xp;
        begin
            xp = (x <<< 11) + (x <<< 10) +
                 (x <<< 7)  + (x <<< 6)  + (x <<< 5) +
                 (x <<< 4)  + (x <<< 3)  + (x <<< 2) +
                 (x <<< 1)  + x;
            mul_qinv_shiftadd = -xp;
        end
    endfunction

    function signed [31:0] mul_q_shiftadd_s16;
        input signed [15:0] x;
        reg signed [31:0] xs;
        begin
            xs = {{16{x[15]}}, x};
            mul_q_shiftadd_s16 = (xs <<< 11) + (xs <<< 10) + (xs <<< 8) + xs;
        end
    endfunction

    wire signed [15:0] u;
    wire signed [31:0] t_temp;
    wire signed [31:0] res_sub;
    wire signed [31:0] u_full;   
    wire signed [31:0] t_shift;  

    
    assign u_full = mul_qinv_shiftadd(a);
    assign u = u_full[15:0];

    
    assign t_temp = mul_q_shiftadd_s16(u);

    
    assign res_sub = a - t_temp;

    
    
    assign t_shift = res_sub >>> 16;
    assign t = t_shift[15:0];

endmodule
