`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// kyber_ntt_address_generator
// Kyber512 RTL source. Comments and unused debug-only code were removed for a
// synthesis-oriented release build.
// -----------------------------------------------------------------------------

module kyber_ntt_address_generator (
    input  wire [2:0] stage,
    input  wire       inv_gs_en,
    input  wire [6:0] cnt,
    output reg  [7:0] addr_a,
    output reg  [7:0] addr_b,
    output reg  [6:0] twiddle_addr
);
    reg [7:0] offset, group, len, twiddle_tmp;
    reg [2:0] stage_eff;

    always @(*) begin
        
        
        stage_eff = inv_gs_en ? (3'd6 - stage) : stage;

        len    = 8'd128 >> stage_eff;
        offset = {1'b0, cnt} & (len - 1);
        group  = {1'b0, cnt} >> (4'd7 - stage_eff);
        addr_a = (group << (4'd8 - stage_eff)) + offset;
        addr_b = addr_a + len;

        if (!inv_gs_en)
            twiddle_tmp = (8'd1 << stage) + group;
        else
            twiddle_tmp = ((8'd1 << (stage_eff + 3'd1)) - 8'd1) - group;

        twiddle_addr = twiddle_tmp[6:0];
    end
endmodule
