`timescale 1ns/1ps

// External Kyber data window memory for kyber_wb_slave.
//
// The old wrapper used one asynchronous byte array:
//   reg [7:0] data_mem [0:8191]
// Vivado could not map that to BRAM because the wrapper read arbitrary byte
// windows combinationally. This implementation banks the byte window by
// address[2:0] and uses synchronous true-dual-port reads.
module kyber_ext_data_bram #(
    parameter integer DATA_BYTES = 8192
)(
    input  wire        clk,

    input  wire        wb_en,
    input  wire        wb_we,
    input  wire [31:0] wb_addr,
    input  wire [31:0] wb_wdata,
    input  wire [3:0]  wb_sel,
    output reg  [31:0] wb_rdata,

    input  wire        core_re,
    input  wire        core_we,
    input  wire [31:0] core_addr,
    input  wire [63:0] core_wdata,
    input  wire [7:0]  core_wstrb,
    output reg  [63:0] core_rdata
);
    localparam integer BANKS = 8;
    localparam integer BANK_DEPTH = (DATA_BYTES + BANKS - 1) / BANKS;
    localparam integer BANK_AW = (BANK_DEPTH <= 2) ? 1 : $clog2(BANK_DEPTH);

    reg [BANK_AW-1:0] wb_bank_addr [0:BANKS-1];
    reg [7:0]         wb_bank_din  [0:BANKS-1];
    reg               wb_bank_we   [0:BANKS-1];
    wire [7:0]        wb_bank_dout [0:BANKS-1];

    reg [BANK_AW-1:0] core_bank_addr [0:BANKS-1];
    reg [7:0]         core_bank_din  [0:BANKS-1];
    reg               core_bank_we   [0:BANKS-1];
    wire [7:0]        core_bank_dout [0:BANKS-1];

    reg [2:0] wb_lane_q;
    reg [2:0] core_lane_q;

    integer wb_b;
    integer wb_i;
    integer core_b;
    integer wb_bank_idx;
    integer core_data_idx;
    reg [31:0] wb_byte_addr;
    reg [2:0]  core_lane;
    reg [BANK_AW-1:0] core_addr_base;

    always @(*) begin
        for (wb_b = 0; wb_b < BANKS; wb_b = wb_b + 1) begin
            wb_bank_addr[wb_b] = {BANK_AW{1'b0}};
            wb_bank_din[wb_b]  = 8'd0;
            wb_bank_we[wb_b]   = 1'b0;
        end

        if (wb_en) begin
            for (wb_i = 0; wb_i < 4; wb_i = wb_i + 1) begin
                wb_byte_addr = wb_addr + wb_i[31:0];
                if (wb_byte_addr < DATA_BYTES) begin
                    wb_bank_idx = wb_byte_addr[2:0];
                    wb_bank_addr[wb_bank_idx] = wb_byte_addr[31:3];
                    wb_bank_din[wb_bank_idx]  = wb_wdata[wb_i*8 +: 8];
                    wb_bank_we[wb_bank_idx]   = wb_we && wb_sel[wb_i];
                end
            end
        end
    end

    always @(*) begin
        for (core_b = 0; core_b < BANKS; core_b = core_b + 1) begin
            core_bank_addr[core_b] = {BANK_AW{1'b0}};
            core_bank_din[core_b]  = 8'd0;
            core_bank_we[core_b]   = 1'b0;
        end

        core_lane = core_addr[2:0];
        core_addr_base = core_addr[BANK_AW+2:3];

        if (core_re || core_we) begin
            for (core_b = 0; core_b < BANKS; core_b = core_b + 1) begin
                if (core_b >= core_lane) begin
                    core_data_idx = core_b - core_lane;
                    core_bank_addr[core_b] = core_addr_base;
                end else begin
                    core_data_idx = core_b + BANKS - core_lane;
                    core_bank_addr[core_b] = core_addr_base + {{(BANK_AW-1){1'b0}}, 1'b1};
                end
                core_bank_din[core_b] = core_wdata[core_data_idx*8 +: 8];
                core_bank_we[core_b]  = core_we && core_wstrb[core_data_idx];
            end
        end
    end

    always @(posedge clk) begin
        if (wb_en)
            wb_lane_q <= wb_addr[2:0];
    end

    always @(negedge clk) begin
        if (core_re)
            core_lane_q <= core_addr[2:0];
    end

    always @(*) begin
        case (wb_lane_q)
            3'd0: wb_rdata = {wb_bank_dout[3], wb_bank_dout[2], wb_bank_dout[1], wb_bank_dout[0]};
            3'd1: wb_rdata = {wb_bank_dout[4], wb_bank_dout[3], wb_bank_dout[2], wb_bank_dout[1]};
            3'd2: wb_rdata = {wb_bank_dout[5], wb_bank_dout[4], wb_bank_dout[3], wb_bank_dout[2]};
            3'd3: wb_rdata = {wb_bank_dout[6], wb_bank_dout[5], wb_bank_dout[4], wb_bank_dout[3]};
            3'd4: wb_rdata = {wb_bank_dout[7], wb_bank_dout[6], wb_bank_dout[5], wb_bank_dout[4]};
            3'd5: wb_rdata = {wb_bank_dout[0], wb_bank_dout[7], wb_bank_dout[6], wb_bank_dout[5]};
            3'd6: wb_rdata = {wb_bank_dout[1], wb_bank_dout[0], wb_bank_dout[7], wb_bank_dout[6]};
            default: wb_rdata = {wb_bank_dout[2], wb_bank_dout[1], wb_bank_dout[0], wb_bank_dout[7]};
        endcase
    end

    always @(*) begin
        case (core_lane_q)
            3'd0: core_rdata = {core_bank_dout[7], core_bank_dout[6], core_bank_dout[5], core_bank_dout[4],
                                core_bank_dout[3], core_bank_dout[2], core_bank_dout[1], core_bank_dout[0]};
            3'd1: core_rdata = {core_bank_dout[0], core_bank_dout[7], core_bank_dout[6], core_bank_dout[5],
                                core_bank_dout[4], core_bank_dout[3], core_bank_dout[2], core_bank_dout[1]};
            3'd2: core_rdata = {core_bank_dout[1], core_bank_dout[0], core_bank_dout[7], core_bank_dout[6],
                                core_bank_dout[5], core_bank_dout[4], core_bank_dout[3], core_bank_dout[2]};
            3'd3: core_rdata = {core_bank_dout[2], core_bank_dout[1], core_bank_dout[0], core_bank_dout[7],
                                core_bank_dout[6], core_bank_dout[5], core_bank_dout[4], core_bank_dout[3]};
            3'd4: core_rdata = {core_bank_dout[3], core_bank_dout[2], core_bank_dout[1], core_bank_dout[0],
                                core_bank_dout[7], core_bank_dout[6], core_bank_dout[5], core_bank_dout[4]};
            3'd5: core_rdata = {core_bank_dout[4], core_bank_dout[3], core_bank_dout[2], core_bank_dout[1],
                                core_bank_dout[0], core_bank_dout[7], core_bank_dout[6], core_bank_dout[5]};
            3'd6: core_rdata = {core_bank_dout[5], core_bank_dout[4], core_bank_dout[3], core_bank_dout[2],
                                core_bank_dout[1], core_bank_dout[0], core_bank_dout[7], core_bank_dout[6]};
            default: core_rdata = {core_bank_dout[6], core_bank_dout[5], core_bank_dout[4], core_bank_dout[3],
                                   core_bank_dout[2], core_bank_dout[1], core_bank_dout[0], core_bank_dout[7]};
        endcase
    end

    genvar g;
    generate
        for (g = 0; g < BANKS; g = g + 1) begin : gen_bank
            (* ram_style = "block" *) reg [7:0] mem [0:BANK_DEPTH-1];
            reg [7:0] wb_dout_r;
            reg [7:0] core_dout_r;
            integer init_i;

            assign wb_bank_dout[g] = wb_dout_r;
            assign core_bank_dout[g] = core_dout_r;

            initial begin
                for (init_i = 0; init_i < BANK_DEPTH; init_i = init_i + 1)
                    mem[init_i] = 8'd0;
                wb_dout_r = 8'd0;
                core_dout_r = 8'd0;
            end

            always @(posedge clk) begin
                if (wb_bank_we[g])
                    mem[wb_bank_addr[g]] <= wb_bank_din[g];
                wb_dout_r <= mem[wb_bank_addr[g]];
            end

            always @(negedge clk) begin
                if (core_bank_we[g])
                    mem[core_bank_addr[g]] <= core_bank_din[g];
                core_dout_r <= mem[core_bank_addr[g]];
            end
        end
    endgenerate
endmodule
