`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// keccak_sponge_core
// Control-only sponge wrapper. The permutation core owns the only 1600-bit
// state; input, padding and output streaming operate directly on 64-bit lanes.
// -----------------------------------------------------------------------------

module keccak_sponge_core(
    input  wire clk,
    input  wire rst,

    input  wire          start,
    input  wire [2:0]    hash_mode,

    input  wire          in_valid,
    output wire          in_ready,
    input  wire [63:0]   in_data,
    input  wire [3:0]    in_bytes,
    input  wire          in_last,

    input  wire          xof_req_valid,
    input  wire [271:0]  xof_req_din,
    output wire          xof_req_ready,
    input  wire          xof_release,

    output reg  [63:0]   xof_word_data,
    output reg           xof_word_valid,
    input  wire          xof_word_ready,

    output reg  [63:0]   hash_out_data,
    output reg           hash_out_valid,
    input  wire          hash_out_ready,
    output reg           hash_out_last,
    output reg  [4:0]    hash_out_word_idx,

    output wire [511:0]  dout,
    output reg           done,
    output wire          busy
);

    localparam IDLE              = 5'd0;
    localparam ABSORB_STREAM     = 5'd1;
    localparam ABSORB_BUF        = 5'd2;
    localparam PERMUTE_MORE_GO   = 5'd3;
    localparam PERMUTE_MORE_WAIT = 5'd4;
    localparam PADDING           = 5'd5;
    localparam ABSORB_FINAL      = 5'd6;
    localparam PERMUTE_FIN_GO    = 5'd7;
    localparam PERMUTE_FIN_WAIT  = 5'd8;
    localparam SQUEEZE1          = 5'd9;
    localparam HASH_STREAM2_GO   = 5'd10;
    localparam XOF_PERMUTE_GO    = 5'd12;
    localparam XOF_PERMUTE_WAIT  = 5'd13;
    localparam XOF_WORD_OUT      = 5'd14;
    localparam XOF_WAIT_NEXT     = 5'd15;
    localparam HASH_STREAM1      = 5'd16;
    localparam HASH_STREAM2P     = 5'd17;
    localparam HASH_STREAM2      = 5'd18;

    localparam HASH_H     = 3'd0;
    localparam HASH_G     = 3'd1;
    localparam HASH_PRF2  = 3'd2;
    localparam HASH_PRF3  = 3'd3;
    localparam HASH_RKPRF = 3'd4;

    reg [4:0] state;
    reg [7:0] rate_byte_cnt;
    reg       final_full_block;
    reg [2:0] saved_hash_mode;
    reg [4:0] xof_word_idx;
    reg [4:0] f_state_word_idx;
    reg [63:0] f_state_word;

    wire       f_done;
    wire [511:0] f_state_low512;
    wire [511:0] f_state_mid512;
    wire [319:0] f_state_high320;

    wire saved_is_g = (saved_hash_mode == HASH_G);
    wire saved_is_sha3 = (saved_hash_mode == HASH_H) ||
                         (saved_hash_mode == HASH_G);
    wire prf_eta2_stream = (saved_hash_mode == HASH_PRF2);
    wire prf_eta3_stream = (saved_hash_mode == HASH_PRF3);

    wire [7:0] saved_rate_bytes = saved_is_g ? 8'd72 : 8'd136;
    wire [7:0] in_nbytes = (in_bytes == 4'd0) ? 8'd8 :
                           {4'd0, in_bytes};
    wire [8:0] rate_byte_cnt_next =
        {1'b0, rate_byte_cnt} + {1'b0, in_nbytes};
    wire in_nbytes_valid = (in_nbytes != 8'd0) && (in_nbytes <= 8'd8);
    wire in_word_granular = (in_nbytes == 8'd8) || in_last;
    wire in_fits = in_nbytes_valid &&
                   (rate_byte_cnt_next <= {1'b0, saved_rate_bytes});
    wire [4:0] rate_word_idx = rate_byte_cnt[7:3];
    wire [16:0] rate_lane_mask =
        17'h00001 << rate_word_idx;
    wire [63:0] in_byte_mask =
        (in_nbytes == 8'd8) ? 64'hffff_ffff_ffff_ffff :
        (64'hffff_ffff_ffff_ffff >> ((8'd8 - in_nbytes) * 8));
    wire [63:0] in_masked_data = in_data & in_byte_mask;

    wire [16:0] pad_lane_mask =
        17'h00001 << rate_byte_cnt[7:3];
    wire [2:0] pad_byte_idx = rate_byte_cnt[2:0];
    wire [16:0] rate_last_lane_mask =
        saved_is_g ? 17'h00100 : 17'h10000;
    wire [63:0] domain_pad_word =
        (saved_is_sha3 ? 64'h06 : 64'h1f) <<
        ({3'd0, pad_byte_idx} * 8);

    assign busy = (state != IDLE);
    assign dout = f_state_low512;
    assign in_ready = (state == ABSORB_STREAM) &&
                      (rate_byte_cnt[2:0] == 3'd0) &&
                      (rate_byte_cnt < saved_rate_bytes) &&
                      (!in_valid || (in_fits && in_word_granular));

    assign xof_req_ready = (state == IDLE) || (state == XOF_WORD_OUT) ||
                           (state == XOF_WAIT_NEXT);

    wire accept_word = in_valid && in_ready;
    wire accept_xof = !xof_release && xof_req_valid && xof_req_ready;
    wire accept_hash_start = !xof_release && !accept_xof &&
                             (state == IDLE) && start;

    wire f_state_clear = xof_release || accept_hash_start;
    wire f_state_xof_load = accept_xof;
    wire [16:0] f_state_xor_mask =
        (!xof_release && !accept_xof && accept_word) ?
        rate_lane_mask : 17'd0;
    wire f_state_pad_en = !xof_release && !accept_xof &&
                          (state == PADDING);
    wire f_start = !xof_release && !accept_xof &&
                   ((state == PERMUTE_MORE_GO) ||
                    (state == PERMUTE_FIN_GO) ||
                    (state == XOF_PERMUTE_GO) ||
                    (state == HASH_STREAM2_GO));

    function [63:0] select_word8;
        input [511:0] words;
        input [2:0] index;
        begin
            case (index)
                3'd0: select_word8 = words[0*64 +: 64];
                3'd1: select_word8 = words[1*64 +: 64];
                3'd2: select_word8 = words[2*64 +: 64];
                3'd3: select_word8 = words[3*64 +: 64];
                3'd4: select_word8 = words[4*64 +: 64];
                3'd5: select_word8 = words[5*64 +: 64];
                3'd6: select_word8 = words[6*64 +: 64];
                default: select_word8 = words[7*64 +: 64];
            endcase
        end
    endfunction

    function [63:0] select_word5;
        input [319:0] words;
        input [2:0] index;
        begin
            case (index)
                3'd0: select_word5 = words[0*64 +: 64];
                3'd1: select_word5 = words[1*64 +: 64];
                3'd2: select_word5 = words[2*64 +: 64];
                3'd3: select_word5 = words[3*64 +: 64];
                default: select_word5 = words[4*64 +: 64];
            endcase
        end
    endfunction

    always @(*) begin
        f_state_word_idx = 5'd0;
        case (state)
            HASH_STREAM1:
                f_state_word_idx = hash_out_word_idx + 5'd1;
            HASH_STREAM2:
                f_state_word_idx = hash_out_word_idx - 5'd16;
            XOF_WORD_OUT:
                f_state_word_idx = xof_word_idx + 5'd1;
            default:
                f_state_word_idx = 5'd0;
        endcase

        case (f_state_word_idx[4:3])
            2'd0:
                f_state_word =
                    select_word8(f_state_low512,
                                 f_state_word_idx[2:0]);
            2'd1:
                f_state_word =
                    select_word8(f_state_mid512,
                                 f_state_word_idx[2:0]);
            default:
                f_state_word =
                    select_word5(f_state_high320,
                                 f_state_word_idx[2:0]);
        endcase
    end

    keccak_f1600_core f_inst(
        .clk                (clk),
        .rst                (rst),
        .start              (f_start),
        .state_clear        (f_state_clear),
        .state_xof_load     (f_state_xof_load),
        .xof_load_data      (xof_req_din),
        .state_xor_mask     (f_state_xor_mask),
        .state_xor_data     (in_masked_data),
        .state_pad_en       (f_state_pad_en),
        .state_pad_mask     (pad_lane_mask),
        .state_pad_data     (domain_pad_word),
        .state_pad_last_mask(rate_last_lane_mask),
        .state_low512       (f_state_low512),
        .state_mid512       (f_state_mid512),
        .state_high320      (f_state_high320),
        .done               (f_done),
        .busy               ()
    );

    always @(posedge clk) begin
        if (rst) begin
            state             <= IDLE;
            rate_byte_cnt     <= 8'd0;
            final_full_block  <= 1'b0;
            saved_hash_mode   <= HASH_H;
            done              <= 1'b0;
            xof_word_idx      <= 5'd0;
            xof_word_data     <= 64'd0;
            xof_word_valid    <= 1'b0;
            hash_out_data     <= 64'd0;
            hash_out_valid    <= 1'b0;
            hash_out_last     <= 1'b0;
            hash_out_word_idx <= 5'd0;
        end else begin
            done <= 1'b0;

            if (xof_release) begin
                xof_word_valid    <= 1'b0;
                xof_word_idx      <= 5'd0;
                hash_out_valid    <= 1'b0;
                hash_out_last     <= 1'b0;
                rate_byte_cnt     <= 8'd0;
                final_full_block  <= 1'b0;
                state             <= IDLE;
            end else if (accept_xof) begin
                xof_word_valid    <= 1'b0;
                xof_word_idx      <= 5'd0;
                hash_out_valid    <= 1'b0;
                hash_out_last     <= 1'b0;
                rate_byte_cnt     <= 8'd0;
                final_full_block  <= 1'b0;
                state             <= XOF_PERMUTE_GO;
            end else begin
                case (state)
                    IDLE: begin
                        if (start) begin
                            rate_byte_cnt     <= 8'd0;
                            final_full_block  <= 1'b0;
                            saved_hash_mode   <= hash_mode;
                            hash_out_valid    <= 1'b0;
                            hash_out_last     <= 1'b0;
                            hash_out_word_idx <= 5'd0;
                            state             <= ABSORB_STREAM;
                        end
                    end

                    ABSORB_STREAM: begin
                        if (accept_word) begin
                            rate_byte_cnt <= rate_byte_cnt_next[7:0];

                            if (in_last) begin
                                if (rate_byte_cnt_next[7:0] ==
                                    saved_rate_bytes) begin
                                    final_full_block <= 1'b1;
                                    state <= ABSORB_BUF;
                                end else begin
                                    state <= PADDING;
                                end
                            end else if (rate_byte_cnt_next[7:0] ==
                                         saved_rate_bytes) begin
                                state <= ABSORB_BUF;
                            end
                        end
                    end

                    ABSORB_BUF:
                        state <= PERMUTE_MORE_GO;

                    PERMUTE_MORE_GO:
                        state <= PERMUTE_MORE_WAIT;

                    PERMUTE_MORE_WAIT: begin
                        if (f_done) begin
                            rate_byte_cnt <= 8'd0;
                            if (final_full_block) begin
                                final_full_block <= 1'b0;
                                state <= PADDING;
                            end else begin
                                state <= ABSORB_STREAM;
                            end
                        end
                    end

                    PADDING:
                        state <= ABSORB_FINAL;

                    ABSORB_FINAL:
                        state <= PERMUTE_FIN_GO;

                    PERMUTE_FIN_GO:
                        state <= PERMUTE_FIN_WAIT;

                    PERMUTE_FIN_WAIT: begin
                        if (f_done)
                            state <= SQUEEZE1;
                    end

                    SQUEEZE1: begin
                        if (prf_eta2_stream || prf_eta3_stream) begin
                            hash_out_word_idx <= 5'd0;
                            hash_out_data     <= f_state_word;
                            hash_out_valid    <= 1'b1;
                            hash_out_last     <= 1'b0;
                            state             <= HASH_STREAM1;
                        end else begin
                            done  <= 1'b1;
                            state <= IDLE;
                        end
                    end

                    HASH_STREAM1: begin
                        if (hash_out_valid && hash_out_ready) begin
                            if (prf_eta2_stream) begin
                                if (hash_out_word_idx == 5'd15) begin
                                    hash_out_valid <= 1'b0;
                                    hash_out_last  <= 1'b0;
                                    done           <= 1'b1;
                                    state          <= IDLE;
                                end else begin
                                    hash_out_word_idx <=
                                        hash_out_word_idx + 5'd1;
                                    hash_out_data <= f_state_word;
                                    hash_out_last <=
                                        (hash_out_word_idx == 5'd14);
                                end
                            end else if (hash_out_word_idx == 5'd16) begin
                                hash_out_valid <= 1'b0;
                                hash_out_last  <= 1'b0;
                                state          <= HASH_STREAM2_GO;
                            end else begin
                                hash_out_word_idx <=
                                    hash_out_word_idx + 5'd1;
                                hash_out_data <= f_state_word;
                                hash_out_last <= 1'b0;
                            end
                        end
                    end

                    HASH_STREAM2_GO:
                        state <= HASH_STREAM2P;

                    HASH_STREAM2P: begin
                        if (f_done) begin
                            hash_out_word_idx <= 5'd17;
                            hash_out_data     <= f_state_word;
                            hash_out_valid    <= 1'b1;
                            hash_out_last     <= 1'b0;
                            state             <= HASH_STREAM2;
                        end
                    end

                    HASH_STREAM2: begin
                        if (hash_out_valid && hash_out_ready) begin
                            if (hash_out_word_idx == 5'd23) begin
                                hash_out_valid <= 1'b0;
                                hash_out_last  <= 1'b0;
                                done           <= 1'b1;
                                state          <= IDLE;
                            end else begin
                                hash_out_word_idx <=
                                    hash_out_word_idx + 5'd1;
                                hash_out_data <= f_state_word;
                                hash_out_last <=
                                    (hash_out_word_idx == 5'd22);
                            end
                        end
                    end

                    XOF_PERMUTE_GO:
                        state <= XOF_PERMUTE_WAIT;

                    XOF_PERMUTE_WAIT: begin
                        if (f_done) begin
                            xof_word_idx   <= 5'd0;
                            xof_word_data  <= f_state_word;
                            xof_word_valid <= 1'b1;
                            state          <= XOF_WORD_OUT;
                        end
                    end

                    XOF_WORD_OUT: begin
                        if (xof_word_valid && xof_word_ready) begin
                            if (xof_word_idx == 5'd20) begin
                                xof_word_valid <= 1'b0;
                                xof_word_idx   <= 5'd0;
                                state          <= XOF_WAIT_NEXT;
                            end else begin
                                xof_word_idx   <= xof_word_idx + 5'd1;
                                xof_word_data  <= f_state_word;
                                xof_word_valid <= 1'b1;
                            end
                        end
                    end

                    XOF_WAIT_NEXT: begin
                        if (xof_word_ready)
                            state <= XOF_PERMUTE_GO;
                    end

                    default: state <= IDLE;
                endcase
            end
        end
    end

endmodule
