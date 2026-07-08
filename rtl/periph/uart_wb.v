`timescale 1ns/1ps

// Wishbone UART with 32-byte TX/RX FIFOs used by the Kyber-512 SoC.
module uart_wb #(
    parameter integer CLK_FREQ_HZ  = 50_000_000,
    parameter integer BAUD_DEFAULT = 115200
)(
    input  wire        wb_clk_i,
    input  wire        wb_rst_i,
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    input  wire [3:0]  wb_sel_i,
    input  wire        wb_we_i,
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    output reg         wb_ack_o,
    output reg         wb_err_o,

    input  wire        uart_rx_i,
    output wire        uart_tx_o,
    output wire        irq_o
);
    localparam [7:0] REG_TX_BUFFER   = 8'h00;
    localparam [7:0] REG_RX_BUFFER   = 8'h04;
    localparam [7:0] REG_CONTROL     = 8'h08;
    localparam [7:0] REG_STATUS      = 8'h0C;
    localparam [7:0] REG_AVAILABLE_TX = 8'h10;
    localparam [7:0] REG_AVAILABLE_RX = 8'h14;
    localparam [7:0] REG_INT_STATUS  = 8'h18;
    localparam [7:0] REG_INT_ENABLE  = 8'h1C;
    localparam [7:0] REG_DIV         = 8'h20;

    localparam integer DEFAULT_DIV_INT = (CLK_FREQ_HZ / (16 * BAUD_DEFAULT));
    localparam [15:0] DEFAULT_DIV = (DEFAULT_DIV_INT > 0) ? DEFAULT_DIV_INT[15:0] : 16'd1;
    localparam [2:0] TX_IDLE  = 3'd0;
    localparam [2:0] TX_START = 3'd1;
    localparam [2:0] TX_DATA  = 3'd2;
    localparam [2:0] TX_PAR   = 3'd3;
    localparam [2:0] TX_STOP1 = 3'd4;
    localparam [2:0] TX_STOP2 = 3'd5;

    localparam [2:0] RX_IDLE  = 3'd0;
    localparam [2:0] RX_START = 3'd1;
    localparam [2:0] RX_DATA  = 3'd2;
    localparam [2:0] RX_PAR   = 3'd3;
    localparam [2:0] RX_STOP1 = 3'd4;
    localparam [2:0] RX_STOP2 = 3'd5;

    reg [7:0]  tx_fifo [0:31];
    reg [7:0]  rx_fifo [0:31];
    reg [4:0]  tx_rd_ptr, tx_wr_ptr;
    reg [4:0]  rx_rd_ptr, rx_wr_ptr;
    reg [5:0]  tx_count, rx_count;

    reg [7:0]  control_reg;
    reg [5:0]  int_enable;
    reg [15:0] baud_div;
    reg [15:0] baud_count;
    reg        baud_tick;

    reg        tx_line;
    reg [2:0]  tx_state;
    reg [3:0]  tx_oversample;
    reg [2:0]  tx_bit_idx;
    reg [3:0]  tx_data_bits;
    reg [1:0]  tx_parity_mode;
    reg        tx_two_stop;
    reg [7:0]  tx_shift;
    reg        tx_parity;

    reg        rx_sync_1, rx_sync_2, rx_sync_d;
    reg [2:0]  rx_state;
    reg [3:0]  rx_oversample;
    reg [2:0]  rx_bit_idx;
    reg [3:0]  rx_data_bits;
    reg [1:0]  rx_parity_mode;
    reg        rx_two_stop;
    reg [7:0]  rx_shift;

    reg parity_error;
    reg overrun_error;
    reg framing_error;

    wire uart_enable = control_reg[7];
    wire tx_fifo_empty = (tx_count == 6'd0);
    wire tx_fifo_full  = (tx_count == 6'd32);
    wire rx_fifo_empty = (rx_count == 6'd0);
    wire rx_fifo_full  = (rx_count == 6'd32);
    wire transmit_pending = (tx_state != TX_IDLE) || !tx_fifo_empty;
    wire wb_fire = wb_cyc_i && wb_stb_i && !wb_ack_o;
    wire tx_fifo_pop_fire = uart_enable && (tx_state == TX_IDLE) && !tx_fifo_empty;
    wire rx_fifo_read_fire = wb_fire && !wb_we_i &&
                             (wb_adr_i[7:0] == REG_RX_BUFFER) &&
                             !rx_fifo_empty;
    wire tx_fifo_write_fire = wb_fire && wb_we_i &&
                              (wb_adr_i[7:0] == REG_TX_BUFFER) &&
                              wb_sel_i[0] &&
                              (!tx_fifo_full || tx_fifo_pop_fire);
    wire rx_fifo_has_push_room = !rx_fifo_full || rx_fifo_read_fire;
    wire rx_fifo_push_stop1_fire = uart_enable && baud_tick &&
                                   (rx_state == RX_STOP1) &&
                                   (rx_oversample == 4'd15) &&
                                   !rx_two_stop &&
                                   rx_fifo_has_push_room;
    wire rx_fifo_push_stop2_fire = uart_enable && baud_tick &&
                                   (rx_state == RX_STOP2) &&
                                   (rx_oversample == 4'd15) &&
                                   rx_fifo_has_push_room;
    wire rx_fifo_push_fire = rx_fifo_push_stop1_fire || rx_fifo_push_stop2_fire;
    wire [7:0] status_reg = {transmit_pending, rx_fifo_full, rx_fifo_empty,
                             tx_fifo_full, tx_fifo_empty, parity_error,
                             overrun_error, framing_error};
    wire [5:0] int_status = {~rx_fifo_empty, rx_fifo_full, tx_fifo_empty,
                             parity_error, overrun_error, framing_error};

    assign uart_tx_o = tx_line;
    assign irq_o = |(int_status & int_enable);

    function [3:0] cfg_data_bits;
        input [1:0] cfg;
        begin
            case (cfg)
                2'b00: cfg_data_bits = 4'd5;
                2'b01: cfg_data_bits = 4'd6;
                2'b10: cfg_data_bits = 4'd7;
                default: cfg_data_bits = 4'd8;
            endcase
        end
    endfunction

    function parity_for;
        input [7:0] data;
        input [3:0] nbits;
        input [1:0] mode;
        integer i;
        reg p;
        begin
            p = 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                if (i < nbits) p = p ^ data[i];
            end
            case (mode)
                2'b01: parity_for = p;   // even parity
                2'b10: parity_for = ~p;  // odd parity
                default: parity_for = 1'b0;
            endcase
        end
    endfunction

    function valid_addr;
        input [7:0] addr;
        begin
            case (addr)
                REG_TX_BUFFER, REG_RX_BUFFER, REG_CONTROL, REG_STATUS,
                REG_AVAILABLE_TX, REG_AVAILABLE_RX, REG_INT_STATUS,
                REG_INT_ENABLE, REG_DIV:
                    valid_addr = 1'b1;
                default:
                    valid_addr = 1'b0;
            endcase
        end
    endfunction

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            baud_count <= 16'd0;
            baud_tick  <= 1'b0;
        end else begin
            baud_tick <= 1'b0;
            if (baud_count == 16'd0) begin
                baud_count <= (baud_div == 16'd0) ? 16'd1 : (baud_div - 16'd1);
                baud_tick <= 1'b1;
            end else begin
                baud_count <= baud_count - 16'd1;
            end
        end
    end

    task clear_tx_fifo;
        begin
            tx_rd_ptr <= 5'd0;
            tx_wr_ptr <= 5'd0;
            tx_count  <= 6'd0;
        end
    endtask

    task clear_rx_fifo;
        begin
            rx_rd_ptr <= 5'd0;
            rx_wr_ptr <= 5'd0;
            rx_count  <= 6'd0;
        end
    endtask

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o       <= 1'b0;
            wb_err_o       <= 1'b0;
            wb_dat_o       <= 32'd0;
            control_reg    <= 8'b1000_0011; // enabled, 8N1
            int_enable     <= 6'd0;
            baud_div       <= DEFAULT_DIV;
            tx_line        <= 1'b1;
            tx_state       <= TX_IDLE;
            tx_oversample  <= 4'd0;
            tx_bit_idx     <= 3'd0;
            tx_data_bits   <= 4'd8;
            tx_parity_mode <= 2'b00;
            tx_two_stop    <= 1'b0;
            tx_shift       <= 8'd0;
            tx_parity      <= 1'b0;
            rx_sync_1      <= 1'b1;
            rx_sync_2      <= 1'b1;
            rx_sync_d      <= 1'b1;
            rx_state       <= RX_IDLE;
            rx_oversample  <= 4'd0;
            rx_bit_idx     <= 3'd0;
            rx_data_bits   <= 4'd8;
            rx_parity_mode <= 2'b00;
            rx_two_stop    <= 1'b0;
            rx_shift       <= 8'd0;
            parity_error   <= 1'b0;
            overrun_error  <= 1'b0;
            framing_error  <= 1'b0;
            clear_tx_fifo();
            clear_rx_fifo();
        end else begin
            wb_ack_o  <= 1'b0;
            wb_err_o  <= 1'b0;
            rx_sync_1 <= uart_rx_i;
            rx_sync_2 <= rx_sync_1;
            rx_sync_d <= rx_sync_2;

            if (tx_fifo_pop_fire) begin
                tx_shift       <= tx_fifo[tx_rd_ptr];
                tx_rd_ptr      <= tx_rd_ptr + 5'd1;
                if (!tx_fifo_write_fire)
                    tx_count   <= tx_count - 6'd1;
                tx_data_bits   <= cfg_data_bits(control_reg[1:0]);
                tx_parity_mode <= control_reg[4:3];
                tx_two_stop    <= control_reg[2];
                tx_parity      <= parity_for(tx_fifo[tx_rd_ptr],
                                             cfg_data_bits(control_reg[1:0]),
                                             control_reg[4:3]);
                tx_bit_idx    <= 3'd0;
                tx_oversample <= 4'd0;
                tx_line       <= 1'b0;
                tx_state      <= TX_START;
            end else if (baud_tick && tx_state != TX_IDLE) begin
                if (tx_oversample != 4'd15) begin
                    tx_oversample <= tx_oversample + 4'd1;
                end else begin
                    tx_oversample <= 4'd0;
                    case (tx_state)
                        TX_START: begin
                            tx_state <= TX_DATA;
                            tx_line  <= tx_shift[0];
                        end
                        TX_DATA: begin
                            if (tx_bit_idx == tx_data_bits[2:0] - 3'd1) begin
                                if (tx_parity_mode == 2'b00) begin
                                    tx_state <= TX_STOP1;
                                    tx_line  <= 1'b1;
                                end else begin
                                    tx_state <= TX_PAR;
                                    tx_line  <= tx_parity;
                                end
                            end else begin
                                tx_bit_idx <= tx_bit_idx + 3'd1;
                                tx_line    <= tx_shift[tx_bit_idx + 3'd1];
                            end
                        end
                        TX_PAR: begin
                            tx_state <= TX_STOP1;
                            tx_line  <= 1'b1;
                        end
                        TX_STOP1: begin
                            if (tx_two_stop) begin
                                tx_state <= TX_STOP2;
                                tx_line  <= 1'b1;
                            end else begin
                                tx_state <= TX_IDLE;
                                tx_line  <= 1'b1;
                            end
                        end
                        TX_STOP2: begin
                            tx_state <= TX_IDLE;
                            tx_line  <= 1'b1;
                        end
                        default: begin
                            tx_state <= TX_IDLE;
                            tx_line  <= 1'b1;
                        end
                    endcase
                end
            end

            if (!uart_enable) begin
                rx_state <= RX_IDLE;
            end else if (rx_state == RX_IDLE) begin
                if (rx_sync_d && !rx_sync_2) begin
                    rx_state       <= RX_START;
                    rx_oversample  <= 4'd0;
                    rx_bit_idx     <= 3'd0;
                    rx_shift       <= 8'd0;
                    rx_data_bits   <= cfg_data_bits(control_reg[1:0]);
                    rx_parity_mode <= control_reg[4:3];
                    rx_two_stop    <= control_reg[2];
                end
            end else if (baud_tick) begin
                case (rx_state)
                    RX_START: begin
                        if (rx_oversample == 4'd7) begin
                            if (rx_sync_2) begin
                                rx_state <= RX_IDLE;
                            end else begin
                                rx_oversample <= 4'd0;
                                rx_state      <= RX_DATA;
                            end
                        end else begin
                            rx_oversample <= rx_oversample + 4'd1;
                        end
                    end
                    RX_DATA: begin
                        if (rx_oversample == 4'd15) begin
                            rx_shift[rx_bit_idx] <= rx_sync_2;
                            rx_oversample <= 4'd0;
                            if (rx_bit_idx == rx_data_bits[2:0] - 3'd1) begin
                                if (rx_parity_mode == 2'b00)
                                    rx_state <= RX_STOP1;
                                else
                                    rx_state <= RX_PAR;
                            end else begin
                                rx_bit_idx <= rx_bit_idx + 3'd1;
                            end
                        end else begin
                            rx_oversample <= rx_oversample + 4'd1;
                        end
                    end
                    RX_PAR: begin
                        if (rx_oversample == 4'd15) begin
                            if (rx_sync_2 != parity_for(rx_shift, rx_data_bits, rx_parity_mode))
                                parity_error <= 1'b1;
                            rx_oversample <= 4'd0;
                            rx_state <= RX_STOP1;
                        end else begin
                            rx_oversample <= rx_oversample + 4'd1;
                        end
                    end
                    RX_STOP1: begin
                        if (rx_oversample == 4'd15) begin
                            if (!rx_sync_2) framing_error <= 1'b1;
                            rx_oversample <= 4'd0;
                            if (rx_two_stop) begin
                                rx_state <= RX_STOP2;
                            end else begin
                                if (rx_fifo_full && !rx_fifo_read_fire) begin
                                    overrun_error <= 1'b1;
                                end else begin
                                    rx_fifo[rx_wr_ptr] <= rx_shift;
                                    rx_wr_ptr <= rx_wr_ptr + 5'd1;
                                    if (!rx_fifo_read_fire)
                                        rx_count <= rx_count + 6'd1;
                                end
                                rx_state <= RX_IDLE;
                            end
                        end else begin
                            rx_oversample <= rx_oversample + 4'd1;
                        end
                    end
                    RX_STOP2: begin
                        if (rx_oversample == 4'd15) begin
                            if (!rx_sync_2) framing_error <= 1'b1;
                            if (rx_fifo_full && !rx_fifo_read_fire) begin
                                overrun_error <= 1'b1;
                            end else begin
                                rx_fifo[rx_wr_ptr] <= rx_shift;
                                rx_wr_ptr <= rx_wr_ptr + 5'd1;
                                if (!rx_fifo_read_fire)
                                    rx_count <= rx_count + 6'd1;
                            end
                            rx_oversample <= 4'd0;
                            rx_state <= RX_IDLE;
                        end else begin
                            rx_oversample <= rx_oversample + 4'd1;
                        end
                    end
                    default: rx_state <= RX_IDLE;
                endcase
            end

            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                wb_err_o <= !valid_addr(wb_adr_i[7:0]);

                if (wb_we_i) begin
                    case (wb_adr_i[7:0])
                        REG_TX_BUFFER: begin
                            if (tx_fifo_write_fire) begin
`ifdef SIM_UART_PRINT
                                $write("%c", wb_dat_i[7:0]);
