`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// kyber512_ct_pack_engine
// Thesis-shaped Kyber-512 ciphertext packer.
//
// Datapath:
//   coefficient RAM pair -> Compress_du/dv (one 2-lane block) ->
//   bit stream buffer -> aligned 64-bit writer.
//
// This intentionally uses one 2-coeff Compress_du and one 2-coeff Compress_dv
// instance, matching the thesis diagrams instead of the earlier wider parallel
// CT packer.
// -----------------------------------------------------------------------------

module kyber512_ct_pack_engine (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    input  wire [12:0] ct_base_addr,

    // Absolute pair-address bases inside u_ram pair-mode storage.
    // pair address = coefficient address >> 1.
    input  wire [10:0] u_pair_base,
    input  wire [10:0] v_pair_base,

    // One-pair read port to the shared polynomial memory bank.
    output reg  [10:0] ct_pair_rd_addr,
    input  wire signed [15:0] ct_pair_rd_c0,
    input  wire signed [15:0] ct_pair_rd_c1,

    // 64-bit byte-addressed external writer.
    output reg         ext_we,
    output reg  [7:0]  ext_wstrb,
    output reg  [31:0] ext_addr,
    output reg  [63:0] ext_dout,
    output reg  [3:0]  ext_nbytes,
    output reg         done
);

    localparam S_IDLE  = 3'd0;
    localparam S_U_RUN = 3'd1;
    localparam S_V_RUN = 3'd2;
    localparam S_DONE  = 3'd3;

    localparam [8:0] U_PAIRS = 9'd256; // 512 coeff / 2
    localparam [8:0] V_PAIRS = 9'd128; // 256 coeff / 2

    reg [2:0] state;
    reg [8:0] issue_idx;
    reg       rd_v0, rd_v1;
    reg [8:0] rd_idx0, rd_idx1;

    reg [63:0] pack_bits;
    reg [6:0]  pack_bit_count;
    reg [9:0]  pack_byte_offset;

    function [11:0] coeff_to_q12;
        input signed [15:0] c;
        reg signed [31:0] u;
        begin
            u = {{16{c[15]}}, c};
            u = u + ((u >>> 15) & 32'sd3329);
            coeff_to_q12 = u[11:0];
        end
    endfunction

    wire [23:0] compress_pair_din = {coeff_to_q12(ct_pair_rd_c1),
                                     coeff_to_q12(ct_pair_rd_c0)};
    wire [31:0] compress_du_word;
    wire [31:0] compress_dv_word;

    kyber_compress_du u_compress_du (
        .din(compress_pair_din),
        .dout(compress_du_word)
    );

    kyber_compress_dv u_compress_dv (
        .din(compress_pair_din),
        .dout(compress_dv_word)
    );

    wire [10:0] u_issue_pair = u_pair_base + issue_idx[7:0];
    wire [10:0] v_issue_pair = v_pair_base + issue_idx[6:0];

    task issue_pair_read;
        input [10:0] p;
        begin
            ct_pair_rd_addr <= p;
        end
    endtask

    task append_ct_bits;
        input [31:0] bits;
        input [5:0]  nbits;
        reg [63:0] tmp_buf;
        reg [6:0]  tmp_count;
        reg [9:0]  tmp_offset;
        integer bit_i;
        begin
            tmp_buf   = pack_bits;
            tmp_count = pack_bit_count;
            tmp_offset = pack_byte_offset;

            for (bit_i = 0; bit_i < 32; bit_i = bit_i + 1) begin
                if (bit_i < nbits) begin
                    tmp_buf[tmp_count] = bits[bit_i];
                    tmp_count = tmp_count + 7'd1;

                    if (tmp_count == 7'd64) begin
                        ext_we     <= 1'b1;
                        ext_wstrb  <= 8'hFF;
                        ext_addr   <= {19'd0, ct_base_addr + {3'd0, tmp_offset}};
                        ext_dout   <= tmp_buf;
                        ext_nbytes <= 4'd8;

                        tmp_buf   = 64'd0;
                        tmp_count = 7'd0;
                        tmp_offset = tmp_offset + 10'd8;
                    end
                end
            end

            pack_bits      <= tmp_buf;
            pack_bit_count <= tmp_count;
            pack_byte_offset <= tmp_offset;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            issue_idx <= 9'd0;
            rd_v0 <= 1'b0;
            rd_v1 <= 1'b0;
            rd_idx0 <= 9'd0;
            rd_idx1 <= 9'd0;

            ct_pair_rd_addr <= 11'd0;

            ext_we <= 1'b0;
            ext_wstrb <= 8'd0;
            ext_addr <= 32'd0;
            ext_dout <= 64'd0;
            ext_nbytes <= 4'd0;
            done <= 1'b0;

            pack_bits <= 64'd0;
            pack_bit_count <= 7'd0;
            pack_byte_offset <= 10'd0;
        end else begin
            ext_we <= 1'b0;
            ext_wstrb <= 8'd0;
            ext_nbytes <= 4'd0;
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    rd_v0 <= 1'b0;
                    rd_v1 <= 1'b0;
                    issue_idx <= 9'd0;
                    pack_bits <= 64'd0;
                    pack_bit_count <= 7'd0;
                    pack_byte_offset <= 10'd0;

                    if (start) begin
                        state <= S_U_RUN;
                    end
                end

                S_U_RUN: begin
                    if (rd_v1) begin
                        append_ct_bits(compress_du_word, 6'd20);
                    end

                    rd_v1   <= rd_v0;
                    rd_idx1 <= rd_idx0;
                    rd_v0   <= 1'b0;
                    rd_idx0 <= 9'd0;

                    if (issue_idx < U_PAIRS) begin
                        issue_pair_read(u_issue_pair);
                        rd_v0   <= 1'b1;
                        rd_idx0 <= issue_idx;
                        issue_idx <= issue_idx + 9'd1;
                    end

                    if (rd_v1 && (rd_idx1 == (U_PAIRS - 9'd1))) begin
                        state <= S_V_RUN;
                        issue_idx <= 9'd0;
                        rd_v0 <= 1'b0;
                        rd_v1 <= 1'b0;
                        rd_idx0 <= 9'd0;
                        rd_idx1 <= 9'd0;
                    end
                end

                S_V_RUN: begin
                    if (rd_v1) begin
                        append_ct_bits(compress_dv_word, 6'd8);
                    end

                    rd_v1   <= rd_v0;
                    rd_idx1 <= rd_idx0;
                    rd_v0   <= 1'b0;
                    rd_idx0 <= 9'd0;

                    if (issue_idx < V_PAIRS) begin
                        issue_pair_read(v_issue_pair);
                        rd_v0   <= 1'b1;
                        rd_idx0 <= issue_idx;
                        issue_idx <= issue_idx + 9'd1;
                    end

                    if (rd_v1 && (rd_idx1 == (V_PAIRS - 9'd1))) begin
                        state <= S_DONE;
                        rd_v0 <= 1'b0;
                        rd_v1 <= 1'b0;
                        issue_idx <= 9'd0;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    if (start) begin
                        done <= 1'b0;
                        issue_idx <= 9'd0;
                        rd_v0 <= 1'b0;
                        rd_v1 <= 1'b0;
                        pack_bits <= 64'd0;
                        pack_bit_count <= 7'd0;
                        pack_byte_offset <= 10'd0;
                        state <= S_U_RUN;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule


// -----------------------------------------------------------------------------
// kyber512_pk_sk_pack_engine
// Streaming 12-bit packer for KeyGen public-key t and secret-key s.
//
// The old top-level FSM read one coefficient pair, normalized it, wrote 3 bytes,
// and repeated through several FSM states. This engine keeps the same external
// format but runs as a small streaming pipeline:
//   RAM pair read -> 2-coeff 12-bit encode -> 64-bit byte accumulator -> ext write
//
// It uses only one 2-coeff encode lane to keep LUT growth low. The throughput is
// still much higher than the old FSM because a new pair read is issued each
// cycle and byte writes are aligned 64-bit beats.
// -----------------------------------------------------------------------------
module kyber512_pk_sk_pack_engine (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    input  wire [31:0] pk_base_addr,
    input  wire [31:0] sk_base_addr,
    input  wire [255:0] rho,

    input  wire [11:0] t_coeff_base,
    input  wire [11:0] s_coeff_base,

    output reg  [11:0] ram_addr_a,
    output reg  [11:0] ram_addr_b,
    input  wire signed [15:0] ram_dout_a,
    input  wire signed [15:0] ram_dout_b,

    output reg         ext_we,
    output reg  [7:0]  ext_wstrb,
    output reg  [31:0] ext_addr,
    output reg  [63:0] ext_dout,
    input  wire        ext_ready,

    output reg         done
);
    localparam S_IDLE   = 3'd0;
    localparam S_PK_RUN = 3'd1;
    localparam S_RHO    = 3'd2;
    localparam S_SK_RUN = 3'd3;
    localparam S_DONE   = 3'd4;

    localparam [8:0] PAIRS_TOTAL = 9'd256; // K=2, 512 coeff / 2

    reg [2:0] state;
    reg [8:0] pair_idx;
    reg [4:0] rho_byte_idx;
    reg       rd_v0, rd_v1;

    reg [63:0] pack_buf;
    reg [3:0]  pack_count;
    reg [31:0] pack_byte_addr;

    function [63:0] rho_word_msb;
        input [4:0] start_idx;
        integer bi;
        begin
            rho_word_msb = 64'd0;
            for (bi = 0; bi < 8; bi = bi + 1) begin
                rho_word_msb[bi*8 +: 8] =
                    rho[255 - ((start_idx + bi) * 8) -: 8];
            end
        end
    endfunction

    function [11:0] coeff_to_q12;
        input signed [15:0] c;
        reg signed [16:0] t;
        begin
            t = {c[15], c};
            if (t < 0)
                t = t + 17'sd3329;
            if (t >= 17'sd3329)
                t = t - 17'sd3329;
            coeff_to_q12 = t[11:0];
        end
    endfunction

    wire [23:0] pair_din12 = {coeff_to_q12(ram_dout_b),
                              coeff_to_q12(ram_dout_a)};
    wire [23:0] pair_bytes;

    kyber_encode12 u_encode12 (
        .din(pair_din12),
        .dout(pair_bytes)
    );

    task append_bytes;
        input [63:0] bytes;
        input [3:0]  nbytes;
        input [31:0] base_addr;
        reg [63:0] tmp_buf;
        reg [3:0]  tmp_count;
        reg [31:0] tmp_addr;
        integer bi;
        begin
            tmp_buf   = pack_buf;
            tmp_count = pack_count;
            tmp_addr  = pack_byte_addr;

            for (bi = 0; bi < 8; bi = bi + 1) begin
                if (bi < nbytes) begin
                    tmp_buf[tmp_count*8 +: 8] = bytes[bi*8 +: 8];
                    tmp_count = tmp_count + 4'd1;

                    if (tmp_count == 4'd8) begin
                        ext_we    <= 1'b1;
                        ext_wstrb <= 8'hFF;
                        ext_addr  <= base_addr + tmp_addr;
                        ext_dout  <= tmp_buf;
                        tmp_buf   = 64'd0;
                        tmp_count = 4'd0;
                        tmp_addr  = tmp_addr + 32'd8;
                    end
                end
            end

            pack_buf       <= tmp_buf;
            pack_count     <= tmp_count;
            pack_byte_addr <= tmp_addr;
        end
    endtask

    task issue_pair_read;
        input [11:0] coeff_base;
        begin
            ram_addr_a <= coeff_base + {2'd0, pair_idx, 1'b0};
            ram_addr_b <= coeff_base + {2'd0, pair_idx, 1'b0} + 12'd1;
            rd_v0 <= 1'b1;
            pair_idx <= pair_idx + 9'd1;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            pair_idx <= 9'd0;
            rho_byte_idx <= 5'd0;
            rd_v0 <= 1'b0;
            rd_v1 <= 1'b0;
            ram_addr_a <= 12'd0;
            ram_addr_b <= 12'd0;
            ext_we <= 1'b0;
            ext_wstrb <= 8'd0;
            ext_addr <= 32'd0;
            ext_dout <= 64'd0;
            done <= 1'b0;
            pack_buf <= 64'd0;
            pack_count <= 4'd0;
            pack_byte_addr <= 32'd0;
        end else begin
            ext_we <= 1'b0;
            ext_wstrb <= 8'd0;
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    pair_idx <= 9'd0;
                    rho_byte_idx <= 5'd0;
                    rd_v0 <= 1'b0;
                    rd_v1 <= 1'b0;
                    pack_buf <= 64'd0;
                    pack_count <= 4'd0;
                    pack_byte_addr <= 32'd0;
                    if (start)
                        state <= S_PK_RUN;
                end

                S_PK_RUN: begin
                    if (rd_v1)
                        append_bytes({40'd0, pair_bytes}, 4'd3, pk_base_addr);

                    rd_v1 <= rd_v0;
                    rd_v0 <= 1'b0;

                    if (pair_idx < PAIRS_TOTAL)
                        issue_pair_read(t_coeff_base);

                    if (rd_v1 && (pair_idx == PAIRS_TOTAL) && !rd_v0) begin
                        state <= S_RHO;
                        rho_byte_idx <= 5'd0;
                        pack_buf <= 64'd0;
                        pack_count <= 4'd0;
                        pack_byte_addr <= 32'd768;
                    end
                end

                S_RHO: begin
                    ext_we    <= 1'b1;
                    ext_wstrb <= 8'hFF;
                    ext_addr  <= pk_base_addr + 32'd768 + {27'd0, rho_byte_idx};
                    ext_dout  <= rho_word_msb(rho_byte_idx);

                    if (ext_ready) begin
                        if (rho_byte_idx == 5'd24) begin
                            state <= S_SK_RUN;
                            pair_idx <= 9'd0;
                            rd_v0 <= 1'b0;
                            rd_v1 <= 1'b0;
                            pack_buf <= 64'd0;
                            pack_count <= 4'd0;
                            pack_byte_addr <= 32'd0;
                        end else begin
                            rho_byte_idx <= rho_byte_idx + 5'd8;
                        end
                    end
                end

                S_SK_RUN: begin
                    if (rd_v1)
                        append_bytes({40'd0, pair_bytes}, 4'd3, sk_base_addr);

                    rd_v1 <= rd_v0;
                    rd_v0 <= 1'b0;

                    if (pair_idx < PAIRS_TOTAL)
                        issue_pair_read(s_coeff_base);

                    if (rd_v1 && (pair_idx == PAIRS_TOTAL) && !rd_v0) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
