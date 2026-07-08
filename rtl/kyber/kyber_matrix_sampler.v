`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// kyber_matrix_sampler
// Kyber512 RTL source. Comments and unused debug-only code were removed for a
// synthesis-oriented release build.
// -----------------------------------------------------------------------------

module kyber_matrix_sampler (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    input  wire [255:0] rho,        
    input  wire         transposed,

    
    output reg          xof_req_valid,
    output reg  [271:0] xof_req_din,
    input  wire         xof_req_ready,
    output reg          xof_release,

    
    input  wire [63:0]  xof_word_data,
    input  wire         xof_word_valid,
    output wire         xof_word_ready,

    input  wire         coeff_ready,
    output reg          we,
    output reg  [11:0]  ram_addr,
    output reg  [15:0]  ram_dout,
    output reg          we_b,
    output reg  [11:0]  ram_addr_b,
    output reg  [15:0]  ram_dout_b,

    output reg          done,
    output wire         busy
);

    localparam KYBER_Q = 12'd3329;
    localparam BASE_A  = 12'd0;

    function [255:0] flip_bytes_32;
        input [255:0] in_data;
        integer fi;
        begin
            for (fi = 0; fi < 32; fi = fi + 1)
                flip_bytes_32[(31-fi)*8 +: 8] = in_data[fi*8 +: 8];
        end
    endfunction

    reg [2:0]  loop_i, loop_j;
    reg [2:0]  k_val;
    reg [8:0]  coeff_cnt;     
    reg [11:0] poly_base;     

    
    reg [127:0] sample_buf;
    reg [7:0]   sample_bits;

    localparam GM_IDLE       = 3'd0;
    localparam GM_XOF_INIT   = 3'd1;
    localparam GM_XOF_ACCEPT = 3'd2;
    localparam GM_WAIT_WORD  = 3'd3;
    localparam GM_NEED_WORD  = 3'd4;
    localparam GM_REJECT     = 3'd5;
    localparam GM_NEXT_POLY  = 3'd6;
    localparam GM_DONE       = 3'd7;

    reg [2:0] state;

    assign busy = (state != GM_IDLE);

    wire [11:0] candidate0    = sample_buf[11:0];
    wire [11:0] candidate1    = sample_buf[23:12];
    wire        candidate0_ok = (candidate0 < KYBER_Q);
    wire        candidate1_ok = (candidate1 < KYBER_Q);
    wire [8:0]  coeff_cnt_p1  = coeff_cnt + 9'd1;

    
    
    
    assign xof_word_ready = (state == GM_NEED_WORD) && (sample_bits <= 8'd64);

    always @(posedge clk) begin
        if (rst) begin
            state         <= GM_IDLE;
            we            <= 1'b0;
            ram_addr      <= 12'd0;
            ram_dout      <= 16'd0;
            we_b          <= 1'b0;
            ram_addr_b    <= 12'd0;
            ram_dout_b    <= 16'd0;
            done          <= 1'b0;
            xof_req_valid <= 1'b0;
            xof_req_din   <= 272'd0;
            xof_release   <= 1'b0;
            loop_i        <= 3'd0;
            loop_j        <= 3'd0;
            k_val         <= 3'd2;
            coeff_cnt     <= 9'd0;
            poly_base     <= 12'd0;
            sample_buf    <= 128'd0;
            sample_bits   <= 8'd0;
        end else begin
            
            xof_req_valid <= 1'b0;
            xof_release   <= 1'b0;
            we            <= 1'b0;
            we_b          <= 1'b0;

            case (state)
                GM_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        k_val       <= 3'd2;
                        loop_i      <= 3'd0;
                        loop_j      <= 3'd0;
                        coeff_cnt   <= 9'd0;
                        poly_base   <= BASE_A;
                        sample_buf  <= 128'd0;
                        sample_bits <= 8'd0;
                        state       <= GM_XOF_INIT;
                    end
                end

                GM_XOF_INIT: begin
                    
                    
                    
                    
                    if (!transposed) begin
                        xof_req_din <= {
                            {5'd0, loop_i},
                            {5'd0, loop_j},
                            flip_bytes_32(rho)
                        };
                    end else begin
                        xof_req_din <= {
                            {5'd0, loop_j},
                            {5'd0, loop_i},
                            flip_bytes_32(rho)
                        };
                    end

                    coeff_cnt   <= 9'd0;
                    sample_buf  <= 128'd0;
                    sample_bits <= 8'd0;

                    
                    
                    
                    state <= GM_XOF_ACCEPT;
                end

                GM_XOF_ACCEPT: begin
                    
                    
                    xof_req_valid <= 1'b1;
                    if (xof_req_ready) begin
                        state <= GM_WAIT_WORD;
                    end
                end

                GM_WAIT_WORD: begin
                    
                    
                    
                    state <= GM_NEED_WORD;
                end

                GM_NEED_WORD: begin
                    if (xof_word_valid) begin
                        sample_buf  <= sample_buf | ({64'd0, xof_word_data} << sample_bits);
                        sample_bits <= sample_bits + 8'd64;
                        state       <= GM_REJECT;
                    end
                end

                GM_REJECT: begin
                    if (coeff_cnt == 9'd256) begin
                        state <= GM_NEXT_POLY;

                    end else if (!coeff_ready) begin
                        state <= GM_REJECT;

                    end else if (sample_bits < 8'd12) begin
                        state <= GM_NEED_WORD;

                    end else if (sample_bits >= 8'd24) begin
                        sample_buf  <= sample_buf >> 24;
                        sample_bits <= sample_bits - 8'd24;

                        if (candidate0_ok) begin
                            we        <= 1'b1;
                            ram_addr  <= poly_base + {3'd0, coeff_cnt[7:0]};
                            ram_dout  <= {4'd0, candidate0};

                            if (candidate1_ok && (coeff_cnt != 9'd255)) begin
                                we_b       <= 1'b1;
                                ram_addr_b <= poly_base + {3'd0, coeff_cnt_p1[7:0]};
                                ram_dout_b <= {4'd0, candidate1};
                                coeff_cnt  <= coeff_cnt + 9'd2;
                            end else begin
                                coeff_cnt <= coeff_cnt + 9'd1;
                            end
                        end else if (candidate1_ok) begin
                            we        <= 1'b1;
                            ram_addr  <= poly_base + {3'd0, coeff_cnt[7:0]};
                            ram_dout  <= {4'd0, candidate1};
                            coeff_cnt <= coeff_cnt + 9'd1;
                        end

                    end else begin
                        sample_buf  <= sample_buf >> 12;
                        sample_bits <= sample_bits - 8'd12;

                        if (candidate0_ok) begin
                            we        <= 1'b1;
                            ram_addr  <= poly_base + {3'd0, coeff_cnt[7:0]};
                            ram_dout  <= {4'd0, candidate0};
                            coeff_cnt <= coeff_cnt + 9'd1;
                        end
                    end
                end

                GM_NEXT_POLY: begin
                    we <= 1'b0;

                    if (loop_j + 1 < k_val) begin
                        loop_j    <= loop_j + 1;
                        poly_base <= poly_base + 12'd256;
                        state     <= GM_XOF_INIT;
                    end else if (loop_i + 1 < k_val) begin
                        loop_i    <= loop_i + 1;
                        loop_j    <= 3'd0;
                        poly_base <= poly_base + 12'd256;
                        state     <= GM_XOF_INIT;
                    end else begin
                        state <= GM_DONE;
                    end
                end

                GM_DONE: begin
                    
                    xof_release <= 1'b1;
                    done        <= 1'b1;
                    state       <= GM_IDLE;
                end

                default: state <= GM_IDLE;
            endcase
        end
    end

endmodule

