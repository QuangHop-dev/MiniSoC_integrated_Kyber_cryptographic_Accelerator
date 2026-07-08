`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// kyber512_core_fsm
// Kyber512 RTL source. Comments and unused debug-only code were removed for a
// synthesis-oriented release build.
// -----------------------------------------------------------------------------

module kyber512_core_fsm (
    input  wire clk,
    input  wire rst,

    input  wire        start,
    input  wire [1:0]  opcode,
    output reg         done,
    output reg         busy,

    output reg         ext_we,
    output reg         ext_re,
    output reg  [31:0] ext_addr,
    output reg  [63:0] ext_dout,
    output reg  [7:0]  ext_wstrb,
    input  wire [63:0] ext_din,
    input  wire        ext_ready,
    
    
    input  wire [511:0] seed_in,
    input  wire         seed_valid,

    output wire [7:0]  state_dbg
);

    
    
    
    
    localparam S_IDLE           = 8'd0;
    localparam S_KG_LOAD_SEED        = 8'd10; localparam S_KG_HASH_G      = 8'd11; 
    localparam S_KG_PRF_E       = 8'd12; localparam S_KG_CBD_E       = 8'd13; localparam S_KG_NTT_E       = 8'd14; localparam S_KG_DMA_E       = 8'd15;
    localparam S_KG_PRF_S       = 8'd16; localparam S_KG_CBD_S       = 8'd17; localparam S_KG_NTT_S       = 8'd18; localparam S_KG_DMA_S       = 8'd19;
    localparam S_KG_GEN_A       = 8'd20; 
    localparam S_KG_PWMA_A_S    = 8'd23; localparam S_KG_HASH_PK     = 8'd24; localparam S_KG_PACK        = 8'd25;
    localparam S_ENC_LOAD_COINS = 8'd30; localparam S_ENC_PRF_R = 8'd32; localparam S_ENC_CBD_R = 8'd33; localparam S_ENC_NTT_R = 8'd34; localparam S_ENC_PWMA_U = 8'd35; localparam S_ENC_INTT_U = 8'd36; localparam S_ENC_PWMA_V = 8'd37; localparam S_ENC_INTT_V = 8'd38; localparam S_ENC_WRITE_SS = 8'd42; localparam S_ENC_PACK = 8'd43;
    localparam S_ENC_READ_PK = 8'd44;
    localparam S_DEC_READ = 8'd50; localparam S_DEC_DECOMP = 8'd51; localparam S_DEC_NTT_U = 8'd52; localparam S_DEC_CMP = 8'd56; localparam S_DEC_PACK = 8'd58;
    localparam S_DEC_READ_REST = 8'd55; localparam S_DEC_READ_CT = 8'd59;
    localparam S_KG_WRITE_REST = 8'd60;
localparam S_DEC_RKPRF     = 8'd62;

    localparam [31:0] PK_EXT_BASE = 32'd0;
    localparam [31:0] SK_EXT_BASE = 32'd2000;
    localparam [31:0] CT_EXT_BASE = 32'd6000;
    localparam [31:0] SS_EXT_BASE = 32'd8000;
reg [255:0] reg_rho, reg_sigma, reg_z, reg_m, reg_K_bar, reg_r_seed, reg_H_pk;
    reg dec_reenc_mode;
    reg enc_write_ss_ready, dec_kdf_ready;
    reg [1:0] enc_noise_kind; 
    reg [1:0] enc_ntt_phase;  
    
    reg [7:0]  state;
    reg [11:0] dma_cnt;
    reg [2:0]  loop_i, loop_j;
    reg [3:0]  dec_phase;
    localparam [2:0] KYBER_K = 3'd2;
wire       ntt_dec_intt_gs_en;

    // Wide write path for ciphertext local RAMs (declared before first use
    // to avoid implicit-net creation in Verilog port connections).
    reg         ct_wide_we;
    reg  [10:0] ct_wide_addr;
    reg  [63:0] ct_wide_din;
    reg  [7:0]  ct_wide_wstrb;

    reg  [10:0] ct_addr_b_fsm;
    wire [10:0] ct_addr_b;
    wire [7:0]  ct_dout;
    wire [10:0] ct_wide_raddr;
    wire [63:0] ct_wide_dout;
    wire        ct_wide_re;
    kyber_byte_bram_wide u_ct_ram (
        .wclk(clk),
        .wide_we(ct_wide_we), .wide_waddr(ct_wide_addr),
        .wide_din(ct_wide_din), .wide_wstrb(ct_wide_wstrb),
        .rclk(clk), .raddr(ct_addr_b), .dout(ct_dout),
        .wide_rclk(clk), .wide_re(ct_wide_re),
        .wide_raddr(ct_wide_raddr), .wide_dout(ct_wide_dout)
    );

    wire [10:0] ct_unpack_wide_raddr;
function [255:0] flip_bytes_32;
        input [255:0] in_data;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1)
                flip_bytes_32[(31-i)*8 +: 8] = in_data[i*8 +: 8];
        end
    endfunction

    function [63:0] flip_bytes_8;
        input [63:0] in_data;
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1)
                flip_bytes_8[(7-i)*8 +: 8] = in_data[i*8 +: 8];
        end
    endfunction


    function [63:0] bytes8_from_256_msb;
        input [255:0] in_data;
        input [4:0]   start_idx;
        integer bi;
        begin
            bytes8_from_256_msb = 64'd0;
            for (bi = 0; bi < 8; bi = bi + 1) begin
                bytes8_from_256_msb[bi*8 +: 8] =
                    in_data[255 - ((start_idx + bi) * 8) -: 8];
            end
        end
    endfunction


    function signed [31:0] mul_1441_shiftadd_s16;
        input signed [15:0] x;
        reg signed [31:0] xs;
        begin
            xs = {{16{x[15]}}, x};
            mul_1441_shiftadd_s16 = (xs <<< 10) + (xs <<< 8) +
                                    (xs <<< 7)  + (xs <<< 5) + xs;
        end
    endfunction

    function [11:0] canonical_modq12;
        input signed [15:0] x;
        reg signed [16:0] value;
        begin
            value = x;
            if (value < 17'sd0)
                value = value + 17'sd3329;
            else if (value >= 17'sd3329)
                value = value - 17'sd3329;
            canonical_modq12 = value[11:0];
        end
    endfunction
reg hash_start; reg [2:0] hash_cmd; reg hash_prf_eta3;
    reg        hash_in_stream_en;
    reg        hash_in_valid;
    wire       hash_in_ready;
    reg [63:0] hash_in_data;
    reg [3:0]  hash_in_bytes;
    reg        hash_in_last;
    wire [511:0] hash_dout; wire hash_done;
    wire [63:0] hash_out_data;
    wire        hash_out_valid;
    wire        hash_out_ready;
    wire        hash_out_last;
    wire [4:0]  hash_out_word_idx;

    
    wire        gm_xof_req_valid;
    wire [271:0] gm_xof_req_din;
    wire        gm_xof_req_ready;
    wire        gm_xof_release;
    wire [63:0] gm_xof_word_data;
    wire        gm_xof_word_valid;
    wire        gm_xof_word_ready;

    kyber_hash_unit u_hash (
        .clk(clk), .rst(rst), .start(hash_start), .hash_cmd(hash_cmd), .prf_eta3(hash_prf_eta3),
        .hash_in_stream_en(hash_in_stream_en), .hash_in_valid(hash_in_valid),
        .hash_in_ready(hash_in_ready), .hash_in_data(hash_in_data),
        .hash_in_bytes(hash_in_bytes), .hash_in_last(hash_in_last),
        .xof_req_valid(gm_xof_req_valid), .xof_req_din(gm_xof_req_din), .xof_req_ready(gm_xof_req_ready),
        .xof_release(gm_xof_release), .xof_word_data(gm_xof_word_data), .xof_word_valid(gm_xof_word_valid), .xof_word_ready(gm_xof_word_ready),
        .hash_out_data(hash_out_data), .hash_out_valid(hash_out_valid), .hash_out_ready(hash_out_ready),
        .hash_out_last(hash_out_last), .hash_out_word_idx(hash_out_word_idx),
        .dout(hash_dout), .done(hash_done), .busy()
    );

    
    reg cbd_start; reg [10:0] cbd_base_addr; reg cbd_eta3_mode;
    wire cbd_we, cbd_we_b, cbd_done;
    wire [10:0] cbd_ram_addr, cbd_ram_addr_b;
    wire signed [15:0] cbd_poly_out, cbd_poly_out_b;
    kyber_cbd_sampler u_cbd (
        .clk(clk), .rst(rst), .start(cbd_start), .eta3_mode(cbd_eta3_mode),
        .stream_valid(hash_out_valid), .stream_ready(hash_out_ready),
        .stream_data(hash_out_data), .stream_last(hash_out_last),
        .base_addr(cbd_base_addr),
        .we(cbd_we), .ram_addr(cbd_ram_addr), .poly_coeffs_out(cbd_poly_out),
        .we_b(cbd_we_b), .ram_addr_b(cbd_ram_addr_b), .poly_coeffs_out_b(cbd_poly_out_b),
        .done(cbd_done)
    );

    
    reg gm_start, gm_transposed;
    wire gm_we, gm_done;
    wire [11:0] gm_ram_addr;
    wire [15:0] gm_ram_din;
    wire gm_we_b;
    wire [11:0] gm_ram_addr_b;
    wire [15:0] gm_ram_din_b;
    reg gm_pwma_stream_mode;
    reg gm_pwma_stream_done;
    reg gm_pwma_all_done;
    wire gm_pair_ready;
    reg signed [15:0] gm_stream_fifo [0:7];
    reg [2:0] gm_stream_rd_ptr;
    reg [2:0] gm_stream_wr_ptr;
    reg [3:0] gm_stream_count;
    wire [2:0] gm_stream_rd_ptr_p1 = gm_stream_rd_ptr + 3'd1;
    wire [2:0] gm_stream_wr_ptr_p1 = gm_stream_wr_ptr + 3'd1;
    wire gm_stream_pair_valid = gm_pwma_stream_mode && (gm_stream_count >= 4'd2);
    wire signed [15:0] gm_stream_pair_c0 = gm_stream_fifo[gm_stream_rd_ptr];
    wire signed [15:0] gm_stream_pair_c1 = gm_stream_fifo[gm_stream_rd_ptr_p1];
    wire gm_stream_pair_consume = gm_stream_pair_valid && gm_pair_ready;
    wire [3:0] gm_stream_pop_count = gm_stream_pair_consume ? 4'd2 : 4'd0;
    wire [3:0] gm_stream_push_count =
        (gm_pwma_stream_mode ? ({3'd0, gm_we} + {3'd0, gm_we_b}) : 4'd0);
    wire [3:0] gm_stream_count_after_pop = gm_stream_count - gm_stream_pop_count;
    // The sampler can have two coefficients already committed when ready
    // deasserts. Stop at four entries so the 8-entry FIFO cannot overrun.
    wire gm_coeff_ready = !gm_pwma_stream_mode ||
                          (gm_stream_count_after_pop <= 4'd4);
    kyber_matrix_sampler u_gm (
        .clk(clk), .rst(rst), .start(gm_start), .rho(reg_rho), .transposed(gm_transposed),
        .xof_req_valid(gm_xof_req_valid), .xof_req_din(gm_xof_req_din), .xof_req_ready(gm_xof_req_ready), .xof_release(gm_xof_release),
        .xof_word_data(gm_xof_word_data), .xof_word_valid(gm_xof_word_valid), .xof_word_ready(gm_xof_word_ready),
        .coeff_ready(gm_coeff_ready),
        .we(gm_we), .ram_addr(gm_ram_addr), .ram_dout(gm_ram_din),
        .we_b(gm_we_b), .ram_addr_b(gm_ram_addr_b), .ram_dout_b(gm_ram_din_b),
        .done(gm_done), .busy()
    );

    
    reg ntt_start, ntt_mode; wire ntt_done; reg ntt_ext_we, ntt_ext_we_b; reg [7:0] ntt_ext_addr, ntt_ext_addr_b; reg signed [15:0] ntt_ext_din, ntt_ext_din_b;
    wire signed [15:0] ntt_ext_dout;
    wire signed [15:0] ntt_ext_dout_b;
    wire signed [15:0] shared_twiddle_dout;
    wire [6:0] local_pwma_zeta_addr;
    wire signed [15:0] pwma_zeta_real =
        (shared_twiddle_dout > 16'sd1664) ?
            shared_twiddle_dout - 16'sd3329 :
            shared_twiddle_dout;
    kyber_ntt_core u_ntt (
        .clk(clk), .rst(rst), .start(ntt_start), .mode(ntt_mode), .intt_gs_en(ntt_dec_intt_gs_en),
        .ext_we(ntt_ext_we), .ext_we_b(ntt_ext_we_b),
        .ext_addr(ntt_ext_addr), .ext_addr_b(ntt_ext_addr_b),
        .ext_din(ntt_ext_din), .ext_din_b(ntt_ext_din_b),
        .ext_dout(ntt_ext_dout), .ext_dout_b(ntt_ext_dout_b),
        .ext_twiddle_addr(local_pwma_zeta_addr),
        .ext_twiddle_dout(shared_twiddle_dout),
        .done(ntt_done)
    );

    wire        local_pwma_active;
    wire [11:0] kg_pack_ram_addr_a;
    wire [11:0] kg_pack_ram_addr_b;
    wire kg_pack_mb_select = (state == S_KG_PACK);

    reg         mb_rd_en;
    reg [2:0]   mb_rd_slot;
    reg [6:0]   mb_rd_pair_addr;
    wire signed [15:0] mb_rd_c0;
    wire signed [15:0] mb_rd_c1;
    reg         mb_wr_en_c0;
    reg         mb_wr_en_c1;
    reg [2:0]   mb_wr_slot;
    reg [6:0]   mb_wr_pair_addr;
    reg signed [15:0] mb_wr_c0;
    reg signed [15:0] mb_wr_c1;
    wire        mb_port_rd_en;
    wire [2:0]  mb_port_rd_slot;
    wire [6:0]  mb_port_rd_pair_addr;

    kyber_poly_memory_bank u_memory_bank (
        .clk(clk),
        .rd_en(mb_port_rd_en),
        .rd_slot(mb_port_rd_slot),
        .rd_pair_addr(mb_port_rd_pair_addr),
        .rd_c0(mb_rd_c0),
        .rd_c1(mb_rd_c1),
        .wr_en_c0(mb_wr_en_c0),
        .wr_en_c1(mb_wr_en_c1),
        .wr_slot(mb_wr_slot),
        .wr_pair_addr(mb_wr_pair_addr),
        .wr_c0(mb_wr_c0),
        .wr_c1(mb_wr_c1)
    );

    reg         local_pwma_bank;
    reg         local_pwma_operand_bank;
    reg         local_pwma_accumulate;
    reg         local_pwma_acc_we;
    reg         local_pwma_acc_load_bank;
    reg [6:0]   local_pwma_acc_addr;
    reg [31:0]  local_pwma_acc_pair;
    reg         local_pwma_operand_we;
    reg         local_pwma_operand_load_bank;
    reg [6:0]   local_pwma_operand_addr;
    reg [31:0]  local_pwma_operand_pair;
    reg         local_pwma_start;
    reg         local_pwma_use_tomont;
    wire        local_pwma_stream_valid;
    wire        local_pwma_stream_ready;
    wire signed [15:0] local_pwma_stream_c0;
    wire signed [15:0] local_pwma_stream_c1;
    reg [6:0]   local_pwma_result_addr;
    reg         local_pwma_result_bank_fsm;
    wire        local_pwma_result_bank =
        kg_pack_mb_select && !kg_pack_ram_addr_a[9] ?
            kg_pack_ram_addr_a[8] : local_pwma_result_bank_fsm;
    wire [6:0] local_pwma_read_addr =
        kg_pack_mb_select && !kg_pack_ram_addr_a[9] ?
            kg_pack_ram_addr_a[7:1] : local_pwma_result_addr;
    wire [31:0] local_pwma_result_pair;
    wire        local_pwma_result_valid;
    wire [6:0]  local_pwma_result_index;
    wire [31:0] local_pwma_write_pair;
    wire        local_pwma_busy;
    wire        local_pwma_done;

    kyber_pwma_local u_pwma_local (
        .clk(clk),
        .rst(rst),
        .bank(local_pwma_bank),
        .operand_bank(local_pwma_operand_bank),
        .accumulate(local_pwma_accumulate),
        .acc_load_we(local_pwma_acc_we),
        .acc_load_bank(local_pwma_acc_load_bank),
        .acc_load_addr(local_pwma_acc_addr),
        .acc_load_pair(local_pwma_acc_pair),
        .operand_load_we(local_pwma_operand_we),
        .operand_load_bank(local_pwma_operand_load_bank),
        .operand_load_addr(local_pwma_operand_addr),
        .operand_load_pair(local_pwma_operand_pair),
        .start(local_pwma_start),
        .use_tomont(local_pwma_use_tomont),
        .stream_valid(local_pwma_stream_valid),
        .stream_ready(local_pwma_stream_ready),
        .stream_c0(local_pwma_stream_c0),
        .stream_c1(local_pwma_stream_c1),
        .zeta_addr(local_pwma_zeta_addr),
        .zeta_in(pwma_zeta_real),
        .result_rd_bank(local_pwma_result_bank),
        .result_rd_addr(local_pwma_read_addr),
        .result_rd_pair(local_pwma_result_pair),
        .result_valid(local_pwma_result_valid),
        .result_index(local_pwma_result_index),
        .result_pair(local_pwma_write_pair),
        .busy(local_pwma_busy),
        .done(local_pwma_done)
    );

    
    reg cmp_start;
    reg cmp_finish;
    wire cmp_done, cmp_not_equal;
    reg ct_cmp_valid;
    reg [63:0] ct_cmp_prime_word;

    // Legacy byte-read port is kept for hash/RKPRF users. Re-encrypted
    // ciphertext is compared as a 64-bit stream while CT_PACK emits it.
    assign ct_addr_b = ct_addr_b_fsm;
    kyber_ct_compare u_cmp (
        .clk(clk),
        .rst(rst),
        .start(cmp_start),
        .word_valid((state == S_ENC_PACK) && dec_reenc_mode && ct_cmp_valid),
        .data_c(ct_wide_dout),
        .data_c_prime(ct_cmp_prime_word),
        .finish(cmp_finish),
        .not_equal(cmp_not_equal),
        .done(cmp_done)
    );
    
    
    
    reg [2:0] mux_sel, ntt_mux_sel;
    reg fsm_ntt_we, fsm_ntt_we_b; reg [7:0] fsm_ntt_addr, fsm_ntt_addr_b; reg signed [15:0] fsm_ntt_din, fsm_ntt_din_b;
    
    
    localparam [11:0] ENC_U_BASE = 12'd512;
    localparam [11:0] ENC_V_BASE = 12'd1024;
    reg [11:0] ct_cap_idx;
    reg [2:0] dec_j_idx;
    wire signed [31:0] dec_invntt_mul_comb = mul_1441_shiftadd_s16(ntt_ext_dout);
    wire signed [31:0] dec_invntt_mul_b_comb = mul_1441_shiftadd_s16(ntt_ext_dout_b);
    reg  signed [31:0] dec_invntt_mul_r;
    reg  signed [31:0] dec_invntt_mul_b_r;
    wire signed [15:0] dec_invntt_scaled_comb;
    wire signed [15:0] dec_invntt_scaled_b_comb;
    reg  signed [15:0] dec_invntt_scaled_r;
    reg  signed [15:0] dec_invntt_scaled_b_r;
    reg [4:0] dp_phase;
    wire [6:0] message_pair_index =
        ((state == S_ENC_INTT_V) && (enc_ntt_phase == 2'd2) &&
         (dma_cnt > 12'd4)) ?
            (dma_cnt[6:0] - 7'd5) : dma_cnt[6:0];
    wire [8:0] local_message_coeff_index = {message_pair_index, 1'b0};
    wire [4:0] local_message_byte_index =
        5'd31 - local_message_coeff_index[7:3];
    wire [7:0] local_message_byte =
        reg_m[{local_message_byte_index, 3'b000} +: 8];
    wire [1:0] local_message_bits = {
        local_message_byte[local_message_coeff_index[2:0] + 3'd1],
        local_message_byte[local_message_coeff_index[2:0]]
    };
    wire [23:0] local_decoded_message_pair;

    kyber_decode1 u_decode1_local (
        .din({30'd0, local_message_bits}),
        .dout(local_decoded_message_pair)
    );

    wire [23:0] scaled_invntt_pair = {
        canonical_modq12(dec_invntt_scaled_b_r),
        canonical_modq12(dec_invntt_scaled_r)
    };
    wire [23:0] memory_bank_pair = {
        canonical_modq12(mb_rd_c1),
        canonical_modq12(mb_rd_c0)
    };
    wire direct_addsub_is_dec =
        (state == S_DEC_DECOMP) && (dp_phase == 5'd8);
    wire direct_addsub_add_message =
        (state == S_ENC_INTT_V) && (enc_ntt_phase == 2'd2);
    wire [23:0] direct_addsub_a =
        direct_addsub_is_dec ? memory_bank_pair : scaled_invntt_pair;
    wire [23:0] direct_addsub_b =
        direct_addsub_is_dec ? scaled_invntt_pair : memory_bank_pair;
    wire [23:0] direct_addsub_result;

    kyber_unified_addsub_modq u_addsub_local (
        .a(direct_addsub_a),
        .b(direct_addsub_b),
        .c(local_decoded_message_pair),
        .subtract(direct_addsub_is_dec),
        .add_c(direct_addsub_add_message),
        .y(direct_addsub_result)
    );

    reg [3:0] kg_poly_phase;
    reg       kg_mb_load_valid;
    reg [6:0] kg_mb_load_addr;
    reg       kg_mb_load_capture_valid;
    reg [6:0] kg_mb_load_capture_addr;
    reg       kg_transfer_valid;
    reg [6:0] kg_transfer_addr;
    reg       kg_transfer_capture_valid;
    reg [6:0] kg_transfer_capture_addr;
    reg       kg_gm_started;
    reg       kg_local_datapath_enable;
    reg       kg_a_cache_active;
    reg       kg_a_cache_done;
    reg       kg_a_source_done;
    reg [9:0] kg_a_cache_count;
    reg       dp_local_pwma_enable;
    reg       dp_local_pwma_gm_source;
    reg       dp_local_pwma_ntt_source;
    reg       dp_mb_stream_valid;
    reg [6:0] dp_mb_stream_addr;
    reg       dp_mb_stream_capture_valid;
    reg [6:0] dp_mb_stream_capture_addr;

    assign local_pwma_active =
        (kg_local_datapath_enable && (state == S_KG_PWMA_A_S)) ||
        dp_local_pwma_enable;
    assign local_pwma_stream_valid =
        local_pwma_active &&
        (dp_local_pwma_ntt_source ?
            ((state == S_DEC_DECOMP) && (dp_phase == 5'd2) &&
             (dma_cnt > 12'd2) && (dma_cnt < 12'd131)) :
         dp_local_pwma_enable ?
            (dp_local_pwma_gm_source ? gm_stream_pair_valid :
                                         dp_mb_stream_capture_valid) :
            ((kg_poly_phase == 4'd3) &&
             dp_mb_stream_capture_valid));
    assign local_pwma_stream_c0 =
        dp_local_pwma_ntt_source ? ntt_ext_dout :
        ((dp_local_pwma_enable && !dp_local_pwma_gm_source) ||
         (kg_local_datapath_enable && (state == S_KG_PWMA_A_S))) ?
            mb_rd_c0 : gm_stream_pair_c0;
    assign local_pwma_stream_c1 =
        dp_local_pwma_ntt_source ? ntt_ext_dout_b :
        ((dp_local_pwma_enable && !dp_local_pwma_gm_source) ||
         (kg_local_datapath_enable && (state == S_KG_PWMA_A_S))) ?
            mb_rd_c1 : gm_stream_pair_c1;
    assign gm_pair_ready =
        kg_a_cache_active ?
            ((state != S_KG_DMA_E) && (state != S_KG_DMA_S)) :
        (dp_local_pwma_enable && dp_local_pwma_gm_source) ?
            local_pwma_stream_ready :
            1'b0;
    reg         ct_pack_start;
    reg         ct_pack_sent;
    wire        ct_pack_done;
    reg         kg_pack_start;
    reg         kg_pack_sent;
    wire        kg_pack_done;

    // CT_PACK pair-read + 64-bit writer interface
    wire [10:0] ct_pack_pair_rd_addr;
    wire        ct_pack_ext_we;
    wire [7:0]  ct_pack_ext_wstrb;
    wire [31:0] ct_pack_ext_addr;
    wire [63:0] ct_pack_ext_dout;
    wire [3:0]  ct_pack_ext_nbytes;

    wire        kg_pack_ext_we;
    wire [7:0]  kg_pack_ext_wstrb;
    wire [31:0] kg_pack_ext_addr;
    wire [63:0] kg_pack_ext_dout;

    // CT_UNPACK engine interface: 64-bit CT read + dual coefficient writes
    reg         ct_unpack_start;
    reg         ct_unpack_sent;
    wire        ct_unpack_done;
    wire        ct_unpack_pair_we;
    wire [2:0]  ct_unpack_pair_slot;
    wire [6:0]  ct_unpack_pair_addr;
    wire signed [15:0] ct_unpack_pair_c0;
    wire signed [15:0] ct_unpack_pair_c1;

    wire ct_pack_mb_select = (state == S_ENC_PACK);
    wire [2:0] kg_pack_mb_slot = kg_pack_ram_addr_a[9:8];
    wire [6:0] kg_pack_mb_pair_addr = kg_pack_ram_addr_a[7:1];
    wire [2:0] ct_pack_mb_slot =
        ct_pack_pair_rd_addr[9] ? 3'd6 :
        (3'd4 + {2'd0, ct_pack_pair_rd_addr[7]});
    wire [6:0] ct_pack_mb_pair_addr = ct_pack_pair_rd_addr[6:0];
    wire kg_pack_reads_s = kg_pack_mb_select && kg_pack_ram_addr_a[9];
    assign mb_port_rd_en = kg_pack_reads_s || ct_pack_mb_select || mb_rd_en;
    assign mb_port_rd_slot =
        kg_pack_reads_s ? kg_pack_mb_slot :
        ct_pack_mb_select ? ct_pack_mb_slot : mb_rd_slot;
    assign mb_port_rd_pair_addr =
        kg_pack_reads_s ? kg_pack_mb_pair_addr :
        ct_pack_mb_select ? ct_pack_mb_pair_addr : mb_rd_pair_addr;

    kyber512_ct_pack_engine u_ct_pack (
        .clk(clk),
        .rst(rst),
        .start(ct_pack_start),

        .ct_base_addr(CT_EXT_BASE[12:0]),
        .u_pair_base(ENC_U_BASE[11:1]),
        .v_pair_base(ENC_V_BASE[11:1]),

        .ct_pair_rd_addr(ct_pack_pair_rd_addr),
        .ct_pair_rd_c0(mb_rd_c0),
        .ct_pair_rd_c1(mb_rd_c1),

        .ext_we(ct_pack_ext_we),
        .ext_wstrb(ct_pack_ext_wstrb),
        .ext_addr(ct_pack_ext_addr),
        .ext_dout(ct_pack_ext_dout),
        .ext_nbytes(ct_pack_ext_nbytes),
        .done(ct_pack_done)
    );

    kyber512_pk_sk_pack_engine u_kg_pack (
        .clk(clk),
        .rst(rst),
        .start(kg_pack_start),
        .pk_base_addr(PK_EXT_BASE),
        .sk_base_addr(SK_EXT_BASE),
        .rho(reg_rho),
        .t_coeff_base(12'd0),
        .s_coeff_base(12'd512),
        .ram_addr_a(kg_pack_ram_addr_a),
        .ram_addr_b(kg_pack_ram_addr_b),
        .ram_dout_a(kg_pack_ram_addr_a[9] ?
                        mb_rd_c0 : local_pwma_result_pair[15:0]),
        .ram_dout_b(kg_pack_ram_addr_a[9] ?
                        mb_rd_c1 : local_pwma_result_pair[31:16]),
        .ext_we(kg_pack_ext_we),
        .ext_wstrb(kg_pack_ext_wstrb),
        .ext_addr(kg_pack_ext_addr),
        .ext_dout(kg_pack_ext_dout),
        .ext_ready(ext_ready),
        .done(kg_pack_done)
    );

    kyber512_ct_unpack_engine u_ct_unpack_engine (
        .clk(clk),
        .rst(rst),
        .start(ct_unpack_start),
        .ct_wide_raddr(ct_unpack_wide_raddr),
        .ct_wide_dout(ct_wide_dout),
        .pair_we(ct_unpack_pair_we),
        .pair_slot(ct_unpack_pair_slot),
        .pair_addr(ct_unpack_pair_addr),
        .pair_c0(ct_unpack_pair_c0),
        .pair_c1(ct_unpack_pair_c1),
        .done(ct_unpack_done)
    );
    kyber_montgomery_reduce u_dec_invntt_scale (
        .a(dec_invntt_mul_r),
        .t(dec_invntt_scaled_comb)
    );
    kyber_montgomery_reduce u_dec_invntt_scale_b (
        .a(dec_invntt_mul_b_r),
        .t(dec_invntt_scaled_b_comb)
    );

    always @(posedge clk) begin
        if (rst) begin
            dec_invntt_mul_r      <= 32'sd0;
            dec_invntt_mul_b_r    <= 32'sd0;
            dec_invntt_scaled_r   <= 16'sd0;
            dec_invntt_scaled_b_r <= 16'sd0;
        end else begin
            dec_invntt_mul_r      <= dec_invntt_mul_comb;
            dec_invntt_mul_b_r    <= dec_invntt_mul_b_comb;
            dec_invntt_scaled_r   <= dec_invntt_scaled_comb;
            dec_invntt_scaled_b_r <= dec_invntt_scaled_b_comb;
        end
    end

    always @(*) begin
        ntt_ext_we     = 1'b0;
        ntt_ext_addr   = 8'd0;
        ntt_ext_din    = 16'sd0;
        ntt_ext_we_b   = 1'b0;
        ntt_ext_addr_b = 8'd0;
        ntt_ext_din_b  = 16'sd0;
        if (ntt_mux_sel == 3'd1) begin
            // CBD sampler emits up to two coefficients per cycle.
            ntt_ext_we   = cbd_we;
            ntt_ext_addr = cbd_ram_addr[7:0];
            ntt_ext_din  = cbd_poly_out;
            ntt_ext_we_b   = cbd_we_b;
            ntt_ext_addr_b = cbd_ram_addr_b[7:0];
            ntt_ext_din_b  = cbd_poly_out_b;
        end else begin
            ntt_ext_we     = fsm_ntt_we;
            ntt_ext_addr   = fsm_ntt_addr;
            ntt_ext_din    = fsm_ntt_din;
            ntt_ext_we_b   = fsm_ntt_we_b;
            ntt_ext_addr_b = fsm_ntt_addr_b;
            ntt_ext_din_b  = fsm_ntt_din_b;
        end
    end

    reg hash_sent, cbd_sent, ntt_sent, pwma_sent, gm_sent;
    reg gm_bg_done;
    localparam ETA1_IS_3 = 1'b1;
assign ntt_dec_intt_gs_en =
        ((state == S_DEC_DECOMP) && (dp_phase == 5'd7)) ||
        (state == S_ENC_INTT_U) ||
        (state == S_ENC_INTT_V);
    localparam [11:0] CT_BYTES_TOTAL = 12'd768;

    
    reg [1:0]  pack_phase;
    reg [2:0]  pack_step;
    reg [31:0] pack_pk_addr;
    reg [31:0] pack_sk_addr;
    reg [63:0] pk_copy_word;
    localparam [11:0] PK_BYTES_TOTAL = 12'd800;

reg dec_sk_reload_done;
    reg [2:0] dec_sk_poly;
    reg [7:0] dec_sk_pair;
    
    reg hash_fetching;
    reg fetch_wait;
    reg [7:0] fetch_cnt;
    reg dec_fetch_done;
reg [11:0] rem12;
    integer byte_i;
    reg [11:0] u_pair_base12, u_pair_base_b12;
    reg [11:0] v_pair_base12, v_pair_base_b12;
    reg [11:0] sk_coeff_base;
    reg [1:0]  dec_msg_pair_pos;
    reg [7:0]  dec_msg_byte_acc;
    reg        dec_u0_direct_loaded;
    reg        dec_u0_ntt_started;
    reg        dec_u0_ntt_done;
    reg        dec_unpack_done_latched;

    wire [23:0] ext_decode12_coeff_pair;
    kyber_decode12 u_decode12_ext_pair (
        .din(ext_din[23:0]),
        .dout(ext_decode12_coeff_pair)
    );

    wire [31:0] dec_encode1_word;
    kyber_encode1 u_encode1_msg (
        .din(direct_addsub_result),
        .dout(dec_encode1_word)
    );

    wire ct_cmp_read_fire =
        (state == S_ENC_PACK) && dec_reenc_mode &&
        ct_pack_ext_we &&
        (ct_cap_idx < CT_BYTES_TOTAL);

    assign ct_wide_raddr =
        ((state == S_DEC_DECOMP) && (dec_phase == 4'd0)) ? ct_unpack_wide_raddr :
        (ct_cmp_read_fire ? ct_cap_idx[10:0] : 11'd0);
    assign ct_wide_re =
        ((state == S_DEC_DECOMP) && (dec_phase == 4'd0)) ||
        ct_cmp_read_fire;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; mux_sel <= 0; ntt_mux_sel <= 0; done <= 0; busy <= 0;
            ext_we <= 0; ext_re <= 0; ext_addr <= 0; ext_dout <= 0; ext_wstrb <= 8'h01;
            
            hash_start <= 0; cbd_start <= 0; ntt_start <= 0; cmp_start <= 0; cmp_finish <= 1'b0; gm_start <= 0; gm_transposed <= 1'b0;
            gm_pwma_stream_mode <= 1'b0;
            gm_pwma_stream_done <= 1'b0;
            gm_pwma_all_done <= 1'b0;
            gm_stream_rd_ptr <= 3'd0;
            gm_stream_wr_ptr <= 3'd0;
            gm_stream_count <= 4'd0;
            hash_in_stream_en <= 1'b0; hash_in_valid <= 1'b0; hash_in_data <= 64'd0; hash_in_bytes <= 4'd0; hash_in_last <= 1'b0;
            
            hash_sent <= 0; cbd_sent <= 0; ntt_sent <= 0; pwma_sent <= 0; gm_sent <= 0;
            gm_bg_done <= 1'b0;
            ct_pack_sent <= 1'b0;
            kg_pack_start <= 1'b0;
            kg_pack_sent <= 1'b0;
            fsm_ntt_we <= 0; fsm_ntt_we_b <= 0; hash_prf_eta3 <= 0; cbd_eta3_mode <= 0;
            ct_pack_start <= 1'b0; kg_pack_start <= 1'b0; ct_unpack_start <= 1'b0; ct_unpack_sent <= 1'b0; ct_wide_we <= 1'b0; ct_wide_addr <= 11'd0; ct_wide_din <= 64'd0; ct_wide_wstrb <= 8'd0;
            pack_phase <= 2'd0; pack_step <= 3'd0;
            pack_pk_addr <= PK_EXT_BASE; pack_sk_addr <= SK_EXT_BASE; pk_copy_word <= 64'd0;
            ct_addr_b_fsm <= 11'd0;
            ct_cmp_valid <= 1'b0;
            ct_cmp_prime_word <= 64'd0;
            dec_reenc_mode <= 1'b0;
            enc_write_ss_ready <= 1'b0; dec_kdf_ready <= 1'b0;
            enc_noise_kind <= 2'd0;
            enc_ntt_phase <= 2'd0;
            dec_phase <= 4'd0;
            ct_cap_idx <= 12'd0;
            hash_fetching <= 1'b0;
            fetch_wait <= 1'b0;
            fetch_cnt <= 8'd0;
            dec_fetch_done <= 1'b0;
            dec_j_idx <= 3'd0;
            dec_sk_reload_done <= 1'b0;
            dec_sk_poly <= 3'd0;
            dec_sk_pair <= 8'd0;
            dec_msg_pair_pos <= 2'd0;
            dec_msg_byte_acc <= 8'd0;
            dec_u0_direct_loaded <= 1'b0;
            dec_u0_ntt_started <= 1'b0;
            dec_u0_ntt_done <= 1'b0;
            dec_unpack_done_latched <= 1'b0;
            mb_rd_en <= 1'b0;
            mb_rd_slot <= 3'd0;
            mb_rd_pair_addr <= 7'd0;
            mb_wr_en_c0 <= 1'b0;
            mb_wr_en_c1 <= 1'b0;
            mb_wr_slot <= 3'd0;
            mb_wr_pair_addr <= 7'd0;
            mb_wr_c0 <= 16'sd0;
            mb_wr_c1 <= 16'sd0;
            local_pwma_bank <= 1'b0;
            local_pwma_operand_bank <= 1'b0;
            local_pwma_accumulate <= 1'b0;
            local_pwma_acc_we <= 1'b0;
            local_pwma_acc_load_bank <= 1'b0;
            local_pwma_acc_addr <= 7'd0;
            local_pwma_acc_pair <= 32'd0;
            local_pwma_operand_we <= 1'b0;
            local_pwma_operand_load_bank <= 1'b0;
            local_pwma_operand_addr <= 7'd0;
            local_pwma_operand_pair <= 32'd0;
            local_pwma_start <= 1'b0;
            local_pwma_use_tomont <= 1'b1;
            local_pwma_result_addr <= 7'd0;
            local_pwma_result_bank_fsm <= 1'b0;
            kg_poly_phase <= 4'd0;
            kg_mb_load_valid <= 1'b0;
            kg_mb_load_addr <= 7'd0;
            kg_mb_load_capture_valid <= 1'b0;
            kg_mb_load_capture_addr <= 7'd0;
            kg_transfer_valid <= 1'b0;
            kg_transfer_addr <= 7'd0;
            kg_transfer_capture_valid <= 1'b0;
            kg_transfer_capture_addr <= 7'd0;
            kg_gm_started <= 1'b0;
            kg_local_datapath_enable <= 1'b0;
            kg_a_cache_active <= 1'b0;
            kg_a_cache_done <= 1'b0;
            kg_a_source_done <= 1'b0;
            kg_a_cache_count <= 10'd0;
            dp_phase <= 5'd0;
            dp_local_pwma_enable <= 1'b0;
            dp_local_pwma_gm_source <= 1'b0;
            dp_local_pwma_ntt_source <= 1'b0;
            dp_mb_stream_valid <= 1'b0;
            dp_mb_stream_addr <= 7'd0;
            dp_mb_stream_capture_valid <= 1'b0;
            dp_mb_stream_capture_addr <= 7'd0;
        end else if ((ext_we || ext_re) && !ext_ready) begin
            
            
            
            
            
            
            ext_we    <= ext_we;
            ext_re    <= ext_re;
            ext_addr  <= ext_addr;
            ext_dout  <= ext_dout;
            ext_wstrb <= ext_wstrb;
        end else begin
            hash_start <= 0; cbd_start <= 0; ntt_start <= 0; cmp_start <= 0; cmp_finish <= 1'b0; gm_start <= 0;
            hash_in_stream_en <= 1'b0;
            if (hash_in_ready) hash_in_valid <= 1'b0;
            ext_we <= 0; ext_re <= 0; ext_wstrb <= 8'h01; fsm_ntt_we <= 0; fsm_ntt_we_b <= 0;
            ct_wide_we <= 1'b0; ct_wide_addr <= 11'd0; ct_wide_din <= 64'd0; ct_wide_wstrb <= 8'd0;
            ct_cmp_valid <= 1'b0;
            ct_pack_start <= 1'b0;
            kg_pack_start <= 1'b0;
            ct_unpack_start <= 1'b0;
            mb_rd_en <= 1'b0;
            mb_wr_en_c0 <= 1'b0;
            mb_wr_en_c1 <= 1'b0;
            local_pwma_acc_we <= 1'b0;
            local_pwma_operand_we <= 1'b0;
            local_pwma_start <= 1'b0;

            if (gm_pwma_stream_mode) begin
                if (gm_we) begin
                    gm_stream_fifo[gm_stream_wr_ptr] <= $signed(gm_ram_din);
                end
                if (gm_we_b) begin
                    gm_stream_fifo[gm_stream_wr_ptr_p1] <= $signed(gm_ram_din_b);
                end
                gm_stream_rd_ptr <= gm_stream_rd_ptr + gm_stream_pop_count[2:0];
                gm_stream_wr_ptr <= gm_stream_wr_ptr + gm_stream_push_count[2:0];
                gm_stream_count  <= gm_stream_count - gm_stream_pop_count + gm_stream_push_count;
            end else begin
                gm_stream_rd_ptr <= 3'd0;
                gm_stream_wr_ptr <= 3'd0;
                gm_stream_count  <= 4'd0;
            end

            if (gm_done && kg_gm_started)
                kg_a_source_done <= 1'b1;

            if (kg_a_cache_active && gm_stream_pair_consume) begin
                mb_wr_en_c0 <= 1'b1;
                mb_wr_en_c1 <= 1'b1;
                mb_wr_slot <= 3'd4 + kg_a_cache_count[8:7];
                mb_wr_pair_addr <= kg_a_cache_count[6:0];
                mb_wr_c0 <= gm_stream_pair_c0;
                mb_wr_c1 <= gm_stream_pair_c1;
                if (kg_a_cache_count == 10'd511) begin
                    kg_a_cache_active <= 1'b0;
                    kg_a_cache_done <= 1'b1;
                end else begin
                    kg_a_cache_count <= kg_a_cache_count + 10'd1;
                end
            end

            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        busy <= 1; dma_cnt <= 0; loop_i <= 0; loop_j <= 0;
                        
                        hash_sent <= 0; cbd_sent <= 0; ntt_sent <= 0; pwma_sent <= 0; gm_sent <= 0;
                        gm_bg_done <= 1'b0;
                        hash_fetching <= 1'b0;
                        fetch_wait <= 1'b0;
                        fetch_cnt <= 8'd0;
                        hash_in_valid <= 1'b0;
                        hash_in_last <= 1'b0;
                        hash_in_bytes <= 4'd0;
                        hash_in_data <= 64'd0;
                        ct_pack_sent <= 1'b0;
                        kg_pack_sent <= 1'b0;
                        pack_phase <= 2'd0; pack_step <= 3'd0;
                        pack_pk_addr <= PK_EXT_BASE; pack_sk_addr <= SK_EXT_BASE; pk_copy_word <= 64'd0;
                        cmp_start <= 1'b0;
                        cmp_finish <= 1'b0;
                        ct_cmp_valid <= 1'b0;
                        ct_cmp_prime_word <= 64'd0;
                        dec_reenc_mode <= 1'b0;
                                                dec_phase <= 4'd0;
                        ct_cap_idx <= 12'd0;
                        dec_j_idx <= 3'd0;
                        dec_sk_reload_done <= 1'b0;
                        dec_sk_poly <= 3'd0;
                        dec_sk_pair <= 8'd0;
                        dec_u0_direct_loaded <= 1'b0;
                        dec_u0_ntt_started <= 1'b0;
                        dec_u0_ntt_done <= 1'b0;
                        dec_unpack_done_latched <= 1'b0;
                        kg_poly_phase <= 4'd0;
                        kg_mb_load_valid <= 1'b0;
                        kg_mb_load_capture_valid <= 1'b0;
                        kg_transfer_valid <= 1'b0;
                        kg_transfer_capture_valid <= 1'b0;
                        kg_gm_started <= 1'b0;
                        kg_local_datapath_enable <= 1'b0;
                        kg_a_cache_active <= 1'b0;
                        kg_a_cache_done <= 1'b0;
                        kg_a_source_done <= 1'b0;
                        kg_a_cache_count <= 10'd0;
                        local_pwma_bank <= 1'b0;
                        local_pwma_operand_bank <= 1'b0;
                        local_pwma_acc_load_bank <= 1'b0;
                        local_pwma_operand_load_bank <= 1'b0;
                        local_pwma_result_bank_fsm <= 1'b0;
                        dp_phase <= 5'd0;
                        dp_local_pwma_enable <= 1'b0;
                        dp_local_pwma_gm_source <= 1'b0;
                        dp_local_pwma_ntt_source <= 1'b0;
                        dp_mb_stream_valid <= 1'b0;
                        dp_mb_stream_capture_valid <= 1'b0;
                        if      (opcode == 2'b01) state <= S_KG_LOAD_SEED;
                        else if (opcode == 2'b10) begin
                            pack_pk_addr <= PK_EXT_BASE;
                            dec_sk_reload_done <= 1'b0;
                            dec_sk_poly <= 3'd0;
                            dec_sk_pair <= 8'd0;
                            ext_addr <= PK_EXT_BASE;
                            state <= S_ENC_READ_PK;
                        end
                        else if (opcode == 2'b11) begin
                            pack_pk_addr <= SK_EXT_BASE;
                            dec_sk_reload_done <= 1'b0;
                            dec_sk_poly <= 3'd0;
                            dec_sk_pair <= 8'd0;
                            ext_addr <= SK_EXT_BASE;
                            state <= S_DEC_READ;
                        end
                    end else busy <= 0;
                end

                
                
                
                S_KG_LOAD_SEED: begin
                    
                    
                    if (seed_valid) begin
reg_z <= seed_in[255:0];
                        dma_cnt <= 12'd0;
                        state <= S_KG_HASH_G; hash_sent <= 0;
                    end
                end
                S_KG_HASH_G: begin
                    hash_cmd <= 3'd3;
                    hash_in_stream_en <= 1'b1;
                    if (!hash_sent) begin
                        hash_start <= 1;
                        hash_sent <= 1;
                        dma_cnt <= 12'd0;
                        hash_in_valid <= 1'b0;
                    end else if (!hash_in_valid && hash_in_ready && (dma_cnt < 12'd33)) begin
                        if (dma_cnt < 12'd32) begin
                            hash_in_data  <= bytes8_from_256_msb(seed_in[511:256], dma_cnt[4:0]);
                            hash_in_bytes <= 4'd8;
                            hash_in_last  <= 1'b0;
                            dma_cnt       <= dma_cnt + 12'd8;
                        end else begin
                            hash_in_data  <= {56'd0, {5'd0, KYBER_K}};
                            hash_in_bytes <= 4'd1;
                            hash_in_last  <= 1'b1;
                            dma_cnt       <= dma_cnt + 12'd1;
                        end
                        hash_in_valid <= 1'b1;
                    end
                    if (hash_done) begin
                        reg_rho <= flip_bytes_32(hash_dout[255:0]);
                        reg_sigma <= flip_bytes_32(hash_dout[511:256]);
                        loop_i <= 0; hash_sent <= 0; state <= S_KG_PRF_E;
                    end
                end

                
                
                
                S_KG_PRF_E: begin
                    hash_cmd <= 3'd1; hash_prf_eta3 <= ETA1_IS_3;
                    hash_in_stream_en <= 1'b1;
                    if (!hash_sent) begin
                        hash_start <= 1; hash_sent <= 1; dma_cnt <= 12'd0; hash_in_valid <= 1'b0;
                    end else if (!hash_in_valid && hash_in_ready && (dma_cnt < 12'd33)) begin
                        if (dma_cnt < 12'd32) begin
                            hash_in_data  <= bytes8_from_256_msb(reg_sigma, dma_cnt[4:0]);
                            hash_in_bytes <= 4'd8;
                            hash_in_last  <= 1'b0;
                            dma_cnt       <= dma_cnt + 12'd8;
                        end else begin
                            hash_in_data  <= {56'd0, {5'd0, loop_i + KYBER_K}};
                            hash_in_bytes <= 4'd1;
                            hash_in_last  <= 1'b1;
                            dma_cnt       <= dma_cnt + 12'd1;
                        end
                        hash_in_valid <= 1'b1;
                    end
                    if (hash_out_valid) begin cbd_sent <= 0; state <= S_KG_CBD_E; end
                end

                S_KG_CBD_E: begin
                    ntt_mux_sel <= 3'd1; cbd_base_addr <= 11'd0; cbd_eta3_mode <= ETA1_IS_3; 
                    if (!cbd_sent) begin cbd_start <= 1; cbd_sent <= 1; end
                    if (cbd_done) begin ntt_sent <= 0; state <= S_KG_NTT_E; end
                end

                S_KG_NTT_E: begin
                    ntt_mux_sel <= 3'd0; ntt_mode <= 0;
                    if ((loop_i == (KYBER_K - 3'd1)) &&
                        !kg_gm_started) begin
                        gm_transposed <= 1'b0;
                        gm_pwma_stream_mode <= 1'b1;
                        gm_start <= 1'b1;
                        gm_sent <= 1'b1;
                        kg_gm_started <= 1'b1;
                        kg_a_cache_active <= 1'b1;
                        kg_a_cache_done <= 1'b0;
                        kg_a_source_done <= 1'b0;
                        kg_a_cache_count <= 10'd0;
                    end
                    if (!ntt_sent) begin ntt_start <= 1; ntt_sent <= 1; end
                    if (ntt_done) begin dma_cnt <= 0; state <= S_KG_DMA_E; end
                end

                S_KG_DMA_E: begin
                    mux_sel <= 3'd0; ntt_mux_sel <= 3'd0;
                    fsm_ntt_addr <= {dma_cnt[6:0], 1'b0};
                    fsm_ntt_addr_b <= {dma_cnt[6:0], 1'b0} + 8'd1;
                    if (dma_cnt > 2) begin
                        mb_wr_en_c0 <= 1'b1;
                        mb_wr_en_c1 <= 1'b1;
                        mb_wr_slot <= loop_i;
                        mb_wr_pair_addr <= dma_cnt[6:0] - 7'd3;
                        mb_wr_c0 <= ntt_ext_dout;
                        mb_wr_c1 <= ntt_ext_dout_b;
                        local_pwma_acc_we <= 1'b1;
                        local_pwma_acc_load_bank <= loop_i[0];
                        local_pwma_acc_addr <= dma_cnt[6:0] - 7'd3;
                        local_pwma_acc_pair <= {
                            4'd0, canonical_modq12(ntt_ext_dout_b),
                            4'd0, canonical_modq12(ntt_ext_dout)
                        };
                    end
                    if (dma_cnt == 12'd130) begin
                        dma_cnt <= 0;
                        if (loop_i == (KYBER_K - 3'd1)) begin
                            loop_i <= 0;
                            loop_j <= 0;
                            state  <= S_KG_GEN_A;
                        end else begin
                            loop_i    <= loop_i + 1;
                            hash_sent <= 0;
                            state     <= S_KG_PRF_E;
                        end
                    end else dma_cnt <= dma_cnt + 1;
                end

                
                
                
                S_KG_PRF_S: begin
                    hash_cmd <= 3'd1; hash_prf_eta3 <= ETA1_IS_3;
                    hash_in_stream_en <= 1'b1;
                    if (!hash_sent) begin
                        hash_start <= 1; hash_sent <= 1; dma_cnt <= 12'd0; hash_in_valid <= 1'b0;
                    end else if (!hash_in_valid && hash_in_ready && (dma_cnt < 12'd33)) begin
                        if (dma_cnt < 12'd32) begin
                            hash_in_data  <= bytes8_from_256_msb(reg_sigma, dma_cnt[4:0]);
                            hash_in_bytes <= 4'd8;
                            hash_in_last  <= 1'b0;
                            dma_cnt       <= dma_cnt + 12'd8;
                        end else begin
                            hash_in_data  <= {56'd0, {5'd0, loop_j}};
                            hash_in_bytes <= 4'd1;
                            hash_in_last  <= 1'b1;
                            dma_cnt       <= dma_cnt + 12'd1;
                        end
                        hash_in_valid <= 1'b1;
                    end
                    if (hash_out_valid) begin cbd_sent <= 0; state <= S_KG_CBD_S; end
                end

                S_KG_CBD_S: begin
                    ntt_mux_sel <= 3'd1; cbd_base_addr <= 11'd0; cbd_eta3_mode <= ETA1_IS_3;
                    if (!cbd_sent) begin cbd_start <= 1; cbd_sent <= 1; end
                    if (cbd_done) begin ntt_sent <= 0; state <= S_KG_NTT_S; end
                end

                S_KG_NTT_S: begin
                    ntt_mux_sel <= 3'd0; ntt_mode <= 0;
                    if (!ntt_sent) begin ntt_start <= 1; ntt_sent <= 1; end
                    if (ntt_done) begin dma_cnt <= 0; state <= S_KG_DMA_S; end
                end

                S_KG_DMA_S: begin
                    mux_sel <= 3'd0; ntt_mux_sel <= 3'd0;
                    fsm_ntt_addr <= {dma_cnt[6:0], 1'b0};
                    fsm_ntt_addr_b <= {dma_cnt[6:0], 1'b0} + 8'd1;
                    if (dma_cnt > 2) begin
                        mb_wr_en_c0 <= 1'b1;
                        mb_wr_en_c1 <= 1'b1;
                        mb_wr_slot <= 3'd2 + loop_j;
                        mb_wr_pair_addr <= dma_cnt[6:0] - 7'd3;
                        mb_wr_c0 <= ntt_ext_dout;
                        mb_wr_c1 <= ntt_ext_dout_b;
                        local_pwma_operand_we <= 1'b1;
                        local_pwma_operand_load_bank <= loop_j[0];
                        local_pwma_operand_addr <= dma_cnt[6:0] - 7'd3;
                        local_pwma_operand_pair <= {
                            ntt_ext_dout_b, ntt_ext_dout
                        };
                    end
                    if (dma_cnt == 12'd130) begin
                        dma_cnt <= 0;
                        if (loop_j == (KYBER_K - 3'd1)) begin
                            loop_i <= 0;
                            loop_j <= 0;
                            pwma_sent <= 0;
                            gm_sent <= 0;
                            kg_poly_phase <= 4'd0;
                            kg_gm_started <= 1'b0;
                            kg_local_datapath_enable <= 1'b1;
                            state <= S_KG_PWMA_A_S;
                        end else begin
                            loop_j <= loop_j + 1'b1;
                            hash_sent <= 1'b0;
                            state <= S_KG_PRF_S;
                        end
                    end else dma_cnt <= dma_cnt + 1;
                end

                
                
                
                S_KG_GEN_A: begin
                    gm_transposed <= 1'b0;
                    gm_pwma_stream_mode <= 1'b1;
                    if (!kg_gm_started) begin
                        gm_start <= 1'b1;
                        gm_sent <= 1'b1;
                        kg_gm_started <= 1'b1;
                        kg_a_cache_active <= 1'b1;
                        kg_a_cache_done <= 1'b0;
                        kg_a_source_done <= 1'b0;
                        kg_a_cache_count <= 10'd0;
                    end
                    if (kg_a_cache_done && kg_a_source_done) begin
                        gm_sent <= 1'b0;
                        gm_pwma_stream_mode <= 1'b0;
                        loop_j    <= 0;          
                        loop_i    <= 0;
                        hash_sent <= 0;
                        state     <= S_KG_PRF_S; 
                    end
                end

                
                
                
                
                
                

                
                
                
                
                
                    
                
                
                
                
                
                
                

                S_KG_PWMA_A_S: begin
                    mux_sel <= 3'd0;
                    ntt_mux_sel <= 3'd0;
                    local_pwma_use_tomont <= 1'b1;
                    local_pwma_bank <= loop_i[0];
                    local_pwma_operand_bank <= loop_j[0];
                    local_pwma_accumulate <= 1'b1;
                    local_pwma_result_bank_fsm <= loop_i[0];
                    local_pwma_operand_load_bank <= loop_j[0];

                    case (kg_poly_phase)
                        4'd0: begin
                            dma_cnt <= 12'd0;
                            kg_mb_load_valid <= 1'b0;
                            kg_mb_load_capture_valid <= 1'b0;
                            kg_transfer_valid <= 1'b0;
                            kg_transfer_capture_valid <= 1'b0;
                            pwma_sent <= 1'b0;
                            loop_j <= 3'd0;
                            dp_mb_stream_valid <= 1'b0;
                            dp_mb_stream_capture_valid <= 1'b0;
                            kg_poly_phase <= 4'd3;
                        end

                        4'd3: begin
                            if (!pwma_sent) begin
                                local_pwma_start <= 1'b1;
                                pwma_sent <= 1'b1;
                            end

                            dp_mb_stream_capture_valid <= dp_mb_stream_valid;
                            dp_mb_stream_capture_addr <= dp_mb_stream_addr;
                            if (dma_cnt < 12'd128) begin
                                mb_rd_en <= 1'b1;
                                mb_rd_slot <=
                                    3'd4 + (loop_i * KYBER_K) + loop_j;
                                mb_rd_pair_addr <= dma_cnt[6:0];
                                dp_mb_stream_valid <= 1'b1;
                                dp_mb_stream_addr <= dma_cnt[6:0];
                                dma_cnt <= dma_cnt + 12'd1;
                            end else begin
                                dp_mb_stream_valid <= 1'b0;
                            end

                            if (local_pwma_done) begin
                                pwma_sent <= 1'b0;
                                dp_mb_stream_valid <= 1'b0;
                                dp_mb_stream_capture_valid <= 1'b0;
                                if (loop_j == (KYBER_K - 3'd1)) begin
                                    if (loop_i == (KYBER_K - 3'd1)) begin
                                        kg_local_datapath_enable <= 1'b0;
                                        kg_pack_sent <= 1'b0;
                                        kg_poly_phase <= 4'd0;
                                        state <= S_KG_PACK;
                                    end else begin
                                        loop_i <= loop_i + 1'b1;
                                        loop_j <= 3'd0;
                                        dma_cnt <= 12'd0;
                                        kg_mb_load_valid <= 1'b0;
                                        kg_mb_load_capture_valid <= 1'b0;
                                        kg_poly_phase <= 4'd0;
                                    end
                                end else begin
                                    loop_j <= loop_j + 1'b1;
                                    dma_cnt <= 12'd0;
                                    kg_poly_phase <= 4'd3;
                                end
                            end
                        end

                        default: kg_poly_phase <= 4'd0;
                    endcase
                end

                
                
                
                S_KG_HASH_PK: begin
                    hash_cmd <= 3'd2;
                    hash_in_stream_en <= 1'b1;
                    if (!hash_sent) begin
                        hash_sent <= 1'b1;
                        hash_start <= 1'b1;
                        dma_cnt <= 12'd0;
                        hash_fetching <= 1'b0;
                        fetch_wait <= 1'b0;
                        fetch_cnt <= 8'd0;
                        hash_in_valid <= 1'b0;
                    end else begin
                        if (!hash_in_valid && hash_in_ready && (dma_cnt < PK_BYTES_TOTAL)) begin
                            if (!hash_fetching) begin
                                ext_re <= 1'b1;
                                ext_addr <= PK_EXT_BASE + {20'd0, dma_cnt};
                                hash_fetching <= 1'b1;
                            end else begin
                                ext_re <= 1'b1;
                                ext_addr <= PK_EXT_BASE + {20'd0, dma_cnt};
                                if (ext_ready) begin
                                    rem12 = PK_BYTES_TOTAL - dma_cnt;
                                    hash_in_data  <= ext_din;
                                    hash_in_bytes <= (rem12 >= 12'd8) ? 4'd8 : rem12[3:0];
                                    hash_in_last  <= (rem12 <= 12'd8);
                                    hash_in_valid <= 1'b1;
                                    hash_fetching <= 1'b0;
                                    dma_cnt       <= dma_cnt + ((rem12 >= 12'd8) ? 12'd8 : rem12);
                                end
                            end
                        end
                        if (hash_done) begin
                            reg_H_pk <= flip_bytes_32(hash_dout[255:0]);
                            hash_sent <= 1'b0;
                            hash_fetching <= 1'b0;
                            fetch_wait <= 1'b0;
                            hash_in_valid <= 1'b0;
                            if (opcode == 2'b10) begin
                                state <= S_ENC_LOAD_COINS;
                                
                            end else begin
                                state <= S_KG_WRITE_REST;
                                pack_phase <= 2'd0;
                                pack_step  <= 3'd0;
                                dma_cnt <= 12'd0;
                                
                            end
                        end
                    end
                end

                S_KG_WRITE_REST: begin
                    // Wide SK tail writer:
                    //   phase 0: copy PK (800 B) from external PK to SK in 64-bit beats.
                    //   phase 1: write H(pk) (32 B) in 64-bit beats.
                    //   phase 2: write z     (32 B) in 64-bit beats.
                    ext_wstrb <= 8'hFF;

                    if (pack_phase == 2'd0) begin
                        case (pack_step)
                            3'd0: begin
                                ext_re   <= 1'b1;
                                ext_addr <= PK_EXT_BASE + {20'd0, dma_cnt};
                                pack_step <= 3'd1;
                            end
                            3'd1: begin
                                ext_re   <= !ext_ready;
                                ext_addr <= PK_EXT_BASE + {20'd0, dma_cnt};
                                if (ext_ready) begin
                                    pk_copy_word <= ext_din;
                                    pack_step <= 3'd2;
                                end
                            end
                            default: begin
                                ext_we   <= 1'b1;
                                ext_addr <= pack_sk_addr + {20'd0, dma_cnt};
                                ext_dout <= pk_copy_word;

                                if (ext_ready) begin
                                    if (dma_cnt + 12'd8 >= PK_BYTES_TOTAL) begin
                                        pack_phase <= 2'd1;
                                        pack_step  <= 3'd0;
                                        dma_cnt    <= 12'd0;
                                    end else begin
                                        dma_cnt   <= dma_cnt + 12'd8;
                                        pack_step <= 3'd0;
                                    end
                                end
                            end
                        endcase
                    end else if (pack_phase == 2'd1) begin
                        ext_we   <= 1'b1;
                        ext_addr <= pack_sk_addr + {20'd0, PK_BYTES_TOTAL} + {20'd0, dma_cnt};
                        ext_dout <= bytes8_from_256_msb(reg_H_pk, dma_cnt[4:0]);

                        if (ext_ready) begin
                            if (dma_cnt == 12'd24) begin
                                pack_phase <= 2'd2;
                                dma_cnt <= 12'd0;
                            end else begin
                                dma_cnt <= dma_cnt + 12'd8;
                            end
                        end
                    end else begin
                        ext_we   <= 1'b1;
                        ext_addr <= pack_sk_addr + {20'd0, PK_BYTES_TOTAL} + 32'd32 + {20'd0, dma_cnt};
                        ext_dout <= bytes8_from_256_msb(reg_z, dma_cnt[4:0]);

                        if (ext_ready) begin
                            if (dma_cnt == 12'd24) begin
                                state <= S_IDLE;
                                done <= 1'b1;
                                dma_cnt <= 12'd0;
                            end else begin
                                dma_cnt <= dma_cnt + 12'd8;
                            end
                        end
                    end
                end

                S_KG_PACK: begin
                    mux_sel <= 3'd4;

                    if (!kg_pack_sent) begin
                        kg_pack_start <= 1'b1;
                        kg_pack_sent  <= 1'b1;
                    end

                    ext_we    <= kg_pack_ext_we;
                    ext_wstrb <= kg_pack_ext_wstrb;
                    ext_addr  <= kg_pack_ext_addr;
                    ext_dout  <= kg_pack_ext_dout;

                    if (kg_pack_done) begin
                        kg_pack_sent <= 1'b0;
                        hash_sent <= 1'b0;
                        pack_sk_addr <= SK_EXT_BASE + 32'd768;
                        state <= S_KG_HASH_PK;
                    end
                end

                S_ENC_LOAD_COINS: begin
                    
                    if (seed_valid) begin
                        
                        reg_m <= seed_in[511:256];
                        hash_sent <= 1'b0;
                        state <= S_ENC_PRF_R;
                    end
                end

                
                S_ENC_PRF_R: begin
                    hash_cmd   <= 3'd3;
                    hash_in_stream_en <= 1'b1;
                    if (!hash_sent) begin
                        hash_start <= 1'b1;
                        hash_sent  <= 1'b1;
                        dma_cnt    <= 12'd0;
                        hash_in_valid <= 1'b0;
                    end else if (!hash_in_valid && hash_in_ready && (dma_cnt < 12'd64)) begin
                        if (dma_cnt < 12'd32)
                            hash_in_data <= bytes8_from_256_msb(reg_m, dma_cnt[4:0]);
                        else
                            hash_in_data <= bytes8_from_256_msb(reg_H_pk, dma_cnt[4:0]);
                        hash_in_bytes <= 4'd8;
                        hash_in_last  <= (dma_cnt == 12'd56);
                        hash_in_valid <= 1'b1;
                        dma_cnt       <= dma_cnt + 12'd8;
                    end
                    if (hash_done) begin
                        reg_K_bar  <= flip_bytes_32(hash_dout[255:0]);   
                        reg_r_seed <= flip_bytes_32(hash_dout[511:256]); 
                        hash_sent  <= 1'b0;
                        cbd_sent   <= 1'b0;
                        ntt_sent   <= 1'b0;
                        loop_j     <= 3'd0;
                        enc_noise_kind <= 2'd0; 
                        dma_cnt    <= 12'd0;
                        state      <= S_ENC_CBD_R;
                    end
                end

                
                

                
                
                S_ENC_CBD_R: begin
                    ntt_mux_sel <= (enc_noise_kind == 2'd0) ? 3'd1 : 3'd0;
                    mux_sel <= 3'd0;
                    
                    if (cbd_we) begin
                        mb_wr_en_c0 <= 1'b1;
                        if (cbd_we_b)
                            mb_wr_en_c1 <= 1'b1;
                        if (enc_noise_kind == 2'd0)
                            mb_wr_slot <= 3'd2 + loop_j;
                        else if (enc_noise_kind == 2'd1)
                            mb_wr_slot <= 3'd4 + loop_j;
                        else
                            mb_wr_slot <= 3'd6;
                        mb_wr_pair_addr <= cbd_ram_addr[7:1];
                        mb_wr_c0 <= cbd_poly_out;
                        if (cbd_we_b)
                            mb_wr_c1 <= cbd_poly_out_b;
                    end

                    if (!hash_sent) begin
                        hash_cmd <= 3'd1;
                        hash_in_stream_en <= 1'b1;
                        hash_prf_eta3 <= (enc_noise_kind == 2'd0) ? ETA1_IS_3 : 1'b0;
                        hash_start <= 1'b1;
                        hash_sent  <= 1'b1;
                        dma_cnt    <= 12'd0;
                        hash_in_valid <= 1'b0;
                    end else begin
                        hash_in_stream_en <= 1'b1;
                        if (!hash_in_valid && hash_in_ready && (dma_cnt < 12'd33)) begin
                            if (dma_cnt < 12'd32) begin
                                hash_in_data  <= bytes8_from_256_msb(reg_r_seed, dma_cnt[4:0]);
                                hash_in_bytes <= 4'd8;
                                hash_in_last  <= 1'b0;
                                dma_cnt       <= dma_cnt + 12'd8;
                            end else begin
                                if (enc_noise_kind == 2'd0)
                                    hash_in_data <= {56'd0, {5'd0, loop_j}};
                                else if (enc_noise_kind == 2'd1)
                                    hash_in_data <= {56'd0, {5'd0, KYBER_K + loop_j}};
                                else
                                    hash_in_data <= {56'd0, ({5'd0, KYBER_K} + {5'd0, KYBER_K})};
                                hash_in_bytes <= 4'd1;
                                hash_in_last  <= 1'b1;
                                hash_in_valid <= 1'b1;
                                dma_cnt       <= dma_cnt + 12'd1;
                            end
                            hash_in_valid <= 1'b1;
                        end
                    end

                    if (hash_sent && hash_out_valid && !cbd_sent) begin
                        cbd_base_addr <= 11'd0;
                        cbd_eta3_mode <= (enc_noise_kind == 2'd0) ? ETA1_IS_3 : 1'b0;
                        cbd_start <= 1'b1;
                        cbd_sent <= 1'b1;
                    end else if (cbd_done) begin
                        hash_sent <= 1'b0;
                        cbd_sent <= 1'b0;
                        if (enc_noise_kind == 2'd0) begin
                            
                            enc_ntt_phase <= 2'd0;
                            dma_cnt <= 12'd0;
                            ntt_sent <= 1'b0;
                            kg_mb_load_valid <= 1'b0;
                            kg_mb_load_capture_valid <= 1'b0;
                            state <= S_ENC_NTT_R;
                        end else if (enc_noise_kind == 2'd1) begin
                            if (loop_j + 3'd1 == KYBER_K) begin
                                loop_j <= 3'd0;
                                enc_noise_kind <= 2'd2; 
                            end else begin
                                loop_j <= loop_j + 3'd1;
                            end
                        end else begin
                            
                            loop_i <= 3'd0;
                            loop_j <= 3'd0;
                            dma_cnt <= 12'd0;
                            enc_ntt_phase <= 2'd0; 
                            dp_phase <= 5'd0;
                            dp_local_pwma_enable <= 1'b0;
                            dp_local_pwma_gm_source <= 1'b1;
                            gm_sent <= 1'b0;
                            state <= S_ENC_PWMA_U;
                        end
                    end
                end

                
                S_ENC_NTT_R: begin
                    ntt_mux_sel <= 3'd0;
                    mux_sel <= 3'd0;
                    if (enc_ntt_phase == 2'd0) begin
                        dma_cnt <= 12'd0;
                        enc_ntt_phase <= 2'd1;
                    end else if (enc_ntt_phase == 2'd1) begin
                        
                        ntt_mode <= 1'b0;
                        if (!ntt_sent) begin
                            ntt_start <= 1'b1;
                            ntt_sent <= 1'b1;
                        end
                        if (ntt_done) begin
                            ntt_sent <= 1'b0;
                            dma_cnt <= 12'd0;
                            enc_ntt_phase <= 2'd2;
                        end
                    end else begin
                        fsm_ntt_addr <= {dma_cnt[6:0], 1'b0};
                        fsm_ntt_addr_b <= {dma_cnt[6:0], 1'b0} + 8'd1;
                        if (dma_cnt > 2) begin
                            mb_wr_en_c0 <= 1'b1;
                            mb_wr_en_c1 <= 1'b1;
                            mb_wr_slot <= 3'd2 + loop_j;
                            mb_wr_pair_addr <= dma_cnt[6:0] - 7'd3;
                            mb_wr_c0 <= ntt_ext_dout;
                            mb_wr_c1 <= ntt_ext_dout_b;
                            local_pwma_operand_we <= 1'b1;
                            local_pwma_operand_load_bank <= loop_j[0];
                            local_pwma_operand_addr <=
                                dma_cnt[6:0] - 7'd3;
                            local_pwma_operand_pair <= {
                                ntt_ext_dout_b, ntt_ext_dout
                            };
                        end
                        if (dma_cnt == 12'd130) begin
                            dma_cnt <= 12'd0;
                            kg_mb_load_valid <= 1'b0;
                            kg_mb_load_capture_valid <= 1'b0;
                            if (loop_j + 3'd1 == KYBER_K) begin
                                loop_j <= 3'd0;
                                enc_noise_kind <= 2'd1; 
                            end else begin
                                loop_j <= loop_j + 3'd1;
                            end
                            state <= S_ENC_CBD_R;
                        end else begin
                            dma_cnt <= dma_cnt + 12'd1;
                        end
                    end
                end

                
                S_ENC_PWMA_U: begin
                    mux_sel <= 3'd0;
                    ntt_mux_sel <= 3'd0;
                    gm_transposed <= 1'b1;
                    gm_pwma_stream_mode <= 1'b1;
                    local_pwma_use_tomont <= 1'b0;
                    local_pwma_operand_bank <= loop_j[0];
                    local_pwma_accumulate <= (loop_j != 3'd0);
                    dp_local_pwma_gm_source <= 1'b1;
                    dp_local_pwma_ntt_source <= 1'b0;

                    if (gm_done)
                        gm_pwma_stream_done <= 1'b1;

                    case (dp_phase)
                        5'd0: begin
                            dp_local_pwma_enable <= 1'b1;
                            dma_cnt <= 12'd0;
                            loop_j <= 3'd0;
                            kg_mb_load_valid <= 1'b0;
                            kg_mb_load_capture_valid <= 1'b0;
                            pwma_sent <= 1'b0;
                            if (!gm_sent) begin
                                gm_start <= 1'b1;
                                gm_sent <= 1'b1;
                                gm_pwma_stream_done <= 1'b0;
                            end
                            dp_phase <= 5'd3;
                        end

                        5'd1: begin
                            dp_phase <= 5'd3;
                        end

                        5'd2: begin
                            if (kg_mb_load_capture_valid) begin
                                local_pwma_operand_we <= 1'b1;
                                local_pwma_operand_addr <=
                                    kg_mb_load_capture_addr;
                                local_pwma_operand_pair <= {mb_rd_c1, mb_rd_c0};
                            end
                            kg_mb_load_capture_valid <= kg_mb_load_valid;
                            kg_mb_load_capture_addr <= kg_mb_load_addr;

                            if (dma_cnt < 12'd128) begin
                                mb_rd_en <= 1'b1;
                                mb_rd_slot <= 3'd2 + loop_j;
                                mb_rd_pair_addr <= dma_cnt[6:0];
                                kg_mb_load_valid <= 1'b1;
                                kg_mb_load_addr <= dma_cnt[6:0];
                                dma_cnt <= dma_cnt + 12'd1;
                            end else begin
                                kg_mb_load_valid <= 1'b0;
                                if (!kg_mb_load_valid &&
                                    !kg_mb_load_capture_valid) begin
                                    if (dma_cnt == 12'd128)
                                        dma_cnt <= 12'd129;
                                    else begin
                                        dma_cnt <= 12'd0;
                                        pwma_sent <= 1'b0;
                                        dp_phase <= 5'd3;
                                    end
                                end
                            end
                        end

                        5'd3: begin
                            if (!pwma_sent) begin
                                local_pwma_start <= 1'b1;
                                pwma_sent <= 1'b1;
                            end
                            if (local_pwma_done) begin
                                pwma_sent <= 1'b0;
                                if (loop_j + 3'd1 == KYBER_K) begin
                                    dma_cnt <= 12'd0;
                                    kg_transfer_valid <= 1'b0;
                                    kg_transfer_capture_valid <= 1'b0;
                                    dp_phase <= 5'd4;
                                end else begin
                                    loop_j <= loop_j + 3'd1;
                                    dma_cnt <= 12'd0;
                                    pwma_sent <= 1'b0;
                                    dp_phase <= 5'd3;
                                end
                            end
                        end

                        5'd4: begin
                            if (kg_transfer_capture_valid) begin
                                fsm_ntt_we <= 1'b1;
                                fsm_ntt_we_b <= 1'b1;
                                fsm_ntt_addr <=
                                    {kg_transfer_capture_addr, 1'b0};
                                fsm_ntt_addr_b <=
                                    {kg_transfer_capture_addr, 1'b0} + 8'd1;
                                fsm_ntt_din <=
                                    local_pwma_result_pair[15:0];
                                fsm_ntt_din_b <=
                                    local_pwma_result_pair[31:16];
                            end
                            kg_transfer_capture_valid <= kg_transfer_valid;
                            kg_transfer_capture_addr <= kg_transfer_addr;

                            if (dma_cnt < 12'd128) begin
                                local_pwma_result_addr <= dma_cnt[6:0];
                                kg_transfer_valid <= 1'b1;
                                kg_transfer_addr <= dma_cnt[6:0];
                                dma_cnt <= dma_cnt + 12'd1;
                            end else begin
                                kg_transfer_valid <= 1'b0;
                                if (!kg_transfer_valid &&
                                    !kg_transfer_capture_valid) begin
                                    if (dma_cnt == 12'd128)
                                        dma_cnt <= 12'd129;
                                    else begin
                                        dp_local_pwma_enable <= 1'b0;
                                        dma_cnt <= 12'd0;
                                        enc_ntt_phase <= 2'd1;
                                        ntt_sent <= 1'b0;
                                        dp_phase <= 5'd0;
                                        state <= S_ENC_INTT_U;
                                    end
                                end
                            end
                        end

                        default: dp_phase <= 5'd0;
                    endcase
                end

                
                S_ENC_INTT_U: begin
                    ntt_mux_sel <= 3'd0;
                    mux_sel <= 3'd0;
                    if (enc_ntt_phase == 2'd1) begin
                        ntt_mode <= 1'b1;
                        if (!ntt_sent) begin
                            ntt_start <= 1'b1;
                            ntt_sent <= 1'b1;
                        end
                        if (ntt_done) begin
                            ntt_sent <= 1'b0;
                            dma_cnt <= 12'd0;
                            enc_ntt_phase <= 2'd2;
                        end
                    end else if (enc_ntt_phase == 2'd2) begin
                        if (dma_cnt == 12'd128)
                            fsm_ntt_addr <= 8'd252;
                        else if (dma_cnt > 12'd128)
                            fsm_ntt_addr <= 8'd254;
                        else
                            fsm_ntt_addr <= {dma_cnt[6:0], 1'b0};

                        if ((dma_cnt >= 12'd3) &&
                            (dma_cnt < 12'd131)) begin
                            mb_rd_en <= 1'b1;
                            mb_rd_slot <= 3'd4 + loop_i;
                            mb_rd_pair_addr <= dma_cnt[6:0] - 7'd3;
                        end

                        if (dma_cnt > 4) begin
                            mb_wr_en_c0 <= 1'b1;
                            mb_wr_en_c1 <= 1'b1;
                            mb_wr_slot <= 3'd4 + loop_i;
                            mb_wr_pair_addr <= dma_cnt[6:0] - 7'd5;
                            mb_wr_c0 <= {4'd0, direct_addsub_result[11:0]};
                            mb_wr_c1 <= {4'd0, direct_addsub_result[23:12]};
                        end
                        if (dma_cnt == 12'd132) begin
                            dma_cnt <= 12'd0;
                            enc_ntt_phase <= 2'd0;
                            loop_j <= 3'd0;
                            dp_phase <= 5'd0;
                            if (loop_i + 3'd1 == KYBER_K) begin
                                loop_i <= 3'd0;
                                gm_pwma_stream_mode <= 1'b0;
                                gm_transposed <= 1'b0;
                                gm_sent <= 1'b0;
                                state <= S_ENC_PWMA_V;
                            end else begin
                                loop_i <= loop_i + 3'd1;
                                state <= S_ENC_PWMA_U;
                            end
                        end else begin
                            dma_cnt <= dma_cnt + 12'd1;
                        end
                    end
                end

                
                S_ENC_PWMA_V: begin
                    mux_sel <= 3'd0;
                    ntt_mux_sel <= 3'd0;
                    local_pwma_use_tomont <= 1'b0;
                    local_pwma_operand_bank <= loop_j[0];
                    local_pwma_accumulate <= (loop_j != 3'd0);
                    dp_local_pwma_gm_source <= 1'b0;
                    dp_local_pwma_ntt_source <= 1'b0;

                    case (dp_phase)
                        5'd0: begin
                            dp_local_pwma_enable <= 1'b1;
                            loop_j <= 3'd0;
                            dma_cnt <= 12'd0;
                            kg_mb_load_valid <= 1'b0;
                            kg_mb_load_capture_valid <= 1'b0;
                            dp_mb_stream_valid <= 1'b0;
                            dp_mb_stream_capture_valid <= 1'b0;
                            pwma_sent <= 1'b0;
                            dp_phase <= 5'd3;
                        end

                        5'd1: begin
                            dp_phase <= 5'd3;
                        end

                        5'd2: begin
                            if (kg_mb_load_capture_valid) begin
                                local_pwma_operand_we <= 1'b1;
                                local_pwma_operand_addr <=
                                    kg_mb_load_capture_addr;
                                local_pwma_operand_pair <= {mb_rd_c1, mb_rd_c0};
                            end
                            kg_mb_load_capture_valid <= kg_mb_load_valid;
                            kg_mb_load_capture_addr <= kg_mb_load_addr;

                            if (dma_cnt < 12'd128) begin
                                mb_rd_en <= 1'b1;
                                mb_rd_slot <= 3'd2 + loop_j;
                                mb_rd_pair_addr <= dma_cnt[6:0];
                                kg_mb_load_valid <= 1'b1;
                                kg_mb_load_addr <= dma_cnt[6:0];
                                dma_cnt <= dma_cnt + 12'd1;
                            end else begin
                                kg_mb_load_valid <= 1'b0;
                                if (!kg_mb_load_valid &&
                                    !kg_mb_load_capture_valid) begin
                                    if (dma_cnt == 12'd128)
                                        dma_cnt <= 12'd129;
                                    else begin
                                        dma_cnt <= 12'd0;
                                        dp_mb_stream_valid <= 1'b0;
                                        dp_mb_stream_capture_valid <= 1'b0;
                                        pwma_sent <= 1'b0;
                                        dp_phase <= 5'd3;
                                    end
                                end
                            end
                        end

                        5'd3: begin
                            if (!pwma_sent) begin
                                local_pwma_start <= 1'b1;
                                pwma_sent <= 1'b1;
                            end

                            dp_mb_stream_capture_valid <= dp_mb_stream_valid;
                            dp_mb_stream_capture_addr <= dp_mb_stream_addr;
                            if (dma_cnt < 12'd128) begin
                                mb_rd_en <= 1'b1;
                                mb_rd_slot <= loop_j;
                                mb_rd_pair_addr <= dma_cnt[6:0];
                                dp_mb_stream_valid <= 1'b1;
                                dp_mb_stream_addr <= dma_cnt[6:0];
                                dma_cnt <= dma_cnt + 12'd1;
                            end else begin
                                dp_mb_stream_valid <= 1'b0;
                            end

                            if (local_pwma_done) begin
                                pwma_sent <= 1'b0;
                                dp_mb_stream_valid <= 1'b0;
                                dp_mb_stream_capture_valid <= 1'b0;
                                if (loop_j + 3'd1 == KYBER_K) begin
                                    dma_cnt <= 12'd0;
                                    kg_transfer_valid <= 1'b0;
                                    kg_transfer_capture_valid <= 1'b0;
                                    dp_phase <= 5'd4;
                                end else begin
                                    loop_j <= loop_j + 3'd1;
                                    dma_cnt <= 12'd0;
                                    dp_mb_stream_valid <= 1'b0;
                                    dp_mb_stream_capture_valid <= 1'b0;
                                    pwma_sent <= 1'b0;
                                    dp_phase <= 5'd3;
                                end
                            end
                        end

                        5'd4: begin
                            if (kg_transfer_capture_valid) begin
                                fsm_ntt_we <= 1'b1;
                                fsm_ntt_we_b <= 1'b1;
                                fsm_ntt_addr <=
                                    {kg_transfer_capture_addr, 1'b0};
                                fsm_ntt_addr_b <=
                                    {kg_transfer_capture_addr, 1'b0} + 8'd1;
                                fsm_ntt_din <=
                                    local_pwma_result_pair[15:0];
                                fsm_ntt_din_b <=
                                    local_pwma_result_pair[31:16];
                            end
                            kg_transfer_capture_valid <= kg_transfer_valid;
                            kg_transfer_capture_addr <= kg_transfer_addr;

                            if (dma_cnt < 12'd128) begin
                                local_pwma_result_addr <= dma_cnt[6:0];
                                kg_transfer_valid <= 1'b1;
                                kg_transfer_addr <= dma_cnt[6:0];
                                dma_cnt <= dma_cnt + 12'd1;
                            end else begin
                                kg_transfer_valid <= 1'b0;
                                if (!kg_transfer_valid &&
                                    !kg_transfer_capture_valid) begin
                                    if (dma_cnt == 12'd128)
                                        dma_cnt <= 12'd129;
                                    else begin
                                        dp_local_pwma_enable <= 1'b0;
                                        dma_cnt <= 12'd0;
                                        enc_ntt_phase <= 2'd1;
                                        ntt_sent <= 1'b0;
                                        dp_phase <= 5'd0;
                                        state <= S_ENC_INTT_V;
                                    end
                                end
                            end
                        end

                        default: dp_phase <= 5'd0;
                    endcase
                end

                
                S_ENC_INTT_V: begin
                    ntt_mux_sel <= 3'd0;
                    mux_sel <= 3'd0;
                    if (enc_ntt_phase == 2'd1) begin
                        ntt_mode <= 1'b1;
                        if (!ntt_sent) begin
                            ntt_start <= 1'b1;
                            ntt_sent <= 1'b1;
                        end
                        if (ntt_done) begin
                            ntt_sent <= 1'b0;
                            dma_cnt <= 12'd0;
                            enc_ntt_phase <= 2'd2;
                        end
                    end else if (enc_ntt_phase == 2'd2) begin
                        if (dma_cnt == 12'd128)
                            fsm_ntt_addr <= 8'd252;
                        else if (dma_cnt > 12'd128)
                            fsm_ntt_addr <= 8'd254;
                        else
                            fsm_ntt_addr <= {dma_cnt[6:0], 1'b0};

                        if ((dma_cnt >= 12'd3) &&
                            (dma_cnt < 12'd131)) begin
                            mb_rd_en <= 1'b1;
                            mb_rd_slot <= 3'd6;
                            mb_rd_pair_addr <= dma_cnt[6:0] - 7'd3;
                        end

                        if (dma_cnt > 4) begin
                            mb_wr_en_c0 <= 1'b1;
                            mb_wr_en_c1 <= 1'b1;
                            mb_wr_slot <= 3'd6;
                            mb_wr_pair_addr <= dma_cnt[6:0] - 7'd5;
                            mb_wr_c0 <= {4'd0, direct_addsub_result[11:0]};
                            mb_wr_c1 <= {4'd0, direct_addsub_result[23:12]};
                        end
                        if (dma_cnt == 12'd132) begin
                            dma_cnt <= 12'd0;
                            enc_ntt_phase <= 2'd0;
                            ct_pack_sent <= 1'b0;
                            state <= S_ENC_PACK;
                        end else begin
                            dma_cnt <= dma_cnt + 12'd1;
                        end
                    end
                end

                S_ENC_PACK: begin
                    // Muc-B CT_PACK owns u_ram through ct_pair_mode and writes
                    // ciphertext as aligned 64-bit words.
                    mux_sel <= 3'd0;

                    if (!ct_pack_sent) begin
                        ct_pack_start <= 1'b1;
                        ct_pack_sent <= 1'b1;
                        ct_cap_idx <= 12'd0;
                        if (dec_reenc_mode) begin
                            cmp_start <= 1'b1;
                            ct_cmp_valid <= 1'b0;
                            ct_cmp_prime_word <= 64'd0;
                        end
                    end

                    ext_we    <= dec_reenc_mode ? 1'b0 : ct_pack_ext_we;
                    ext_addr  <= ct_pack_ext_addr;
                    ext_dout  <= ct_pack_ext_dout;
                    ext_wstrb <= ct_pack_ext_wstrb;

                    if (ct_pack_ext_we && (ct_cap_idx < CT_BYTES_TOTAL)) begin
                        if (dec_reenc_mode) begin
                            ct_cmp_prime_word <= ct_pack_ext_dout;
                            ct_cmp_valid      <= 1'b1;
                        end else begin
                            ct_wide_we    <= 1'b1;
                            ct_wide_addr  <= ct_cap_idx[10:0];
                            ct_wide_din   <= ct_pack_ext_dout;
                            ct_wide_wstrb <= ct_pack_ext_wstrb;
                        end
                        ct_cap_idx <= ct_cap_idx + {8'd0, ct_pack_ext_nbytes};
                    end

                    if (ct_pack_done && (ct_cap_idx >= CT_BYTES_TOTAL) &&
                        (!dec_reenc_mode || !ct_cmp_valid)) begin
                        ct_pack_sent <= 1'b0;
                        hash_sent <= 1'b0;
                        hash_in_valid <= 1'b0;
                        dma_cnt <= 12'd0;
                        if (dec_reenc_mode) begin
                            cmp_finish <= 1'b1;
                            state <= S_DEC_CMP;
                        end else begin
                            enc_write_ss_ready <= 1'b0;
                            state <= S_ENC_WRITE_SS;
                        end
                    end
                end

		
		S_ENC_WRITE_SS: begin
		    if (!enc_write_ss_ready) begin
			dma_cnt       <= 12'd0;
			hash_sent     <= 1'b0;
			enc_write_ss_ready <= 1'b1;
		    end else begin
			ext_we    <= 1'b1;
			ext_wstrb <= 8'hFF;
			ext_addr  <= SS_EXT_BASE + {20'd0, dma_cnt};
			ext_dout  <= bytes8_from_256_msb(reg_K_bar, dma_cnt[4:0]);

			if (ext_ready) begin
			    if (dma_cnt == 12'd24) begin
				state         <= S_IDLE;
				done          <= 1'b1;
				dma_cnt       <= 12'd0;
				enc_write_ss_ready <= 1'b0;
			    end else begin
				dma_cnt <= dma_cnt + 12'd8;
			    end
			end
		    end
		end





                S_DEC_READ: begin
                    // Wide external read for secret-key s:
                    // 3 encoded bytes are available in ext_din[23:0] after one
                    // external read transaction; decode and write both coeffs
                    // to scratch in the same cycle.
                    ext_re <= 1'b1;
                    if (!dec_sk_reload_done) begin
                        sk_coeff_base = ({9'd0, dec_sk_poly} * 12'd256) + {3'd0, dec_sk_pair, 1'b0};

                        if (ext_ready) begin
                            mb_wr_en_c0 <= 1'b1;
                            mb_wr_en_c1 <= 1'b1;
                            mb_wr_slot <= 3'd2 + dec_sk_poly;
                            mb_wr_pair_addr <= dec_sk_pair[6:0];
                            mb_wr_c0 <= $signed({4'd0, ext_decode12_coeff_pair[11:0]});
                            mb_wr_c1 <= $signed({4'd0, ext_decode12_coeff_pair[23:12]});
                            local_pwma_operand_we <= 1'b1;
                            local_pwma_operand_load_bank <= dec_sk_poly[0];
                            local_pwma_operand_addr <= dec_sk_pair[6:0];
                            local_pwma_operand_pair <= {
                                4'd0, ext_decode12_coeff_pair[23:12],
                                4'd0, ext_decode12_coeff_pair[11:0]
                            };

                            if (dec_sk_pair == 8'd127) begin
                                dec_sk_pair <= 8'd0;
                                if (dec_sk_poly + 3'd1 == KYBER_K) begin
                                    dec_sk_poly <= 3'd0;
                                    dec_sk_reload_done <= 1'b1;
                                    pack_pk_addr <= pack_pk_addr + ({29'd0, KYBER_K} * 32'd384);
                                    ext_addr <= pack_pk_addr + ({29'd0, KYBER_K} * 32'd384);
                                end else begin
                                    dec_sk_poly <= dec_sk_poly + 3'd1;
                                    ext_addr <= pack_pk_addr + ({29'd0, dec_sk_poly + 3'd1} * 32'd384);
                                end
                            end else begin
                                dec_sk_pair <= dec_sk_pair + 8'd1;
                                ext_addr <= pack_pk_addr + ({29'd0, dec_sk_poly} * 32'd384) + ({24'd0, dec_sk_pair + 8'd1} * 32'd3);
                            end
                        end
                    end else begin
                        dec_sk_reload_done <= 1'b0;
                        state <= S_ENC_READ_PK;
                    end
                end

                S_ENC_READ_PK: begin
                    // Wide external read for public key:
                    //   t-polys: decode 3 bytes -> 2 coeffs.
                    //   rho    : read 8 bytes per cycle.
                    ext_re <= 1'b1;
                    if (!dec_sk_reload_done) begin
                        sk_coeff_base = ({9'd0, dec_sk_poly} * 12'd256) + {3'd0, dec_sk_pair, 1'b0};

                        if (ext_ready) begin
                            mb_wr_en_c0 <= 1'b1;
                            mb_wr_en_c1 <= 1'b1;
                            mb_wr_slot <= dec_sk_poly;
                            mb_wr_pair_addr <= dec_sk_pair[6:0];
                            mb_wr_c0 <= $signed({4'd0, ext_decode12_coeff_pair[11:0]});
                            mb_wr_c1 <= $signed({4'd0, ext_decode12_coeff_pair[23:12]});

                            if (dec_sk_pair == 8'd127) begin
                                dec_sk_pair <= 8'd0;
                                if (dec_sk_poly + 3'd1 == KYBER_K) begin
                                    dec_sk_poly <= 3'd0;
                                    dec_sk_reload_done <= 1'b1;
                                    dma_cnt <= 12'd0;
                                    pack_pk_addr <= pack_pk_addr + ({29'd0, KYBER_K} * 32'd384);
                                    ext_addr <= pack_pk_addr + ({29'd0, KYBER_K} * 32'd384);
                                end else begin
                                    dec_sk_poly <= dec_sk_poly + 3'd1;
                                    ext_addr <= pack_pk_addr + ({29'd0, dec_sk_poly + 3'd1} * 32'd384);
                                end
                            end else begin
                                dec_sk_pair <= dec_sk_pair + 8'd1;
                                ext_addr <= pack_pk_addr + ({29'd0, dec_sk_poly} * 32'd384) + ({24'd0, dec_sk_pair + 8'd1} * 32'd3);
                            end
                        end
                    end else if (dma_cnt < 12'd32) begin
                        if (ext_ready) begin
                            reg_rho <= {reg_rho[191:0], flip_bytes_8(ext_din)};

                            if (dma_cnt == 12'd24) begin
                                pack_pk_addr <= pack_pk_addr + 32'd32;
                                if (opcode == 2'b10) begin
                                    state <= S_KG_HASH_PK;
                                    hash_sent <= 1'b0;
                                end else begin
                                    state <= S_DEC_READ_REST;
                                    dma_cnt <= 12'd0;
                                    ext_addr <= pack_pk_addr + 32'd32;
                                end
                            end else begin
                                dma_cnt <= dma_cnt + 12'd8;
                                ext_addr <= pack_pk_addr + {20'd0, dma_cnt} + 32'd8;
                            end
                        end
                    end
                end

                S_DEC_READ_REST: begin
                    // H(pk) and z are both 32-byte fields, read 8 bytes/cycle.
                    ext_re <= 1'b1;
                    if (dma_cnt < 12'd32) begin
                        if (ext_ready) begin
                            reg_H_pk <= {reg_H_pk[191:0], flip_bytes_8(ext_din)};

                            if (dma_cnt == 12'd24) begin
                                dma_cnt <= 12'd32;
                                ext_addr <= pack_pk_addr + 32'd32;
                            end else begin
                                dma_cnt <= dma_cnt + 12'd8;
                                ext_addr <= pack_pk_addr + {20'd0, dma_cnt} + 32'd8;
                            end
                        end
                    end else if (dma_cnt < 12'd64) begin
                        if (ext_ready) begin
                            reg_z <= {reg_z[191:0], flip_bytes_8(ext_din)};

                            if (dma_cnt == 12'd56) begin
                                state <= S_DEC_READ_CT;
                                dma_cnt <= 12'd0;
                                hash_sent <= 1'b0;
                            end else begin
                                dma_cnt <= dma_cnt + 12'd8;
                                ext_addr <= pack_pk_addr + {20'd0, dma_cnt} + 32'd8;
                            end
                        end
                    end
                end

                S_DEC_READ_CT: begin
                    // Ciphertext read: 768 bytes -> 96 external 64-bit reads.
                    // Store original C once in ct_ram; unpack, RKPRF, and C/C'
                    // compare share this copy in separate FSM phases.
                    ext_re <= 1'b1;
                    if (!hash_sent) begin
                        ext_addr <= CT_EXT_BASE;
                        dma_cnt <= 12'd0;
                        hash_sent <= 1'b1;
                    end else begin
                        if (dma_cnt < CT_BYTES_TOTAL) begin
                            if (ext_ready) begin
                                ct_wide_we    <= 1'b1;
                                ct_wide_addr  <= dma_cnt[10:0];
                                ct_wide_din   <= ext_din;
                                ct_wide_wstrb <= 8'hFF;

                                if (dma_cnt + 12'd8 >= CT_BYTES_TOTAL) begin
                                    state     <= S_DEC_DECOMP;
                                    dma_cnt   <= 12'd0;
                                    hash_sent <= 1'b0;
                                    dec_phase <= 4'd0;
                                    hash_fetching <= 1'b0; fetch_wait <= 1'b0; fetch_cnt <= 8'd0;
                                    dec_fetch_done <= 1'b0; dec_j_idx <= 3'd0; reg_m <= 256'd0; ct_unpack_sent <= 1'b0;
                                    dec_u0_direct_loaded <= 1'b0;
                                    dec_u0_ntt_started <= 1'b0;
                                    dec_u0_ntt_done <= 1'b0;
                                    dec_unpack_done_latched <= 1'b0;
                                    dp_phase <= 5'd0;
                                    dp_local_pwma_enable <= 1'b0;
                                    dp_local_pwma_gm_source <= 1'b0;
                                end else begin
                                    dma_cnt  <= dma_cnt + 12'd8;
                                    ext_addr <= CT_EXT_BASE + {20'd0, dma_cnt} + 32'd8;
                                end
                            end
                        end
                    end
                end

                S_DEC_DECOMP: begin
                    mux_sel <= 3'd0;
                    ntt_mux_sel <= 3'd0;

                    
                    
                    
                    
                    if (1'b1) begin
                        dp_local_pwma_gm_source <= 1'b0;
                        dp_local_pwma_ntt_source <= 1'b1;
                        local_pwma_use_tomont <= 1'b0;
                        local_pwma_operand_bank <= dec_j_idx[0];
                        local_pwma_accumulate <= (dec_j_idx != 3'd0);

                        case (dp_phase)
                            5'd0: begin
                                dp_local_pwma_enable <= 1'b1;
                                dec_unpack_done_latched <= 1'b0;
                                dec_u0_direct_loaded <= 1'b0;
                                dec_u0_ntt_started <= 1'b0;
                                dec_u0_ntt_done <= 1'b0;
                                dec_j_idx <= 3'd0;
                                dma_cnt <= 12'd0;
                                ct_unpack_start <= 1'b1;
                                ct_unpack_sent <= 1'b1;
                                dp_phase <= 5'd1;
                            end

                            5'd1: begin
                                if (ct_unpack_pair_we) begin
                                    mb_wr_en_c0 <= 1'b1;
                                    mb_wr_en_c1 <= 1'b1;
                                    mb_wr_slot <= ct_unpack_pair_slot;
                                    mb_wr_pair_addr <= ct_unpack_pair_addr;
                                    mb_wr_c0 <= ct_unpack_pair_c0;
                                    mb_wr_c1 <= ct_unpack_pair_c1;

                                    if (ct_unpack_pair_slot == 3'd4) begin
                                        fsm_ntt_we <= 1'b1;
                                        fsm_ntt_we_b <= 1'b1;
                                        fsm_ntt_addr <=
                                            {ct_unpack_pair_addr, 1'b0};
                                        fsm_ntt_addr_b <=
                                            {ct_unpack_pair_addr, 1'b0} + 8'd1;
                                        fsm_ntt_din <= ct_unpack_pair_c0;
                                        fsm_ntt_din_b <= ct_unpack_pair_c1;
                                        if (ct_unpack_pair_addr == 7'd127)
                                            dec_u0_direct_loaded <= 1'b1;
                                    end
                                end

                                if (dec_u0_direct_loaded &&
                                    !dec_u0_ntt_started) begin
                                    ntt_mode <= 1'b0;
                                    ntt_start <= 1'b1;
                                    dec_u0_ntt_started <= 1'b1;
                                end
                                if (dec_u0_ntt_started && ntt_done)
                                    dec_u0_ntt_done <= 1'b1;

                                if (ct_unpack_done) begin
                                    ct_unpack_sent <= 1'b0;
                                    dec_unpack_done_latched <= 1'b1;
                                end

                                if ((ct_unpack_done ||
                                     dec_unpack_done_latched) &&
                                    (dec_u0_ntt_done ||
                                     (dec_u0_ntt_started && ntt_done))) begin
                                    dma_cnt <= 12'd0;
                                    dec_j_idx <= 3'd0;
                                    dp_phase <= 5'd2;
                                end
                            end

                            5'd2: begin
                                if (!pwma_sent) begin
                                    local_pwma_start <= 1'b1;
                                    pwma_sent <= 1'b1;
                                end

                                fsm_ntt_addr <= {dma_cnt[6:0], 1'b0};
                                fsm_ntt_addr_b <=
                                    {dma_cnt[6:0], 1'b0} + 8'd1;

                                if (dma_cnt < 12'd131)
                                    dma_cnt <= dma_cnt + 12'd1;

                                if (local_pwma_done) begin
                                    pwma_sent <= 1'b0;
                                    dma_cnt <= 12'd0;
                                    if (dec_j_idx + 3'd1 == KYBER_K) begin
                                        kg_transfer_valid <= 1'b0;
                                        kg_transfer_capture_valid <= 1'b0;
                                        dp_phase <= 5'd6;
                                    end else begin
                                        dec_j_idx <= dec_j_idx + 3'd1;
                                        kg_mb_load_valid <= 1'b0;
                                        kg_mb_load_capture_valid <= 1'b0;
                                        dp_phase <= 5'd4;
                                    end
                                end
                            end

                            5'd3: begin
                                dp_phase <= 5'd2;
                            end

                            5'd4: begin
                                if (kg_mb_load_capture_valid) begin
                                    fsm_ntt_we <= 1'b1;
                                    fsm_ntt_we_b <= 1'b1;
                                    fsm_ntt_addr <=
                                        {kg_mb_load_capture_addr, 1'b0};
                                    fsm_ntt_addr_b <=
                                        {kg_mb_load_capture_addr, 1'b0} + 8'd1;
                                    fsm_ntt_din <= mb_rd_c0;
                                    fsm_ntt_din_b <= mb_rd_c1;
                                end
                                kg_mb_load_capture_valid <= kg_mb_load_valid;
                                kg_mb_load_capture_addr <= kg_mb_load_addr;

                                if (dma_cnt < 12'd128) begin
                                    mb_rd_en <= 1'b1;
                                    mb_rd_slot <= 3'd4 + dec_j_idx;
                                    mb_rd_pair_addr <= dma_cnt[6:0];
                                    kg_mb_load_valid <= 1'b1;
                                    kg_mb_load_addr <= dma_cnt[6:0];
                                    dma_cnt <= dma_cnt + 12'd1;
                                end else begin
                                    kg_mb_load_valid <= 1'b0;
                                    if (!kg_mb_load_valid &&
                                        !kg_mb_load_capture_valid) begin
                                        if (dma_cnt == 12'd128)
                                            dma_cnt <= 12'd129;
                                        else begin
                                            dma_cnt <= 12'd0;
                                            ntt_sent <= 1'b0;
                                            dp_phase <= 5'd5;
                                        end
                                    end
                                end
                            end

                            5'd5: begin
                                ntt_mode <= 1'b0;
                                if (!ntt_sent) begin
                                    ntt_start <= 1'b1;
                                    ntt_sent <= 1'b1;
                                end
                                if (ntt_done) begin
                                    ntt_sent <= 1'b0;
                                    dma_cnt <= 12'd0;
                                    dp_phase <= 5'd2;
                                end
                            end

                            5'd6: begin
                                if (kg_transfer_capture_valid) begin
                                    fsm_ntt_we <= 1'b1;
                                    fsm_ntt_we_b <= 1'b1;
                                    fsm_ntt_addr <=
                                        {kg_transfer_capture_addr, 1'b0};
                                    fsm_ntt_addr_b <=
                                        {kg_transfer_capture_addr, 1'b0} + 8'd1;
                                    fsm_ntt_din <=
                                        local_pwma_result_pair[15:0];
                                    fsm_ntt_din_b <=
                                        local_pwma_result_pair[31:16];
                                end
                                kg_transfer_capture_valid <= kg_transfer_valid;
                                kg_transfer_capture_addr <= kg_transfer_addr;

                                if (dma_cnt < 12'd128) begin
                                    local_pwma_result_addr <= dma_cnt[6:0];
                                    kg_transfer_valid <= 1'b1;
                                    kg_transfer_addr <= dma_cnt[6:0];
                                    dma_cnt <= dma_cnt + 12'd1;
                                end else begin
                                    kg_transfer_valid <= 1'b0;
                                    if (!kg_transfer_valid &&
                                        !kg_transfer_capture_valid) begin
                                        if (dma_cnt == 12'd128)
                                            dma_cnt <= 12'd129;
                                        else begin
                                            dma_cnt <= 12'd0;
                                            ntt_sent <= 1'b0;
                                            dp_phase <= 5'd7;
                                        end
                                    end
                                end
                            end

                            5'd7: begin
                                ntt_mode <= 1'b1;
                                if (!ntt_sent) begin
                                    ntt_start <= 1'b1;
                                    ntt_sent <= 1'b1;
                                end
                                if (ntt_done) begin
                                    ntt_sent <= 1'b0;
                                    dma_cnt <= 12'd0;
                                    dp_phase <= 5'd8;
                                end
                            end

                            5'd8: begin
                                if (dma_cnt == 12'd128) begin
                                    fsm_ntt_addr <= 8'd252;
                                    fsm_ntt_addr_b <= 8'd253;
                                end else if (dma_cnt > 12'd128) begin
                                    fsm_ntt_addr <= 8'd254;
                                    fsm_ntt_addr_b <= 8'd255;
                                end else begin
                                    fsm_ntt_addr <=
                                        {dma_cnt[6:0], 1'b0};
                                    fsm_ntt_addr_b <=
                                        {dma_cnt[6:0], 1'b0} + 8'd1;
                                end

                                if ((dma_cnt >= 12'd3) &&
                                    (dma_cnt < 12'd131)) begin
                                    mb_rd_en <= 1'b1;
                                    mb_rd_slot <= 3'd6;
                                    mb_rd_pair_addr <=
                                        dma_cnt[6:0] - 7'd3;
                                end

                                if (dma_cnt > 4) begin
                                    case (dec_msg_pair_pos)
                                        2'd0: begin
                                            dec_msg_byte_acc[1:0] <=
                                                dec_encode1_word[1:0];
                                            dec_msg_pair_pos <= 2'd1;
                                        end
                                        2'd1: begin
                                            dec_msg_byte_acc[3:2] <=
                                                dec_encode1_word[1:0];
                                            dec_msg_pair_pos <= 2'd2;
                                        end
                                        2'd2: begin
                                            dec_msg_byte_acc[5:4] <=
                                                dec_encode1_word[1:0];
                                            dec_msg_pair_pos <= 2'd3;
                                        end
                                        default: begin
                                            reg_m <= {
                                                reg_m[247:0],
                                                dec_encode1_word[1],
                                                dec_encode1_word[0],
                                                dec_msg_byte_acc[5:0]
                                            };
                                            dec_msg_pair_pos <= 2'd0;
                                        end
                                    endcase
                                end

                                if (dma_cnt == 12'd132) begin
                                    dma_cnt <= 12'd0;
                                    dp_local_pwma_enable <= 1'b0;
                                    dp_phase <= 5'd0;
                                    hash_sent <= 1'b0;
                                    state <= S_DEC_NTT_U;
                                end else begin
                                    dma_cnt <= dma_cnt + 12'd1;
                                end
                            end

                            default: dp_phase <= 5'd0;
                        endcase
                    end
                end

                
                S_DEC_NTT_U: begin
                    hash_cmd   <= 3'd3;
                    hash_in_stream_en <= 1'b1;
                    if (!hash_sent) begin
                        hash_start <= 1'b1;
                        hash_sent  <= 1'b1;
                        dma_cnt    <= 12'd0;
                        hash_in_valid <= 1'b0;
                    end else if (!hash_in_valid && hash_in_ready && (dma_cnt < 12'd64)) begin
                        if (dma_cnt < 12'd32)
                            hash_in_data <= bytes8_from_256_msb(reg_m, dma_cnt[4:0]);
                        else
                            hash_in_data <= bytes8_from_256_msb(reg_H_pk, dma_cnt[4:0]);
                        hash_in_bytes <= 4'd8;
                        hash_in_last  <= (dma_cnt == 12'd56);
                        hash_in_valid <= 1'b1;
                        dma_cnt       <= dma_cnt + 12'd8;
                    end
                    if (hash_done) begin
                        reg_K_bar  <= flip_bytes_32(hash_dout[255:0]);   
                        reg_r_seed <= flip_bytes_32(hash_dout[511:256]); 
                        hash_sent  <= 1'b0;
                        
                        dec_reenc_mode <= 1'b1;
                        cbd_sent   <= 1'b0;
                        ntt_sent   <= 1'b0;
                        pwma_sent  <= 1'b0;
                        loop_j     <= 3'd0;
                        enc_noise_kind <= 2'd0;
                        enc_ntt_phase <= 2'd0;
                        dma_cnt    <= 12'd0;
                        state      <= S_ENC_CBD_R;
                    end
                end

                
                S_DEC_CMP: begin
                    if (cmp_done) begin
                        dec_reenc_mode    <= 1'b0;
                        hash_sent         <= 1'b0;
                        hash_fetching     <= 1'b0;
                        fetch_wait        <= 1'b0;
                        fetch_cnt         <= 8'd0;
                        hash_in_valid <= 1'b0;
                        dma_cnt           <= 12'd0;

                        if (cmp_not_equal)
                            state <= S_DEC_RKPRF;
                        else
                            state <= S_DEC_PACK;
                    end
                end

                

                
                
                
                
		
		
		
		S_DEC_RKPRF: begin
		    hash_cmd       <= 3'd4; 
		    hash_in_stream_en <= 1'b1;

		    if (!hash_sent) begin
			hash_sent         <= 1'b1;
			hash_start        <= 1'b1;
			dma_cnt           <= 12'd0;
			hash_fetching     <= 1'b0;
			fetch_wait        <= 1'b0;
			fetch_cnt         <= 8'd0;
			hash_in_valid     <= 1'b0;
		    end else begin
			if (!hash_in_valid && hash_in_ready && dma_cnt < (CT_BYTES_TOTAL + 12'd32)) begin
			    if (dma_cnt < 12'd32) begin
				hash_in_data  <= bytes8_from_256_msb(reg_z, dma_cnt[4:0]);
				hash_in_bytes <= 4'd8;
				hash_in_last  <= 1'b0;
				hash_in_valid <= 1'b1;
				dma_cnt       <= dma_cnt + 12'd8;
			    end else if (!hash_fetching) begin
				hash_in_data   <= 64'd0;
				fetch_cnt      <= 8'd0;
				hash_fetching  <= 1'b1;
				ct_addr_b_fsm  <= dma_cnt[10:0] - 11'd32;
				fetch_wait     <= 1'b1;
			    end else if (fetch_wait) begin
				fetch_wait    <= 1'b0;
				ct_addr_b_fsm <= ct_addr_b_fsm + 11'd1;
			    end else begin
				hash_in_data[(fetch_cnt * 8) +: 8] <= ct_dout;
				if ((fetch_cnt == 8'd7) ||
				    (dma_cnt + {4'd0, fetch_cnt} + 12'd1 == (CT_BYTES_TOTAL + 12'd32))) begin
				    hash_fetching <= 1'b0;
				    hash_in_bytes <= fetch_cnt[3:0] + 4'd1;
				    hash_in_last  <= (dma_cnt + {4'd0, fetch_cnt} + 12'd1 == (CT_BYTES_TOTAL + 12'd32));
				    hash_in_valid <= 1'b1;
				    dma_cnt       <= dma_cnt + {4'd0, fetch_cnt} + 12'd1;
				end else begin
				    fetch_cnt <= fetch_cnt + 8'd1;
				    ct_addr_b_fsm <= dma_cnt[10:0] - 11'd30 + {3'd0, fetch_cnt};
				end
			    end
			end
		    end

		    if (hash_done) begin
			reg_K_bar         <= flip_bytes_32(hash_dout[255:0]);
			hash_sent         <= 1'b0;
			hash_fetching     <= 1'b0;
			fetch_wait        <= 1'b0;
			hash_in_valid     <= 1'b0;
			dec_kdf_ready     <= 1'b0;
			dma_cnt           <= 12'd0;
			state             <= S_DEC_PACK;
		    end
		end
                
                
		
		S_DEC_PACK: begin
		    if (!dec_kdf_ready) begin
			dma_cnt       <= 12'd0;
			hash_sent     <= 1'b0;
			dec_kdf_ready <= 1'b1;
		    end else begin
			ext_we    <= 1'b1;
			ext_wstrb <= 8'hFF;
			ext_addr  <= SS_EXT_BASE + {20'd0, dma_cnt};
			ext_dout  <= bytes8_from_256_msb(reg_K_bar, dma_cnt[4:0]);

			if (ext_ready) begin
			    if (dma_cnt == 12'd24) begin
				state         <= S_IDLE;
				done          <= 1'b1;
				dma_cnt       <= 12'd0;
				dec_kdf_ready <= 1'b0;
			    end else begin
				dma_cnt <= dma_cnt + 12'd8;
			    end
			end
		    end
		end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign state_dbg = state;

endmodule
