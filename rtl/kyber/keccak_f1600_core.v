`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// keccak_f1600_core
// Owns the single Keccak state used by both the sponge and the permutation.
// Absorb and padding use one-hot lane enables so synthesis does not build a
// 25:1 dynamic write mux. Squeeze uses fixed rate-window taps.
// -----------------------------------------------------------------------------

module keccak_f1600_core(
    input  wire          clk,
    input  wire          rst,
    input  wire          start,

    input  wire          state_clear,
    input  wire          state_xof_load,
    input  wire [271:0]  xof_load_data,

    input  wire [16:0]   state_xor_mask,
    input  wire [63:0]   state_xor_data,

    input  wire          state_pad_en,
    input  wire [16:0]   state_pad_mask,
    input  wire [63:0]   state_pad_data,
    input  wire [16:0]   state_pad_last_mask,

    output wire [511:0]  state_low512,
    output wire [511:0]  state_mid512,
    output wire [319:0]  state_high320,

    output reg           done,
    output wire          busy
);

    localparam IDLE    = 2'd0;
    localparam PROCESS = 2'd1;
    localparam FINISH  = 2'd2;

    reg [1:0] state;
    reg [4:0] round_cnt;
    reg  [1599:0] state_reg;
    wire [1599:0] round_next_state;
    reg  [63:0]   rc;

    assign state_low512  = state_reg[511:0];
    assign state_mid512  = state_reg[1023:512];
    assign state_high320 = state_reg[1343:1024];
    assign busy = (state != IDLE);

    keccak_round_function round_inst (
        .in_state (state_reg),
        .rc       (rc),
        .out_state(round_next_state)
    );

    always @(*) begin
        case (round_cnt)
            5'd0:  rc = 64'h0000000000000001;
            5'd1:  rc = 64'h0000000000008082;
            5'd2:  rc = 64'h800000000000808a;
            5'd3:  rc = 64'h8000000080008000;
            5'd4:  rc = 64'h000000000000808b;
            5'd5:  rc = 64'h0000000080000001;
            5'd6:  rc = 64'h8000000080008081;
            5'd7:  rc = 64'h8000000000008009;
            5'd8:  rc = 64'h000000000000008a;
            5'd9:  rc = 64'h0000000000000088;
            5'd10: rc = 64'h0000000080008009;
            5'd11: rc = 64'h000000008000000a;
            5'd12: rc = 64'h000000008000808b;
            5'd13: rc = 64'h800000000000008b;
            5'd14: rc = 64'h8000000000008089;
            5'd15: rc = 64'h8000000000008003;
            5'd16: rc = 64'h8000000000008002;
            5'd17: rc = 64'h8000000000000080;
            5'd18: rc = 64'h000000000000800a;
            5'd19: rc = 64'h800000008000000a;
            5'd20: rc = 64'h8000000080008081;
            5'd21: rc = 64'h8000000000008080;
            5'd22: rc = 64'h0000000080000001;
            5'd23: rc = 64'h8000000080008008;
            default: rc = 64'h0000000000000000;
        endcase
    end

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            round_cnt <= 5'd0;
            done      <= 1'b0;
            state_reg <= 1600'd0;
        end else if (state_clear) begin
            state     <= IDLE;
            round_cnt <= 5'd0;
            done      <= 1'b0;
            state_reg <= 1600'd0;
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    round_cnt <= 5'd0;

                    if (state_xof_load) begin
                        state_reg <= 1600'd0;
                        state_reg[0*64 +: 64] <= xof_load_data[63:0];
                        state_reg[1*64 +: 64] <= xof_load_data[127:64];
                        state_reg[2*64 +: 64] <= xof_load_data[191:128];
                        state_reg[3*64 +: 64] <= xof_load_data[255:192];
                        state_reg[4*64 +: 64] <=
                            {40'd0, 8'h1f, xof_load_data[271:256]};
                        state_reg[20*64 +: 64] <=
                            64'h8000_0000_0000_0000;
                    end else if (|state_xor_mask) begin
                        for (i = 0; i < 17; i = i + 1) begin
                            if (state_xor_mask[i])
                                state_reg[i*64 +: 64] <=
                                    state_reg[i*64 +: 64] ^
                                    state_xor_data;
                        end
                    end else if (state_pad_en) begin
                        for (i = 0; i < 17; i = i + 1) begin
                            if (state_pad_mask[i] ||
                                state_pad_last_mask[i])
                                state_reg[i*64 +: 64] <=
                                    state_reg[i*64 +: 64] ^
                                    (state_pad_mask[i] ?
                                        state_pad_data : 64'd0) ^
                                    (state_pad_last_mask[i] ?
                                        64'h8000_0000_0000_0000 :
                                        64'd0);
                        end
                    end else if (start) begin
                        state <= PROCESS;
                    end
                end

                PROCESS: begin
                    state_reg <= round_next_state;

                    if (round_cnt == 5'd23)
                        state <= FINISH;
                    else
                        round_cnt <= round_cnt + 5'd1;
                end

                FINISH: begin
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