`endif
                                tx_fifo[tx_wr_ptr] <= wb_dat_i[7:0];
                                tx_wr_ptr <= tx_wr_ptr + 5'd1;
                                if (!tx_fifo_pop_fire)
                                    tx_count <= tx_count + 6'd1;
                            end
                        end
                        REG_CONTROL: begin
                            if (wb_sel_i[0]) begin
                                control_reg <= {wb_dat_i[7], 2'b00, wb_dat_i[4:0]};
                                if (wb_dat_i[6]) clear_tx_fifo();
                                if (wb_dat_i[5]) begin
                                    clear_rx_fifo();
                                    overrun_error <= 1'b0;
                                    framing_error <= 1'b0;
                                    parity_error  <= 1'b0;
                                end
                            end
                        end
                        REG_INT_ENABLE: begin
                            if (wb_sel_i[0]) int_enable <= wb_dat_i[5:0];
                        end
                        REG_DIV: begin
                            if (wb_sel_i[0]) baud_div[7:0]  <= wb_dat_i[7:0];
                            if (wb_sel_i[1]) baud_div[15:8] <= wb_dat_i[15:8];
                        end
                        default: ;
                    endcase
                end else begin
                    case (wb_adr_i[7:0])
                        REG_RX_BUFFER: begin
                            if (!rx_fifo_empty) begin
                                wb_dat_o <= {24'd0, rx_fifo[rx_rd_ptr]};
                                rx_rd_ptr <= rx_rd_ptr + 5'd1;
                                if (!rx_fifo_push_fire)
                                    rx_count <= rx_count - 6'd1;
                            end else begin
                                wb_dat_o <= 32'd0;
                            end
                        end
                        REG_CONTROL:      wb_dat_o <= {24'd0, control_reg};
                        REG_STATUS: begin
                            wb_dat_o <= {24'd0, status_reg};
                            parity_error  <= 1'b0;
                            overrun_error <= 1'b0;
                            framing_error <= 1'b0;
                        end
                        REG_AVAILABLE_TX: wb_dat_o <= {26'd0, tx_count};
                        REG_AVAILABLE_RX: wb_dat_o <= {26'd0, rx_count};
                        REG_INT_STATUS:   wb_dat_o <= {26'd0, int_status};
                        REG_INT_ENABLE:   wb_dat_o <= {26'd0, int_enable};
                        REG_DIV:          wb_dat_o <= {16'd0, baud_div};
                        default:          wb_dat_o <= 32'd0;
                    endcase
                end
            end
        end
    end
endmodule
