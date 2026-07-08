`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// kyber_cbd_sampler
// Kyber512 RTL source. Comments and unused debug-only code were removed for a
// synthesis-oriented release build.
// -----------------------------------------------------------------------------

module kyber_cbd_sampler (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        eta3_mode,          

    input  wire        stream_valid,
    output wire        stream_ready,
    input  wire [63:0] stream_data,
    input  wire        stream_last,

    input  wire [10:0] base_addr,

    output reg         we,
    output reg  [10:0] ram_addr,
    output reg  signed [15:0] poly_coeffs_out,
    output reg         we_b,
    output reg  [10:0] ram_addr_b,
    output reg  signed [15:0] poly_coeffs_out_b,
    output reg         done
);

    localparam IDLE    = 2'd0;
    localparam PROCESS = 2'd1;
    localparam FINISH  = 2'd2;

    function signed [15:0] cbd_core_signed;
        input [5:0] din;
        reg [1:0] a;
        reg [1:0] b;
        reg signed [3:0] diff;
        begin
            a = {1'b0, din[0]} + {1'b0, din[1]} + {1'b0, din[2]};
            b = {1'b0, din[3]} + {1'b0, din[4]} + {1'b0, din[5]};
            diff = $signed({1'b0, a}) - $signed({1'b0, b});
            cbd_core_signed = {{12{diff[3]}}, diff};
        end
    endfunction

    reg [1:0]   state;
    reg [127:0] bit_buf;
    reg [7:0]   bits_avail;
    reg [8:0]   coeff_cnt;   
    reg         saved_eta3;  
    reg         input_done;

    assign stream_ready = (state == PROCESS) && !input_done && (bits_avail <= 8'd64);

    wire        accept_word    = stream_valid && stream_ready;
    wire [7:0]  bit_step       = saved_eta3 ? 8'd6 : 8'd4;
    wire [7:0]  bit_step2      = saved_eta3 ? 8'd12 : 8'd8;
    wire [127:0] input_appended = bit_buf | ({64'd0, stream_data} << bits_avail);
    wire [127:0] sample_buf     = accept_word ? input_appended : bit_buf;
    wire [7:0]   bits_with_input = bits_avail + (accept_word ? 8'd64 : 8'd0);
    wire         can_emit        = (state == PROCESS) &&
                                   (coeff_cnt < 9'd256) &&
                                   (bits_with_input >= bit_step);
    wire         emit_two        = can_emit &&
                                   (coeff_cnt < 9'd255) &&
                                   (bits_with_input >= bit_step2);
    wire [8:0]   coeff_cnt_p1    = coeff_cnt + 9'd1;
    wire [7:0]   emit_step       = emit_two ? bit_step2 : bit_step;

    wire [7:0]  eta2_raw = sample_buf[7:0];
    wire [11:0] eta2_as_eta3 = {
        1'b0, eta2_raw[7], eta2_raw[6],
        1'b0, eta2_raw[5], eta2_raw[4],
        1'b0, eta2_raw[3], eta2_raw[2],
        1'b0, eta2_raw[1], eta2_raw[0]
    };
    wire [11:0] cbd_core_din = saved_eta3 ? sample_buf[11:0] : eta2_as_eta3;
    wire signed [15:0] cbd_val   = cbd_core_signed(cbd_core_din[5:0]);
    wire signed [15:0] cbd_val_b = cbd_core_signed(cbd_core_din[11:6]);

    
    always @(posedge clk) begin
        if (rst) begin
            state           <= IDLE;
            we              <= 1'b0;
            ram_addr        <= 11'd0;
            poly_coeffs_out <= 16'd0;
            we_b              <= 1'b0;
            ram_addr_b        <= 11'd0;
            poly_coeffs_out_b <= 16'd0;
            coeff_cnt       <= 9'd0;
            bit_buf         <= 128'd0;
            bits_avail      <= 8'd0;
            done            <= 1'b0;
            saved_eta3      <= 1'b0;
            input_done      <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    we   <= 1'b0;
                    we_b <= 1'b0;
                    if (start) begin
                        bit_buf    <= 128'd0;
                        bits_avail <= 8'd0;
                        saved_eta3 <= eta3_mode;
                        coeff_cnt  <= 9'd0;
                        input_done <= 1'b0;
                        state      <= PROCESS;
                    end
                end

                PROCESS: begin
                    we <= 1'b0;
                    we_b <= 1'b0;

                    if (can_emit) begin
                        we              <= 1'b1;
                        poly_coeffs_out <= cbd_val;
                        ram_addr        <= base_addr + {2'd0, coeff_cnt};
                        if (emit_two) begin
                            we_b              <= 1'b1;
                            poly_coeffs_out_b <= cbd_val_b;
                            ram_addr_b        <= base_addr + {2'd0, coeff_cnt_p1};
                        end
                        bit_buf         <= sample_buf >> emit_step;
                        bits_avail      <= bits_with_input - emit_step;
                        coeff_cnt       <= coeff_cnt + (emit_two ? 9'd2 : 9'd1);

                        if (accept_word && stream_last)
                            input_done <= 1'b1;

                        if ((emit_two && (coeff_cnt >= 9'd254)) ||
                            (!emit_two && (coeff_cnt == 9'd255)))
                            state <= FINISH;
                    end else begin
                        bit_buf    <= sample_buf;
                        bits_avail <= bits_with_input;

                        if (accept_word && stream_last)
                            input_done <= 1'b1;
                    end
                end

                FINISH: begin
                    we   <= 1'b0;
                    we_b <= 1'b0;
                    done <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

