`timescale 1ns/1ps

// 8-source programmable interrupt controller.
module pic_wb #(
    parameter integer NIRQ = 8
)(
    input  wire             wb_clk_i,
    input  wire             wb_rst_i,
    input  wire [31:0]      wb_adr_i,
    input  wire [31:0]      wb_dat_i,
    output reg  [31:0]      wb_dat_o,
    input  wire [3:0]       wb_sel_i,
    input  wire             wb_we_i,
    input  wire             wb_cyc_i,
    input  wire             wb_stb_i,
    output reg              wb_ack_o,
    output reg              wb_err_o,

    input  wire [NIRQ-1:0]  irq_sources_i,
    output wire             irq_o,
    output wire [31:0]      irq_vector_o
);
    localparam [7:0] REG_PIC_STATUS = 8'h00;
    localparam [7:0] REG_PIC_ENABLE = 8'h04;
    localparam [7:0] REG_PIC_RAW    = 8'h08;

    reg [NIRQ-1:0] pic_status;
    reg [NIRQ-1:0] pic_enable;

    assign irq_vector_o = {{(32-NIRQ){1'b0}}, (pic_status & pic_enable)};
    assign irq_o        = |(pic_status & pic_enable);

    function [NIRQ-1:0] apply_wstrb_irq;
        input [NIRQ-1:0] oldv;
        input [31:0]     newv;
        input [3:0]      sel;
        integer i;
        begin
            apply_wstrb_irq = oldv;
            for (i = 0; i < NIRQ; i = i + 1) begin
                if (sel[i/8]) apply_wstrb_irq[i] = newv[i];
            end
        end
    endfunction

    function [31:0] zext_irq;
        input [NIRQ-1:0] v;
        integer i;
        begin
            zext_irq = 32'd0;
            for (i = 0; i < NIRQ; i = i + 1)
                zext_irq[i] = v[i];
        end
    endfunction

    function valid_addr;
        input [7:0] addr;
        begin
            case (addr)
                REG_PIC_STATUS, REG_PIC_ENABLE, REG_PIC_RAW:
                    valid_addr = 1'b1;
                default:
                    valid_addr = 1'b0;
            endcase
        end
    endfunction

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o   <= 1'b0;
            wb_err_o   <= 1'b0;
            wb_dat_o   <= 32'd0;
            pic_status <= {NIRQ{1'b0}};
            pic_enable <= {NIRQ{1'b0}};
        end else begin
            wb_ack_o   <= 1'b0;
            wb_err_o   <= 1'b0;
            pic_status <= pic_status | irq_sources_i;

            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                wb_err_o <= !valid_addr(wb_adr_i[7:0]);

                if (wb_we_i) begin
                    case (wb_adr_i[7:0])
                        REG_PIC_STATUS: pic_status <= (pic_status | irq_sources_i) &
                                                       ~apply_wstrb_irq({NIRQ{1'b0}}, wb_dat_i, wb_sel_i);
                        REG_PIC_ENABLE: pic_enable <= apply_wstrb_irq(pic_enable, wb_dat_i, wb_sel_i);
                        default: ;
                    endcase
                end else begin
                    case (wb_adr_i[7:0])
                        REG_PIC_STATUS: wb_dat_o <= zext_irq(pic_status);
                        REG_PIC_ENABLE: wb_dat_o <= zext_irq(pic_enable);
                        REG_PIC_RAW:    wb_dat_o <= zext_irq(irq_sources_i);
                        default:        wb_dat_o <= 32'd0;
                    endcase
                end
            end
        end
    end
endmodule
