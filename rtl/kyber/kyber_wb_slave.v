`timescale 1ns/1ps

// Wishbone wrapper for kyber512_core_fsm.
//
// Address map relative to KYBER_BASE:
//   0x0000..0x1FFF  Core external byte RAM (PK/SK/CT/SS windows)
//   0x3000..0x303F  64-byte seed input window
//   0x4000          CTRL: bit0 start, bits[2:1] opcode, bit8 soft reset
//   0x4004          STATUS: bit0 busy, bit1 done, bit2 error, bits[15:8] state
//   0x4008          IRQ_ENABLE: bit0 done IRQ enable
//   0x400C          IRQ_STATUS: bit0 done IRQ status, W1C
//   0x4010          CYCLE_COUNT
module kyber_wb_slave #(
    parameter integer DATA_BYTES = 8192
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
    output wire        irq_o
);
    localparam [31:0] SEED_OFFSET        = 32'h0000_3000;
    localparam [31:0] SEED_BYTES         = 32'd64;
    localparam [31:0] CTRL_OFFSET        = 32'h0000_4000;
    localparam [31:0] STATUS_OFFSET      = 32'h0000_4004;
    localparam [31:0] IRQ_ENABLE_OFFSET  = 32'h0000_4008;
    localparam [31:0] IRQ_STATUS_OFFSET  = 32'h0000_400C;
    localparam [31:0] CYCLE_COUNT_OFFSET = 32'h0000_4010;

    localparam [1:0] OPCODE_KEYGEN = 2'b01;
    localparam [1:0] OPCODE_ENCAPS = 2'b10;
    localparam [1:0] OPCODE_DECAPS = 2'b11;

    reg [7:0] seed_mem [0:63];

    reg [1:0]  core_opcode;
    reg        core_start;
    reg        core_rst_pulse;
    reg        done_latched;
    reg        error_latched;
    reg        irq_enable_done;
    reg        irq_status_done;
    reg [31:0] cycle_count;

    wire        core_done;
    wire        core_busy;
    wire        core_ext_we;
    wire        core_ext_re;
    wire [31:0] core_ext_addr;
    wire [63:0] core_ext_dout;
    wire [7:0]  core_ext_wstrb;
    wire [63:0] core_ext_din;
    wire        core_ext_ready;
    reg  [511:0] core_seed_in;
    wire [7:0]  core_state_dbg;
    wire        core_rst = wb_rst_i | core_rst_pulse;

    assign irq_o = irq_enable_done & irq_status_done;

    integer init_i;
    initial begin
        for (init_i = 0; init_i < 64; init_i = init_i + 1)
            seed_mem[init_i] = 8'd0;
    end

    function addr_in_data;
        input [31:0] addr;
        begin
            addr_in_data = (addr < DATA_BYTES);
        end
    endfunction

    function addr_in_seed;
        input [31:0] addr;
        begin
            addr_in_seed = (addr >= SEED_OFFSET) &&
                           (addr < (SEED_OFFSET + SEED_BYTES));
        end
    endfunction

    function addr_is_csr;
        input [31:0] addr;
        begin
            case (addr)
                CTRL_OFFSET, STATUS_OFFSET, IRQ_ENABLE_OFFSET,
                IRQ_STATUS_OFFSET, CYCLE_COUNT_OFFSET:
                    addr_is_csr = 1'b1;
                default:
                    addr_is_csr = 1'b0;
            endcase
        end
    endfunction

    function wb_addr_valid;
        input [31:0] addr;
        begin
            wb_addr_valid = addr_in_data(addr) || addr_in_seed(addr) || addr_is_csr(addr);
        end
    endfunction

    function [7:0] read_seed_byte;
        input [31:0] addr;
        begin
            if (addr_in_seed(addr))
                read_seed_byte = seed_mem[addr - SEED_OFFSET];
            else
                read_seed_byte = 8'd0;
        end
    endfunction

    function [31:0] build_wb_read_data;
        input [31:0] addr;
        integer bi;
        begin
            build_wb_read_data = 32'd0;
            if (addr_in_seed(addr)) begin
                for (bi = 0; bi < 4; bi = bi + 1)
                    build_wb_read_data[bi*8 +: 8] = read_seed_byte(addr + bi);
            end else begin
                case (addr)
                    CTRL_OFFSET:
                        build_wb_read_data = {23'd0, 1'b0, 5'd0, core_opcode, 1'b0};
                    STATUS_OFFSET:
                        build_wb_read_data = {16'd0, core_state_dbg,
                                              5'd0, error_latched,
                                              done_latched, core_busy};
                    IRQ_ENABLE_OFFSET:
                        build_wb_read_data = {31'd0, irq_enable_done};
                    IRQ_STATUS_OFFSET:
                        build_wb_read_data = {31'd0, irq_status_done};
                    CYCLE_COUNT_OFFSET:
                        build_wb_read_data = cycle_count;
                    default:
                        build_wb_read_data = 32'd0;
                endcase
            end
        end
    endfunction

    function valid_opcode;
        input [1:0] opcode;
        begin
            valid_opcode = (opcode == OPCODE_KEYGEN) ||
                           (opcode == OPCODE_ENCAPS) ||
                           (opcode == OPCODE_DECAPS);
        end
    endfunction

    integer seed_i;
    always @(*) begin
        core_seed_in = 512'd0;
        for (seed_i = 0; seed_i < 64; seed_i = seed_i + 1)
            core_seed_in[511 - (seed_i*8) -: 8] = seed_mem[seed_i];
    end

    reg wb_pending;
    reg wb_pending_err;
    reg wb_pending_read_is_data;
    reg [31:0] wb_pending_read_data;

    wire wb_fire = wb_cyc_i && wb_stb_i && !wb_ack_o && !wb_pending;
    wire wb_busy_write_blocked =
        core_busy && wb_we_i &&
        (addr_in_data(wb_adr_i) || addr_in_seed(wb_adr_i));

    wire wb_data_mem_access = wb_fire && addr_in_data(wb_adr_i) &&
                              !wb_busy_write_blocked;
    wire wb_data_mem_we = wb_data_mem_access && wb_we_i;
    wire wb_data_mem_en = wb_data_mem_access;
    wire [31:0] data_mem_wb_rdata;

    wire core_ext_range_ok = ((core_ext_addr + 32'd7) < DATA_BYTES);
    wire core_write_issue = core_ext_we && core_ext_range_ok;
    wire [63:0] data_mem_core_rdata;

    assign core_ext_ready = 1'b1;
    assign core_ext_din = data_mem_core_rdata;

    kyber_ext_data_bram #(
        .DATA_BYTES(DATA_BYTES)
    ) u_data_mem (
        .clk(wb_clk_i),
        .wb_en(wb_data_mem_en),
        .wb_we(wb_data_mem_we),
        .wb_addr(wb_adr_i),
        .wb_wdata(wb_dat_i),
        .wb_sel(wb_sel_i),
        .wb_rdata(data_mem_wb_rdata),
        .core_re(1'b1),
        .core_we(core_write_issue),
        .core_addr(core_ext_addr),
        .core_wdata(core_ext_dout),
        .core_wstrb(core_ext_wstrb),
        .core_rdata(data_mem_core_rdata)
    );

    integer wr_i;
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o        <= 1'b0;
            wb_err_o        <= 1'b0;
            wb_dat_o        <= 32'd0;
            core_opcode     <= OPCODE_KEYGEN;
            core_start      <= 1'b0;
            core_rst_pulse  <= 1'b0;
            done_latched    <= 1'b0;
            error_latched   <= 1'b0;
            irq_enable_done <= 1'b0;
            irq_status_done <= 1'b0;
            cycle_count     <= 32'd0;
            wb_pending      <= 1'b0;
            wb_pending_err  <= 1'b0;
            wb_pending_read_is_data <= 1'b0;
            wb_pending_read_data    <= 32'd0;
        end else begin
            wb_ack_o       <= 1'b0;
            wb_err_o       <= 1'b0;
            core_start     <= 1'b0;
            core_rst_pulse <= 1'b0;

            if (core_busy)
                cycle_count <= cycle_count + 32'd1;

            if ((core_ext_we || core_ext_re) && !core_ext_range_ok) begin
                error_latched <= 1'b1;
            end

            if (core_done) begin
                done_latched    <= 1'b1;
                irq_status_done <= 1'b1;
            end

            if (wb_pending) begin
                wb_ack_o <= 1'b1;
                wb_err_o <= wb_pending_err;
                wb_dat_o <= wb_pending_read_is_data ?
                            data_mem_wb_rdata : wb_pending_read_data;
                wb_pending <= 1'b0;
            end

            if (wb_fire) begin
                wb_pending <= 1'b1;
                wb_pending_err <= !wb_addr_valid(wb_adr_i) || wb_busy_write_blocked;
                wb_pending_read_is_data <= !wb_we_i && addr_in_data(wb_adr_i) &&
                                           wb_addr_valid(wb_adr_i) &&
                                           !wb_busy_write_blocked;
                wb_pending_read_data <= build_wb_read_data(wb_adr_i);

                if (wb_we_i && wb_addr_valid(wb_adr_i) && !wb_busy_write_blocked) begin
                    if (addr_in_seed(wb_adr_i)) begin
                        for (wr_i = 0; wr_i < 4; wr_i = wr_i + 1) begin
                            if (wb_sel_i[wr_i] && addr_in_seed(wb_adr_i + wr_i))
                                seed_mem[(wb_adr_i + wr_i) - SEED_OFFSET] <= wb_dat_i[wr_i*8 +: 8];
                        end
                    end else begin
                        case (wb_adr_i)
                            CTRL_OFFSET: begin
                                if (wb_sel_i[1] && wb_dat_i[8]) begin
                                    core_rst_pulse  <= 1'b1;
                                    done_latched    <= 1'b0;
                                    error_latched   <= 1'b0;
                                    irq_status_done <= 1'b0;
                                    cycle_count     <= 32'd0;
                                end

                                if (wb_sel_i[0]) begin
                                    if (valid_opcode(wb_dat_i[2:1]))
                                        core_opcode <= wb_dat_i[2:1];

                                    if (wb_dat_i[0]) begin
                                        if (!core_busy && valid_opcode(wb_dat_i[2:1])) begin
                                            core_opcode     <= wb_dat_i[2:1];
                                            core_start      <= 1'b1;
                                            done_latched    <= 1'b0;
                                            error_latched   <= 1'b0;
                                            irq_status_done <= 1'b0;
                                            cycle_count     <= 32'd0;
                                        end else begin
                                            error_latched <= 1'b1;
                                        end
                                    end
                                end
                            end
                            IRQ_ENABLE_OFFSET: begin
                                if (wb_sel_i[0])
                                    irq_enable_done <= wb_dat_i[0];
                            end
                            IRQ_STATUS_OFFSET: begin
                                if (wb_sel_i[0] && wb_dat_i[0])
                                    irq_status_done <= 1'b0;
                            end
                            default: ;
                        endcase
                    end
                end
            end
        end
    end

    kyber512_core_fsm u_core (
        .clk(wb_clk_i),
        .rst(core_rst),
        .start(core_start),
        .opcode(core_opcode),
        .done(core_done),
        .busy(core_busy),
        .ext_we(core_ext_we),
        .ext_re(core_ext_re),
        .ext_addr(core_ext_addr),
        .ext_dout(core_ext_dout),
        .ext_wstrb(core_ext_wstrb),
        .ext_din(core_ext_din),
        .ext_ready(core_ext_ready),
        .seed_in(core_seed_in),
        .seed_valid(1'b1),
        .state_dbg(core_state_dbg)
    );
endmodule
