`timescale 1ns/1ps

// 16-bit Wishbone timer used by the Kyber-512 SoC register map.
module timer_wb(
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
    output wire        irq_o
);
    localparam [7:0] REG_CTRL      = 8'h00;
    localparam [7:0] REG_COUNT     = 8'h04;
    localparam [7:0] REG_PERIOD    = 8'h08;
    localparam [7:0] REG_STATUS    = 8'h0C;
    localparam [7:0] REG_PRESCALER = 8'h10;

    reg        count_enable;
    reg        count_down;
    reg        irq_enable;
    reg        auto_reload;
    reg        prescaler_enable;
    reg [15:0] count_reg;
    reg [15:0] period_reg;
    reg [15:0] status_reg;
    reg [15:0] prescaler_reg;
    reg [15:0] prescaler_count;

    assign irq_o = irq_enable & |status_reg[2:0];

    function [15:0] apply_wstrb16;
        input [15:0] oldv;
        input [31:0] newv;
        input [3:0]  sel;
        begin
            apply_wstrb16 = oldv;
            if (sel[0]) apply_wstrb16[7:0]  = newv[7:0];
            if (sel[1]) apply_wstrb16[15:8] = newv[15:8];
        end
    endfunction

    function valid_addr;
        input [7:0] addr;
        begin
            case (addr)
                REG_CTRL, REG_COUNT, REG_PERIOD, REG_STATUS, REG_PRESCALER:
                    valid_addr = 1'b1;
                default:
                    valid_addr = 1'b0;
            endcase
        end
    endfunction

    reg do_count;
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o         <= 1'b0;
            wb_err_o         <= 1'b0;
            wb_dat_o         <= 32'd0;
            count_enable     <= 1'b0;
            count_down       <= 1'b0;
            irq_enable       <= 1'b0;
            auto_reload      <= 1'b0;
            prescaler_enable <= 1'b0;
            count_reg        <= 16'd0;
            period_reg       <= 16'hFFFF;
            status_reg       <= 16'd0;
            prescaler_reg    <= 16'hFFFF;
            prescaler_count  <= 16'd0;
        end else begin
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;
            do_count = 1'b0;

            if (count_enable) begin
                if (prescaler_enable) begin
                    if ((prescaler_reg == 16'd0) ||
                        (prescaler_count >= (prescaler_reg - 16'd1))) begin
                        prescaler_count <= 16'd0;
                        do_count = 1'b1;
                    end else begin
                        prescaler_count <= prescaler_count + 16'd1;
                    end
                end else begin
                    prescaler_count <= 16'd0;
                    do_count = 1'b1;
                end
            end else begin
                prescaler_count <= 16'd0;
            end

            if (do_count) begin
                if (count_reg == period_reg) begin
                    status_reg[0] <= 1'b1;
                    if (auto_reload)
                        count_reg <= count_down ? 16'hFFFF : 16'd0;
                end else if (!count_down) begin
                    if (count_reg == 16'hFFFF) begin
                        status_reg[1] <= 1'b1;
                    end else begin
                        count_reg <= count_reg + 16'd1;
                    end
                end else begin
                    if (count_reg == 16'd0) begin
                        status_reg[2] <= 1'b1;
                    end else begin
                        count_reg <= count_reg - 16'd1;
                    end
                end
            end

            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                wb_err_o <= !valid_addr(wb_adr_i[7:0]);

                if (wb_we_i) begin
                    case (wb_adr_i[7:0])
                        REG_CTRL: begin
                            if (wb_sel_i[0]) begin
                                count_enable     <= wb_dat_i[0];
                                count_down       <= wb_dat_i[1];
                                irq_enable       <= wb_dat_i[2];
                                auto_reload      <= wb_dat_i[3];
                                prescaler_enable <= wb_dat_i[4];
                            end
                        end
                        REG_COUNT:     count_reg     <= apply_wstrb16(count_reg,     wb_dat_i, wb_sel_i);
                        REG_PERIOD:    period_reg    <= apply_wstrb16(period_reg,    wb_dat_i, wb_sel_i);
                        REG_PRESCALER: prescaler_reg <= apply_wstrb16(prescaler_reg, wb_dat_i, wb_sel_i);
                        REG_STATUS:    status_reg    <= status_reg & ~apply_wstrb16(16'd0, wb_dat_i, wb_sel_i);
                        default: ;
                    endcase
                end else begin
                    case (wb_adr_i[7:0])
                        REG_CTRL: begin
                            wb_dat_o <= {27'd0, prescaler_enable, auto_reload,
                                         irq_enable, count_down, count_enable};
                        end
                        REG_COUNT:     wb_dat_o <= {16'd0, count_reg};
                        REG_PERIOD:    wb_dat_o <= {16'd0, period_reg};
                        REG_STATUS: begin
                            wb_dat_o   <= {24'd0, status_reg[7:0]};
                            status_reg <= 16'd0;
                        end
                        REG_PRESCALER: wb_dat_o <= {16'd0, prescaler_reg};
                        default:       wb_dat_o <= 32'd0;
                    endcase
                end
            end
        end
    end
endmodule
