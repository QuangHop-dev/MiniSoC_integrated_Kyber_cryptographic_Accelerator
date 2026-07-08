`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// kyber512_ct_unpack_engine
// Thesis-shaped Kyber-512 ciphertext unpacker.
//
// Datapath:
//   aligned 64-bit CT reader -> bit stream buffer -> Decompress_du/dv
//   (one 2-lane block) -> two coefficient writes.
// -----------------------------------------------------------------------------
module kyber512_ct_unpack_engine (
    input  wire clk,
    input  wire rst,
    input  wire start,

    // 64-bit byte-addressed synchronous CT reader.
    output reg  [10:0] ct_wide_raddr,
    input  wire [63:0] ct_wide_dout,

    // One polynomial-pair write per cycle to the shared memory bank.
    output reg         pair_we,
    output reg  [2:0]  pair_slot,
    output reg  [6:0]  pair_addr,
    output reg  signed [15:0] pair_c0,
    output reg  signed [15:0] pair_c1,

    output reg done
);
    localparam S_IDLE  = 3'd0;
    localparam S_U_RUN = 3'd1;
    localparam S_V_RUN = 3'd2;
    localparam S_DONE  = 3'd3;

    localparam [8:0] U_PAIRS = 9'd256;
    localparam [8:0] V_PAIRS = 9'd128;

    localparam [10:0] CT_U_BASE = 11'd0;
    localparam [10:0] CT_V_BASE = 11'd640;
    localparam [10:0] CT_END    = 11'd768;
    reg [2:0] state;
    reg [8:0] u_pair;
    reg [8:0] v_pair;

    reg [127:0] bit_buf;
    reg [7:0]   bit_count;
    reg [10:0]  read_addr;
    reg         rd_v0;
    reg         rd_v1;

    wire [127:0] appended_buf = bit_buf | ({64'd0, ct_wide_dout} << bit_count);
    wire [127:0] stream_buf   = rd_v1 ? appended_buf : bit_buf;
    wire [7:0]   stream_count = bit_count + (rd_v1 ? 8'd64 : 8'd0);

    wire [31:0] u_decompress_word = {12'd0, stream_buf[19:0]};
    wire [31:0] v_decompress_word = {24'd0, stream_buf[7:0]};
    wire [23:0] u_coeff_pair12;
    wire [23:0] v_coeff_pair12;

    kyber_decompress_du u_decompress_du (
        .din(u_decompress_word),
        .dout(u_coeff_pair12)
    );

    kyber_decompress_dv u_decompress_dv (
        .din(v_decompress_word),
        .dout(v_coeff_pair12)
    );

    wire [2:0] u_slot = 3'd4 + u_pair[7];

    task issue_ct_word;
        input [10:0] end_addr;
        begin
            if (!rd_v0 && (read_addr < end_addr)) begin
                ct_wide_raddr <= read_addr;
                read_addr <= read_addr + 11'd8;
                rd_v0 <= 1'b1;
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            u_pair <= 9'd0;
            v_pair <= 9'd0;
            ct_wide_raddr <= 11'd0;
            pair_we <= 1'b0;
            pair_slot <= 3'd0;
            pair_addr <= 7'd0;
            pair_c0 <= 16'sd0;
            pair_c1 <= 16'sd0;
            done <= 1'b0;
            bit_buf <= 128'd0;
            bit_count <= 8'd0;
            read_addr <= 11'd0;
            rd_v0 <= 1'b0;
            rd_v1 <= 1'b0;
        end else begin
            pair_we <= 1'b0;
            done <= 1'b0;
            rd_v1 <= rd_v0;
            rd_v0 <= 1'b0;

            if (rd_v1) begin
                bit_buf <= stream_buf;
                bit_count <= stream_count;
            end

            case (state)
                S_IDLE: begin
                    u_pair <= 9'd0;
                    v_pair <= 9'd0;
                    bit_buf <= 128'd0;
                    bit_count <= 8'd0;
                    read_addr <= CT_U_BASE + 11'd8;
                    rd_v0 <= 1'b0;
                    rd_v1 <= 1'b0;
                    if (start) begin
                        // Prime the first aligned U word.
                        ct_wide_raddr <= CT_U_BASE;
                        rd_v0 <= 1'b1;
                        state <= S_U_RUN;
                    end
                end

                S_U_RUN: begin
                    if (stream_count < 8'd20) begin
                        bit_buf <= stream_buf;
                        bit_count <= stream_count;
                        issue_ct_word(CT_V_BASE);
                    end else begin
                        pair_we   <= 1'b1;
                        pair_slot <= u_slot;
                        pair_addr <= u_pair[6:0];
                        pair_c0   <= $signed({4'd0, u_coeff_pair12[11:0]});
                        pair_c1   <= $signed({4'd0, u_coeff_pair12[23:12]});

                        bit_buf <= stream_buf >> 20;
                        bit_count <= stream_count - 8'd20;

                        if ((stream_count - 8'd20) <= 8'd64)
                            issue_ct_word(CT_V_BASE);

                        if (u_pair + 9'd1 == U_PAIRS) begin
                            v_pair <= 9'd0;
                            bit_buf <= 128'd0;
                            bit_count <= 8'd0;
                            read_addr <= CT_V_BASE + 11'd8;
                            ct_wide_raddr <= CT_V_BASE;
                            rd_v0 <= 1'b1;
                            rd_v1 <= 1'b0;
                            state <= S_V_RUN;
                        end else begin
                            u_pair <= u_pair + 9'd1;
                        end
                    end
                end

                S_V_RUN: begin
                    if (stream_count < 8'd8) begin
                        bit_buf <= stream_buf;
                        bit_count <= stream_count;
                        issue_ct_word(CT_END);
                    end else begin
                        pair_we   <= 1'b1;
                        pair_slot <= 3'd6;
                        pair_addr <= v_pair[6:0];
                        pair_c0   <= $signed({4'd0, v_coeff_pair12[11:0]});
                        pair_c1   <= $signed({4'd0, v_coeff_pair12[23:12]});

                        bit_buf <= stream_buf >> 8;
                        bit_count <= stream_count - 8'd8;

                        if ((stream_count - 8'd8) <= 8'd64)
                            issue_ct_word(CT_END);

                        if (v_pair + 9'd1 == V_PAIRS) begin
                            state <= S_DONE;
                        end else begin
                            v_pair <= v_pair + 9'd1;
                        end
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
