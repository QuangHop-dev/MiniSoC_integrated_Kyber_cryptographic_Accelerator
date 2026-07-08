`timescale 1ns/1ps

// Open-drain I2C master with an OpenCores-style byte register map.
// Byte lanes are honored so RV32 byte loads/stores can access offsets 0..4.
module i2c_wb(
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

    input  wire        scl_i,
    output wire        scl_o,
    output wire        scl_oe,
    input  wire        sda_i,
    output wire        sda_o,
    output wire        sda_oe,
    output wire        irq_o
);
    localparam [7:0] REG_PRER_LO = 8'h00;
    localparam [7:0] REG_PRER_HI = 8'h01;
    localparam [7:0] REG_CTR     = 8'h02;
    localparam [7:0] REG_TXR_RXR = 8'h03;
    localparam [7:0] REG_CR_SR   = 8'h04;

    localparam [3:0] ST_IDLE      = 4'd0;
    localparam [3:0] ST_START_A   = 4'd1;
    localparam [3:0] ST_START_B   = 4'd2;
    localparam [3:0] ST_START_C   = 4'd3;
    localparam [3:0] ST_WRITE_LOW = 4'd4;
    localparam [3:0] ST_WRITE_HI  = 4'd5;
    localparam [3:0] ST_WACK_LOW  = 4'd6;
    localparam [3:0] ST_WACK_HI   = 4'd7;
    localparam [3:0] ST_READ_LOW  = 4'd8;
    localparam [3:0] ST_READ_HI   = 4'd9;
    localparam [3:0] ST_RACK_LOW  = 4'd10;
    localparam [3:0] ST_RACK_HI   = 4'd11;
    localparam [3:0] ST_STOP_A    = 4'd12;
    localparam [3:0] ST_STOP_B    = 4'd13;
    localparam [3:0] ST_STOP_C    = 4'd14;
    localparam [3:0] ST_DONE      = 4'd15;

    reg [7:0] prer_lo;
    reg [7:0] prer_hi;
    reg [7:0] ctr;
    reg [7:0] txr;
    reg [7:0] rxr;
    reg [7:0] shifter;
    reg [3:0] state;
    reg [2:0] bit_count;
    reg [15:0] clk_count;
    reg tick;

    reg scl_drive_low;
    reg sda_drive_low;
    reg rxack;
    reg busy;
    reg arbitration_lost;
    reg transfer_in_progress;
    reg irq_flag;

    reg cmd_stop;
    reg cmd_read;
    reg cmd_write;
    reg cmd_ack;

    wire core_enable = ctr[7];
    wire irq_enable  = ctr[6];
    wire [15:0] prescale = {prer_hi, prer_lo};
    wire [7:0] status_reg = {rxack, busy, arbitration_lost, 3'b000,
                             transfer_in_progress, irq_flag};

    assign scl_o  = 1'b0;
    assign sda_o  = 1'b0;
    assign scl_oe = scl_drive_low;
    assign sda_oe = sda_drive_low;
    assign irq_o  = irq_enable & irq_flag;

    function valid_addr;
        input [7:0] addr;
        begin
            case (addr)
                REG_PRER_LO, REG_PRER_HI, REG_CTR, REG_TXR_RXR, REG_CR_SR:
                    valid_addr = 1'b1;
                default:
                    valid_addr = 1'b0;
            endcase
        end
    endfunction

    function wb_has_byte;
        input [3:0] sel;
        begin
            wb_has_byte = |sel;
        end
    endfunction

    function [7:0] wb_write_byte;
        input [31:0] data;
        input [3:0]  sel;
        input [1:0]  lane;
        begin
            if (sel[lane]) begin
                case (lane)
                    2'd0: wb_write_byte = data[7:0];
                    2'd1: wb_write_byte = data[15:8];
                    2'd2: wb_write_byte = data[23:16];
                    default: wb_write_byte = data[31:24];
                endcase
            end else if (sel[0]) begin
                wb_write_byte = data[7:0];
            end else if (sel[1]) begin
                wb_write_byte = data[15:8];
            end else if (sel[2]) begin
                wb_write_byte = data[23:16];
            end else begin
                wb_write_byte = data[31:24];
            end
        end
    endfunction

    wire wb_wbyte_valid = wb_has_byte(wb_sel_i);
    wire [7:0] wb_wbyte = wb_write_byte(wb_dat_i, wb_sel_i, wb_adr_i[1:0]);

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            clk_count <= 16'd0;
            tick      <= 1'b0;
        end else begin
            tick <= 1'b0;
            if (!transfer_in_progress) begin
                clk_count <= 16'd0;
            end else if (clk_count == 16'd0) begin
                clk_count <= prescale;
                tick <= 1'b1;
            end else begin
                clk_count <= clk_count - 16'd1;
            end
        end
    end

    task finish_command;
        begin
            transfer_in_progress <= 1'b0;
            irq_flag <= 1'b1;
            state <= ST_IDLE;
            if (!busy) begin
                scl_drive_low <= 1'b0;
                sda_drive_low <= 1'b0;
            end
        end
    endtask

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o             <= 1'b0;
            wb_err_o             <= 1'b0;
            wb_dat_o             <= 32'd0;
            prer_lo              <= 8'hFF;
            prer_hi              <= 8'h00;
            ctr                  <= 8'd0;
            txr                  <= 8'd0;
            rxr                  <= 8'd0;
            shifter              <= 8'd0;
            state                <= ST_IDLE;
            bit_count            <= 3'd7;
            scl_drive_low        <= 1'b0;
            sda_drive_low        <= 1'b0;
            rxack                <= 1'b1;
            busy                 <= 1'b0;
            arbitration_lost     <= 1'b0;
            transfer_in_progress <= 1'b0;
            irq_flag             <= 1'b0;
            cmd_stop             <= 1'b0;
            cmd_read             <= 1'b0;
            cmd_write            <= 1'b0;
            cmd_ack              <= 1'b0;
        end else begin
            wb_ack_o <= 1'b0;
            wb_err_o <= 1'b0;

            if (tick) begin
                case (state)
                    ST_START_A: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        state <= ST_START_B;
                    end
                    ST_START_B: begin
                        sda_drive_low <= 1'b1;
                        busy <= 1'b1;
                        state <= ST_START_C;
                    end
                    ST_START_C: begin
                        scl_drive_low <= 1'b1;
                        shifter <= txr;
                        bit_count <= 3'd7;
                        state <= cmd_write ? ST_WRITE_LOW :
                                 (cmd_read ? ST_READ_LOW :
                                  (cmd_stop ? ST_STOP_A : ST_DONE));
                    end
                    ST_WRITE_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= ~shifter[7];
                        state <= ST_WRITE_HI;
                    end
                    ST_WRITE_HI: begin
                        scl_drive_low <= 1'b0;
                        if (shifter[7] && !sda_i)
                            arbitration_lost <= 1'b1;
                        state <= (bit_count == 3'd0) ? ST_WACK_LOW : ST_WRITE_LOW;
                        shifter <= {shifter[6:0], 1'b0};
                        if (bit_count != 3'd0)
                            bit_count <= bit_count - 3'd1;
                    end
                    ST_WACK_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b0;
                        state <= ST_WACK_HI;
                    end
                    ST_WACK_HI: begin
                        scl_drive_low <= 1'b0;
                        rxack <= sda_i;
                        state <= cmd_stop ? ST_STOP_A : ST_DONE;
                    end
                    ST_READ_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b0;
                        state <= ST_READ_HI;
                    end
                    ST_READ_HI: begin
                        scl_drive_low <= 1'b0;
                        shifter <= {shifter[6:0], sda_i};
                        state <= (bit_count == 3'd0) ? ST_RACK_LOW : ST_READ_LOW;
                        if (bit_count != 3'd0)
                            bit_count <= bit_count - 3'd1;
                    end
                    ST_RACK_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= ~cmd_ack; // ACK=0 drives low, NACK=1 releases.
                        state <= ST_RACK_HI;
                    end
                    ST_RACK_HI: begin
                        scl_drive_low <= 1'b0;
                        rxr <= shifter;
                        state <= cmd_stop ? ST_STOP_A : ST_DONE;
                    end
                    ST_STOP_A: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b1;
                        state <= ST_STOP_B;
                    end
                    ST_STOP_B: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b1;
                        state <= ST_STOP_C;
                    end
                    ST_STOP_C: begin
                        sda_drive_low <= 1'b0;
                        busy <= 1'b0;
                        state <= ST_DONE;
                    end
                    ST_DONE: begin
                        finish_command();
                    end
                    default: state <= ST_IDLE;
                endcase
            end

            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                wb_err_o <= !valid_addr(wb_adr_i[7:0]);

                if (wb_we_i) begin
                    case (wb_adr_i[7:0])
                        REG_PRER_LO: if (wb_wbyte_valid && !core_enable) prer_lo <= wb_wbyte;
                        REG_PRER_HI: if (wb_wbyte_valid && !core_enable) prer_hi <= wb_wbyte;
                        REG_CTR:     if (wb_wbyte_valid) ctr <= {wb_wbyte[7:6], 6'd0};
                        REG_TXR_RXR: if (wb_wbyte_valid) txr <= wb_wbyte;
                        REG_CR_SR: begin
                            if (wb_wbyte_valid) begin
                                if (wb_wbyte[0])
                                    irq_flag <= 1'b0;
                                if (core_enable && !transfer_in_progress &&
                                    |wb_wbyte[7:4]) begin
                                    cmd_stop <= wb_wbyte[6];
                                    cmd_read <= wb_wbyte[5];
                                    cmd_write <= wb_wbyte[4];
                                    cmd_ack <= wb_wbyte[3];
                                    irq_flag <= 1'b0;
                                    arbitration_lost <= 1'b0;
                                    transfer_in_progress <= 1'b1;
                                    state <= wb_wbyte[7] ? ST_START_A :
                                             (wb_wbyte[4] ? ST_WRITE_LOW :
                                              (wb_wbyte[5] ? ST_READ_LOW :
                                               (wb_wbyte[6] ? ST_STOP_A : ST_DONE)));
                                    if (!wb_wbyte[7]) begin
                                        shifter <= txr;
                                        bit_count <= 3'd7;
                                    end
                                end
                            end
                        end
                        default: ;
                    endcase
                end else begin
                    case (wb_adr_i[7:0])
                        REG_PRER_LO: wb_dat_o <= {4{prer_lo}};
                        REG_PRER_HI: wb_dat_o <= {4{prer_hi}};
                        REG_CTR:     wb_dat_o <= {4{ctr}};
                        REG_TXR_RXR: wb_dat_o <= {4{rxr}};
                        REG_CR_SR:   wb_dat_o <= {4{status_reg}};
                        default:     wb_dat_o <= 32'd0;
                    endcase
                end
            end
        end
    end
endmodule
