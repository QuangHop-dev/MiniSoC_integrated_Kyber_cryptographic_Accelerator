`timescale 1ns/1ps

// Two-stage RV32I/Zicsr CPU with one Wishbone master port.
//
// This implementation matches the CPU datapath diagram used in the report:
//   Stage 1: PC, instruction fetch, controller/decode, register file,
//            forwarding muxes, and immediate generation.
//   Stage 2: ID/EX register, ALU, jump execute, CSR, trap logic,
//            hazard/stall control, Wishbone master interface, and writeback mux.
module rv32i_2stage_wb #(
    parameter [31:0] RESET_VECTOR = 32'h0000_0000,
    parameter [31:0] IRQ_VECTOR   = 32'h0000_0100
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        irq_i,
    output reg         trap_o,
    output reg         halted_o,
    output reg  [31:0] fault_pc_o,
    output reg  [31:0] fault_cause_o,
    output wire [31:0] pc_debug_o,

    output reg  [31:0] wb_adr_o,
    output reg  [31:0] wb_dat_o,
    input  wire [31:0] wb_dat_i,
    output reg  [3:0]  wb_sel_o,
    output reg         wb_we_o,
    output reg         wb_cyc_o,
    output reg         wb_stb_o,
    input  wire        wb_ack_i,
    input  wire        wb_err_i
);
    localparam [3:0] ALU_ADD  = 4'd0;
    localparam [3:0] ALU_SUB  = 4'd1;
    localparam [3:0] ALU_SLL  = 4'd2;
    localparam [3:0] ALU_SLT  = 4'd3;
    localparam [3:0] ALU_SLTU = 4'd4;
    localparam [3:0] ALU_XOR  = 4'd5;
    localparam [3:0] ALU_SRL  = 4'd6;
    localparam [3:0] ALU_SRA  = 4'd7;
    localparam [3:0] ALU_OR   = 4'd8;
    localparam [3:0] ALU_AND  = 4'd9;
    localparam [3:0] ALU_PASS = 4'd10;

    localparam [2:0] WB_ALU = 3'd0;
    localparam [2:0] WB_MEM = 3'd1;
    localparam [2:0] WB_PC4 = 3'd2;
    localparam [2:0] WB_IMM = 3'd3;
    localparam [2:0] WB_CSR = 3'd4;

    localparam [1:0] CSR_WRITE = 2'd0;
    localparam [1:0] CSR_SET   = 2'd1;
    localparam [1:0] CSR_CLEAR = 2'd2;

    localparam [31:0] CAUSE_INSTR_BUS  = 32'd1;
    localparam [31:0] CAUSE_DATA_BUS   = 32'd2;
    localparam [31:0] CAUSE_ILLEGAL    = 32'd3;
    localparam [31:0] CAUSE_MISALIGNED = 32'd4;
    localparam [31:0] MCAUSE_EXT_IRQ   = 32'h8000_000B;

    reg [31:0] pc;
    reg [31:0] fetch_pc;
    reg        fetch_pending;
    reg        data_pending;

    // PC execute block in the report diagram.
    localparam [1:0] PCSEL_PC4   = 2'd0;
    localparam [1:0] PCSEL_ALU   = 2'd1;
    localparam [1:0] PCSEL_MTVEC = 2'd2;
    localparam [1:0] PCSEL_MEPC  = 2'd3;
    reg [1:0] pcsel;
    reg [31:0] pc_execute_next;

    // Stage 1: fetched instruction/decode side.
    reg        if_id_valid;
    reg [31:0] if_id_pc;
    reg [31:0] if_id_instr;

    // Stage 2: ID/EX register shown in the datapath diagram.
    reg        id_ex_valid;
    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_instr;
    reg [4:0]  id_ex_rs1;
    reg [4:0]  id_ex_rs2;
    reg [4:0]  id_ex_rd;
    reg [31:0] id_ex_a;
    reg [31:0] id_ex_b;
    reg [31:0] id_ex_imm;
    reg [3:0]  id_ex_alu_op;
    reg        id_ex_op_a_pc;
    reg        id_ex_op_b_imm;
    reg        id_ex_reg_write;
    reg [2:0]  id_ex_wb_sel;
    reg        id_ex_mem_read;
    reg        id_ex_mem_write;
    reg [2:0]  id_ex_mem_funct3;
    reg        id_ex_branch;
    reg        id_ex_jal;
    reg        id_ex_jalr;
    reg        id_ex_csr;
    reg [1:0]  id_ex_csr_op;
    reg        id_ex_csr_imm;
    reg [11:0] id_ex_csr_addr;
    reg        id_ex_mret;

    wire       branch_taken;
    wire [31:0] alu_result;
    reg        id_ex_illegal_shadow;

    // CSR file.
    reg [31:0] csr_mstatus;
    reg [31:0] csr_mie;
    reg [31:0] csr_mtvec;
    reg [31:0] csr_mepc;
    reg [31:0] csr_mcause;

    // Trap logic block in the report diagram. External interrupts are sampled
    // at instruction boundaries; synchronous exceptions have priority when they
    // are detected in the active stage.
    reg        trap_pending;
    reg [31:0] trap_cause;
    reg [31:0] trap_pc;
    wire       trap_taken = trap_pending;

    rv32i_2stage_csr_probe u_csr (
        .mstatus_i(csr_mstatus),
        .mie_i(csr_mie),
        .mtvec_i(csr_mtvec),
        .mepc_i(csr_mepc),
        .mcause_i(csr_mcause)
    );

    wire irq_enabled = csr_mstatus[3] && csr_mie[11];

    assign pc_debug_o = pc;

    wire wb_done = wb_ack_i || wb_err_i;
    wire bus_active = wb_cyc_o && wb_stb_o;
    reg  bus_is_data;
    // Pipeline boundary:
    // - fetch_done: the IF/ID stage has just received the next instruction.
    // - id_ex_valid in the same cycle means the previous instruction is in
    //   EX/MEM/WB, so this is the steady-state two-stage overlap.
    wire fetch_done = fetch_pending && wb_done && !bus_is_data;
    wire mem_done   = data_pending && wb_done && bus_is_data;

    // Decode outputs for the controller and immediate generation block.
    reg [4:0]  dec_rs1;
    reg [4:0]  dec_rs2;
    reg [4:0]  dec_rd;
    reg [2:0]  dec_funct3;
    reg [31:0] dec_imm;
    reg [3:0]  dec_alu_op;
    reg        dec_op_a_pc;
    reg        dec_op_b_imm;
    reg        dec_reg_write;
    reg [2:0]  dec_wb_sel;
    reg        dec_mem_read;
    reg        dec_mem_write;
    reg        dec_branch;
    reg        dec_jal;
    reg        dec_jalr;
    reg        dec_csr;
    reg [1:0]  dec_csr_op;
    reg        dec_csr_imm;
    reg [11:0] dec_csr_addr;
    reg        dec_mret;
    reg        dec_illegal;
    wire [31:0] decode_instr = (fetch_done && !wb_err_i) ? wb_dat_i : if_id_instr;

    wire [31:0] rf_rs1_data;
    wire [31:0] rf_rs2_data;
    reg         rf_write_enable;
    reg [4:0]  rf_write_addr;
    reg [31:0] rf_write_data;

    rv32i_2stage_regfile u_regfile (
        .clk_i(clk),
        .rs1_i(dec_rs1),
        .rs2_i(dec_rs2),
        .rs1_data_o(rf_rs1_data),
        .rs2_data_o(rf_rs2_data),
        .write_enable_i(rf_write_enable),
        .write_addr_i(rf_write_addr),
        .write_data_i(rf_write_data)
    );

    // Forwarding logic block in the report diagram. Because this is a compact
    // two-stage core, the relevant bypass source is the writeback result being
    // committed while the next instruction is decoded.
    wire       forward_hit1 = rf_write_enable && (rf_write_addr != 5'd0) &&
                              (rf_write_addr == dec_rs1);
    wire       forward_hit2 = rf_write_enable && (rf_write_addr != 5'd0) &&
                              (rf_write_addr == dec_rs2);
    wire       forward_sel1 = forward_hit1;
    wire       forward_sel2 = forward_hit2;
    wire [31:0] decode_data_a = forward_sel1 ? rf_write_data : rf_rs1_data;
    wire [31:0] decode_data_b = forward_sel2 ? rf_write_data : rf_rs2_data;

    function [31:0] imm_i;
        input [31:0] insn;
        begin
            imm_i = {{20{insn[31]}}, insn[31:20]};
        end
    endfunction

    function [31:0] imm_s;
        input [31:0] insn;
        begin
            imm_s = {{20{insn[31]}}, insn[31:25], insn[11:7]};
        end
    endfunction

    function [31:0] imm_b;
        input [31:0] insn;
        begin
            imm_b = {{19{insn[31]}}, insn[31], insn[7], insn[30:25],
                     insn[11:8], 1'b0};
        end
    endfunction

    function [31:0] imm_u;
        input [31:0] insn;
        begin
            imm_u = {insn[31:12], 12'd0};
        end
    endfunction

    function [31:0] imm_j;
        input [31:0] insn;
        begin
            imm_j = {{11{insn[31]}}, insn[31], insn[19:12], insn[20],
                     insn[30:21], 1'b0};
        end
    endfunction

    function csr_supported;
        input [11:0] addr;
        begin
            case (addr)
                12'h300, 12'h304, 12'h305, 12'h341, 12'h342, 12'h344:
                    csr_supported = 1'b1;
                default:
                    csr_supported = 1'b0;
            endcase
        end
    endfunction

    function [31:0] csr_read_value;
        input [11:0] addr;
        begin
            case (addr)
                12'h300: csr_read_value = csr_mstatus;
                12'h304: csr_read_value = csr_mie;
                12'h305: csr_read_value = csr_mtvec;
                12'h341: csr_read_value = csr_mepc;
                12'h342: csr_read_value = csr_mcause;
                12'h344: csr_read_value = {20'd0, irq_i, 11'd0};
                default: csr_read_value = 32'd0;
            endcase
        end
    endfunction

    function [31:0] csr_apply_op;
        input [1:0]  op;
        input [31:0] old_value;
        input [31:0] src;
        begin
            case (op)
                CSR_WRITE: csr_apply_op = src;
                CSR_SET:   csr_apply_op = old_value | src;
                CSR_CLEAR: csr_apply_op = old_value & ~src;
                default:   csr_apply_op = old_value;
            endcase
        end
    endfunction

    function [31:0] load_extend;
        input [31:0] word;
        input [1:0]  byte_offset;
        input [2:0]  funct3;
        reg [7:0]  selected_byte;
        reg [15:0] selected_half;
        begin
            case (byte_offset)
                2'd0: selected_byte = word[7:0];
                2'd1: selected_byte = word[15:8];
                2'd2: selected_byte = word[23:16];
                default: selected_byte = word[31:24];
            endcase
            selected_half = byte_offset[1] ? word[31:16] : word[15:0];
            case (funct3)
                3'b000: load_extend = {{24{selected_byte[7]}}, selected_byte};
                3'b001: load_extend = {{16{selected_half[15]}}, selected_half};
                3'b010: load_extend = word;
                3'b100: load_extend = {24'd0, selected_byte};
                3'b101: load_extend = {16'd0, selected_half};
                default: load_extend = word;
            endcase
        end
    endfunction

    function [3:0] store_sel;
        input [1:0] byte_offset;
        input [2:0] funct3;
        begin
            case (funct3)
                3'b000: store_sel = 4'b0001 << byte_offset;
                3'b001: store_sel = byte_offset[1] ? 4'b1100 : 4'b0011;
                default: store_sel = 4'b1111;
            endcase
        end
    endfunction

    function [31:0] store_data;
        input [31:0] data;
        input [1:0]  byte_offset;
        input [2:0]  funct3;
        begin
            case (funct3)
                3'b000: store_data = {4{data[7:0]}} << (8 * byte_offset);
                3'b001: store_data = byte_offset[1] ? {data[15:0], 16'd0}
                                                    : {16'd0, data[15:0]};
                default: store_data = data;
            endcase
        end
    endfunction

    wire [31:0] csr_old_value = csr_read_value(id_ex_csr_addr);
    wire [31:0] id_ex_csr_src = id_ex_csr_imm ? {27'd0, id_ex_rs1} : id_ex_a;
    wire [31:0] csr_next_value =
        csr_apply_op(id_ex_csr_op, csr_old_value, id_ex_csr_src);
    wire csr_write_requested =
        id_ex_csr && ((id_ex_csr_op == CSR_WRITE) || (id_ex_csr_src != 32'd0));

    wire [31:0] alu_a = id_ex_op_a_pc ? id_ex_pc : id_ex_a;
    wire [31:0] alu_b = id_ex_op_b_imm ? id_ex_imm : id_ex_b;
    reg [31:0] alu_out;

    always @(*) begin
        case (id_ex_alu_op)
            ALU_ADD:  alu_out = alu_a + alu_b;
            ALU_SUB:  alu_out = alu_a - alu_b;
            ALU_SLL:  alu_out = alu_a << alu_b[4:0];
            ALU_SLT:  alu_out = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;
            ALU_SLTU: alu_out = (alu_a < alu_b) ? 32'd1 : 32'd0;
            ALU_XOR:  alu_out = alu_a ^ alu_b;
            ALU_SRL:  alu_out = alu_a >> alu_b[4:0];
            ALU_SRA:  alu_out = $signed(alu_a) >>> alu_b[4:0];
            ALU_OR:   alu_out = alu_a | alu_b;
            ALU_AND:  alu_out = alu_a & alu_b;
            ALU_PASS: alu_out = alu_b;
            default:  alu_out = 32'd0;
        endcase
    end

    assign alu_result = alu_out;

    reg branch_condition;
    always @(*) begin
        case (id_ex_mem_funct3)
            3'b000: branch_condition = (id_ex_a == id_ex_b);
            3'b001: branch_condition = (id_ex_a != id_ex_b);
            3'b100: branch_condition = ($signed(id_ex_a) < $signed(id_ex_b));
            3'b101: branch_condition = ($signed(id_ex_a) >= $signed(id_ex_b));
            3'b110: branch_condition = (id_ex_a < id_ex_b);
            3'b111: branch_condition = (id_ex_a >= id_ex_b);
            default: branch_condition = 1'b0;
        endcase
    end
    assign branch_taken = id_ex_valid && id_ex_branch && branch_condition;

    wire [31:0] pc_plus4 = id_ex_pc + 32'd4;
    wire [31:0] branch_target = id_ex_pc + id_ex_imm;
    wire [31:0] jalr_target = (id_ex_a + id_ex_imm) & 32'hFFFF_FFFE;

    wire load_misaligned =
        id_ex_mem_read &&
        (((id_ex_mem_funct3 == 3'b001) || (id_ex_mem_funct3 == 3'b101)) && alu_out[0] ||
         (id_ex_mem_funct3 == 3'b010) && |alu_out[1:0]);
    wire store_misaligned =
        id_ex_mem_write &&
        ((id_ex_mem_funct3 == 3'b001) && alu_out[0] ||
         (id_ex_mem_funct3 == 3'b010) && |alu_out[1:0]);

    wire jump_taken = id_ex_valid && (id_ex_jal || id_ex_jalr || branch_taken);
    wire mret_taken = id_ex_valid && id_ex_mret;
    wire exec_active = fetch_done && id_ex_valid;
    wire exec_sync_exception =
        exec_active && (id_ex_illegal_shadow || load_misaligned || store_misaligned);
    wire exec_data_access =
        exec_active && !exec_sync_exception && (id_ex_mem_read || id_ex_mem_write);
    wire exec_control_redirect =
        exec_active && !exec_sync_exception && (jump_taken || mret_taken);
    wire exec_irq_pending =
        exec_active && !exec_sync_exception && !exec_data_access &&
        !exec_control_redirect && irq_i && irq_enabled;
    wire id_ex_flush = trap_taken || exec_control_redirect;
    wire pipeline_stall = (fetch_pending && !fetch_done) ||
                          (data_pending && !mem_done);
    wire pipeline_idle = !pipeline_stall && !fetch_pending &&
                         !data_pending && !bus_active;

    always @(*) begin
        trap_pending = 1'b0;
        trap_cause   = 32'd0;
        trap_pc      = pc;

        if (pipeline_idle && !halted_o && |pc[1:0]) begin
            trap_pending = 1'b1;
            trap_cause   = CAUSE_MISALIGNED;
            trap_pc      = pc;
        end else if (exec_active && id_ex_illegal_shadow) begin
            trap_pending = 1'b1;
            trap_cause   = CAUSE_ILLEGAL;
            trap_pc      = id_ex_pc;
        end else if (exec_active && (load_misaligned || store_misaligned)) begin
            trap_pending = 1'b1;
            trap_cause   = CAUSE_MISALIGNED;
            trap_pc      = id_ex_pc;
        end else if (fetch_done && wb_err_i && !exec_control_redirect) begin
            trap_pending = 1'b1;
            trap_cause   = CAUSE_INSTR_BUS;
            trap_pc      = fetch_pc;
        end else if (mem_done && wb_err_i) begin
            trap_pending = 1'b1;
            trap_cause   = CAUSE_DATA_BUS;
            trap_pc      = id_ex_pc;
        end else if (exec_irq_pending) begin
            trap_pending = 1'b1;
            trap_cause   = MCAUSE_EXT_IRQ;
            trap_pc      = fetch_pc & 32'hFFFF_FFFE;
        end else if (pipeline_idle && !halted_o && irq_i && irq_enabled) begin
            trap_pending = 1'b1;
            trap_cause   = MCAUSE_EXT_IRQ;
            trap_pc      = pc & 32'hFFFF_FFFE;
        end
    end

    always @(*) begin
        pcsel = PCSEL_PC4;
        pc_execute_next = pc_plus4;
        if (trap_taken) begin
            pcsel = PCSEL_MTVEC;
            pc_execute_next = {csr_mtvec[31:2], 2'b00};
        end else if (mret_taken) begin
            pcsel = PCSEL_MEPC;
            pc_execute_next = csr_mepc;
        end else if (id_ex_jalr) begin
            pcsel = PCSEL_ALU;
            pc_execute_next = jalr_target;
        end else if (id_ex_jal || branch_taken) begin
            pcsel = PCSEL_ALU;
            pc_execute_next = branch_target;
        end
    end

    // Register writeback mux in the diagram.
    always @(*) begin
        rf_write_enable = 1'b0;
        rf_write_addr   = 5'd0;
        rf_write_data   = 32'd0;

        if (fetch_done && id_ex_valid && id_ex_reg_write &&
            !id_ex_mem_read && !id_ex_mem_write && !id_ex_mret &&
            !id_ex_illegal_shadow && !load_misaligned && !store_misaligned) begin
            rf_write_enable = (id_ex_rd != 5'd0);
            rf_write_addr   = id_ex_rd;
            case (id_ex_wb_sel)
                WB_PC4: rf_write_data = pc_plus4;
                WB_IMM: rf_write_data = id_ex_imm;
                WB_CSR: rf_write_data = csr_old_value;
                default: rf_write_data = alu_out;
            endcase
        end else if (mem_done && id_ex_valid && id_ex_mem_read && !wb_err_i) begin
            rf_write_enable = (id_ex_rd != 5'd0);
            rf_write_addr   = id_ex_rd;
            rf_write_data   = load_extend(wb_dat_i, alu_out[1:0], id_ex_mem_funct3);
        end
    end

    // Combinational controller/decode and immediate generation.
    always @(*) begin
        dec_rs1       = decode_instr[19:15];
        dec_rs2       = decode_instr[24:20];
        dec_rd        = decode_instr[11:7];
        dec_funct3    = decode_instr[14:12];
        dec_csr_addr  = decode_instr[31:20];
        dec_imm       = 32'd0;
        dec_alu_op    = ALU_ADD;
        dec_op_a_pc   = 1'b0;
        dec_op_b_imm  = 1'b0;
        dec_reg_write = 1'b0;
        dec_wb_sel    = WB_ALU;
        dec_mem_read  = 1'b0;
        dec_mem_write = 1'b0;
        dec_branch    = 1'b0;
        dec_jal       = 1'b0;
        dec_jalr      = 1'b0;
        dec_csr       = 1'b0;
        dec_csr_op    = CSR_WRITE;
        dec_csr_imm   = 1'b0;
        dec_mret      = 1'b0;
        dec_illegal   = 1'b0;

        case (decode_instr[6:0])
            7'b0110111: begin
                dec_imm       = imm_u(decode_instr);
                dec_alu_op    = ALU_PASS;
                dec_op_b_imm  = 1'b1;
                dec_reg_write = 1'b1;
                dec_wb_sel    = WB_IMM;
            end
            7'b0010111: begin
                dec_imm       = imm_u(decode_instr);
                dec_alu_op    = ALU_ADD;
                dec_op_a_pc   = 1'b1;
                dec_op_b_imm  = 1'b1;
                dec_reg_write = 1'b1;
            end
            7'b1101111: begin
                dec_imm       = imm_j(decode_instr);
                dec_jal       = 1'b1;
                dec_reg_write = 1'b1;
                dec_wb_sel    = WB_PC4;
            end
            7'b1100111: begin
                dec_imm       = imm_i(decode_instr);
                dec_jalr      = (dec_funct3 == 3'b000);
                dec_reg_write = (dec_funct3 == 3'b000);
                dec_wb_sel    = WB_PC4;
                dec_illegal   = (dec_funct3 != 3'b000);
            end
            7'b1100011: begin
                dec_imm     = imm_b(decode_instr);
                dec_branch  = 1'b1;
                dec_illegal = (dec_funct3 == 3'b010) || (dec_funct3 == 3'b011);
            end
            7'b0000011: begin
                dec_imm       = imm_i(decode_instr);
                dec_op_b_imm  = 1'b1;
                dec_reg_write = 1'b1;
                dec_wb_sel    = WB_MEM;
                dec_mem_read  = 1'b1;
                dec_illegal   = (dec_funct3 == 3'b011) || (dec_funct3 == 3'b110) ||
                                (dec_funct3 == 3'b111);
            end
            7'b0100011: begin
                dec_imm       = imm_s(decode_instr);
                dec_op_b_imm  = 1'b1;
                dec_mem_write = 1'b1;
                dec_illegal   = (dec_funct3 != 3'b000) && (dec_funct3 != 3'b001) &&
                                (dec_funct3 != 3'b010);
            end
            7'b0010011: begin
                dec_imm       = imm_i(decode_instr);
                dec_op_b_imm  = 1'b1;
                dec_reg_write = 1'b1;
                case (dec_funct3)
                    3'b000: dec_alu_op = ALU_ADD;
                    3'b010: dec_alu_op = ALU_SLT;
                    3'b011: dec_alu_op = ALU_SLTU;
                    3'b100: dec_alu_op = ALU_XOR;
                    3'b110: dec_alu_op = ALU_OR;
                    3'b111: dec_alu_op = ALU_AND;
                    3'b001: begin
                        dec_alu_op  = ALU_SLL;
                        dec_illegal = (decode_instr[31:25] != 7'b0000000);
                    end
                    3'b101: begin
                        dec_alu_op  = decode_instr[30] ? ALU_SRA : ALU_SRL;
                        dec_illegal = (decode_instr[31:25] != 7'b0000000) &&
                                      (decode_instr[31:25] != 7'b0100000);
                    end
                    default: dec_illegal = 1'b1;
                endcase
            end
            7'b0110011: begin
                dec_reg_write = 1'b1;
                case ({decode_instr[31:25], dec_funct3})
                    {7'b0000000, 3'b000}: dec_alu_op = ALU_ADD;
                    {7'b0100000, 3'b000}: dec_alu_op = ALU_SUB;
                    {7'b0000000, 3'b001}: dec_alu_op = ALU_SLL;
                    {7'b0000000, 3'b010}: dec_alu_op = ALU_SLT;
                    {7'b0000000, 3'b011}: dec_alu_op = ALU_SLTU;
                    {7'b0000000, 3'b100}: dec_alu_op = ALU_XOR;
                    {7'b0000000, 3'b101}: dec_alu_op = ALU_SRL;
                    {7'b0100000, 3'b101}: dec_alu_op = ALU_SRA;
                    {7'b0000000, 3'b110}: dec_alu_op = ALU_OR;
                    {7'b0000000, 3'b111}: dec_alu_op = ALU_AND;
                    default: dec_illegal = 1'b1;
                endcase
            end
            7'b0001111: begin
                dec_illegal = 1'b0;
            end
            7'b1110011: begin
                if (decode_instr == 32'h3020_0073) begin
                    dec_mret = 1'b1;
                end else if ((dec_funct3 != 3'b000) && csr_supported(dec_csr_addr)) begin
                    dec_csr       = 1'b1;
                    dec_csr_imm   = dec_funct3[2];
                    dec_reg_write = 1'b1;
                    dec_wb_sel    = WB_CSR;
                    case (dec_funct3[1:0])
                        2'b01: dec_csr_op = CSR_WRITE;
                        2'b10: dec_csr_op = CSR_SET;
                        2'b11: dec_csr_op = CSR_CLEAR;
                        default: dec_illegal = 1'b1;
                    endcase
                end else begin
                    dec_illegal = 1'b1;
                end
            end
            default: dec_illegal = 1'b1;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            pc                   <= RESET_VECTOR;
            fetch_pc             <= RESET_VECTOR;
            fetch_pending        <= 1'b0;
            data_pending         <= 1'b0;
            if_id_valid          <= 1'b0;
            if_id_pc             <= 32'd0;
            if_id_instr          <= 32'd0;
            id_ex_valid          <= 1'b0;
            id_ex_pc             <= 32'd0;
            id_ex_instr          <= 32'd0;
            id_ex_rs1            <= 5'd0;
            id_ex_rs2            <= 5'd0;
            id_ex_rd             <= 5'd0;
            id_ex_a              <= 32'd0;
            id_ex_b              <= 32'd0;
            id_ex_imm            <= 32'd0;
            id_ex_alu_op         <= ALU_ADD;
            id_ex_op_a_pc        <= 1'b0;
            id_ex_op_b_imm       <= 1'b0;
            id_ex_reg_write      <= 1'b0;
            id_ex_wb_sel         <= WB_ALU;
            id_ex_mem_read       <= 1'b0;
            id_ex_mem_write      <= 1'b0;
            id_ex_mem_funct3     <= 3'd0;
            id_ex_branch         <= 1'b0;
            id_ex_jal            <= 1'b0;
            id_ex_jalr           <= 1'b0;
            id_ex_csr            <= 1'b0;
            id_ex_csr_op         <= CSR_WRITE;
            id_ex_csr_imm        <= 1'b0;
            id_ex_csr_addr       <= 12'd0;
            id_ex_mret           <= 1'b0;
            id_ex_illegal_shadow <= 1'b0;
            csr_mstatus          <= 32'd0;
            csr_mie              <= 32'd0;
            csr_mtvec            <= IRQ_VECTOR;
            csr_mepc             <= 32'd0;
            csr_mcause           <= 32'd0;
            wb_adr_o             <= 32'd0;
            wb_dat_o             <= 32'd0;
            wb_sel_o             <= 4'd0;
            wb_we_o              <= 1'b0;
            wb_cyc_o             <= 1'b0;
            wb_stb_o             <= 1'b0;
            bus_is_data          <= 1'b0;
            trap_o               <= 1'b0;
            halted_o             <= 1'b0;
            fault_pc_o           <= 32'd0;
            fault_cause_o        <= 32'd0;
        end else begin
            trap_o <= 1'b0;

            if (wb_done) begin
                wb_cyc_o      <= 1'b0;
                wb_stb_o      <= 1'b0;
                wb_we_o       <= 1'b0;
                fetch_pending <= 1'b0;
                data_pending  <= 1'b0;
            end

            if (!halted_o) begin
                if (fetch_done) begin
                    if (id_ex_flush) begin
                        if (trap_taken) begin
                            csr_mepc       <= trap_pc & 32'hFFFF_FFFE;
                            csr_mcause     <= trap_cause;
                            csr_mstatus[7] <= csr_mstatus[3];
                            csr_mstatus[3] <= 1'b0;
                            trap_o         <= (trap_cause != MCAUSE_EXT_IRQ);
                            fault_pc_o     <= trap_pc;
                            fault_cause_o  <= trap_cause;
                        end else if (id_ex_mret) begin
                            csr_mstatus[3] <= csr_mstatus[7];
                            csr_mstatus[7] <= 1'b1;
                        end else if (id_ex_csr && csr_write_requested) begin
                            case (id_ex_csr_addr)
                                12'h300: csr_mstatus <= csr_next_value;
                                12'h304: csr_mie     <= csr_next_value;
                                12'h305: csr_mtvec   <= {csr_next_value[31:2], 2'b00};
                                12'h341: csr_mepc    <= csr_next_value & 32'hFFFF_FFFE;
                                12'h342: csr_mcause  <= csr_next_value;
                                default: ;
                            endcase
                        end

                        pc             <= pc_execute_next;
                        fetch_pc       <= pc_execute_next;
                        if_id_valid    <= 1'b0;
                        id_ex_valid    <= 1'b0;
                        fetch_pending  <= 1'b0;
                        data_pending   <= 1'b0;
                    end else if (exec_data_access) begin
                        if_id_valid <= !wb_err_i;
                        if_id_pc    <= fetch_pc;
                        if_id_instr <= wb_dat_i;

                        wb_adr_o      <= alu_out;
                        wb_dat_o      <= store_data(id_ex_b, alu_out[1:0], id_ex_mem_funct3);
                        wb_sel_o      <= id_ex_mem_write ?
                                         store_sel(alu_out[1:0], id_ex_mem_funct3) : 4'hF;
                        wb_we_o       <= id_ex_mem_write;
                        wb_cyc_o      <= 1'b1;
                        wb_stb_o      <= 1'b1;
                        bus_is_data   <= 1'b1;
                        fetch_pending <= 1'b0;
                        data_pending  <= 1'b1;
                    end else begin
                        if (exec_active && id_ex_csr && csr_write_requested) begin
                            case (id_ex_csr_addr)
                                12'h300: csr_mstatus <= csr_next_value;
                                12'h304: csr_mie     <= csr_next_value;
                                12'h305: csr_mtvec   <= {csr_next_value[31:2], 2'b00};
                                12'h341: csr_mepc    <= csr_next_value & 32'hFFFF_FFFE;
                                12'h342: csr_mcause  <= csr_next_value;
                                default: ;
                            endcase
                        end

                        if_id_valid <= 1'b0;
                        if_id_pc    <= fetch_pc;
                        if_id_instr <= wb_dat_i;

                        id_ex_valid          <= 1'b1;
                        id_ex_pc             <= fetch_pc;
                        id_ex_instr          <= wb_dat_i;
                        id_ex_rs1            <= dec_rs1;
                        id_ex_rs2            <= dec_rs2;
                        id_ex_rd             <= dec_rd;
                        id_ex_a              <= decode_data_a;
                        id_ex_b              <= decode_data_b;
                        id_ex_imm            <= dec_imm;
                        id_ex_alu_op         <= dec_alu_op;
                        id_ex_op_a_pc        <= dec_op_a_pc;
                        id_ex_op_b_imm       <= dec_op_b_imm;
                        id_ex_reg_write      <= dec_reg_write;
                        id_ex_wb_sel         <= dec_wb_sel;
                        id_ex_mem_read       <= dec_mem_read;
                        id_ex_mem_write      <= dec_mem_write;
                        id_ex_mem_funct3     <= dec_funct3;
                        id_ex_branch         <= dec_branch;
                        id_ex_jal            <= dec_jal;
                        id_ex_jalr           <= dec_jalr;
                        id_ex_csr            <= dec_csr;
                        id_ex_csr_op         <= dec_csr_op;
                        id_ex_csr_imm        <= dec_csr_imm;
                        id_ex_csr_addr       <= dec_csr_addr;
                        id_ex_mret           <= dec_mret;
                        id_ex_illegal_shadow <= dec_illegal;

                        fetch_pc      <= pc;
                        wb_adr_o      <= pc;
                        wb_dat_o      <= 32'd0;
                        wb_sel_o      <= 4'hF;
                        wb_we_o       <= 1'b0;
                        wb_cyc_o      <= 1'b1;
                        wb_stb_o      <= 1'b1;
                        bus_is_data   <= 1'b0;
                        pc            <= pc + 32'd4;
                        fetch_pending <= 1'b1;
                        data_pending  <= 1'b0;
                    end
                end else if (mem_done) begin
                    if (id_ex_flush) begin
                        csr_mepc       <= trap_pc & 32'hFFFF_FFFE;
                        csr_mcause     <= trap_cause;
                        csr_mstatus[7] <= csr_mstatus[3];
                        csr_mstatus[3] <= 1'b0;
                        pc             <= pc_execute_next;
                        fetch_pc       <= pc_execute_next;
                        if_id_valid    <= 1'b0;
                        id_ex_valid    <= 1'b0;
                        trap_o         <= 1'b1;
                        fault_pc_o     <= trap_pc;
                        fault_cause_o  <= trap_cause;
                        fetch_pending  <= 1'b0;
                        data_pending   <= 1'b0;
                    end else if (if_id_valid) begin
                        id_ex_valid          <= 1'b1;
                        id_ex_pc             <= if_id_pc;
                        id_ex_instr          <= if_id_instr;
                        id_ex_rs1            <= dec_rs1;
                        id_ex_rs2            <= dec_rs2;
                        id_ex_rd             <= dec_rd;
                        id_ex_a              <= decode_data_a;
                        id_ex_b              <= decode_data_b;
                        id_ex_imm            <= dec_imm;
                        id_ex_alu_op         <= dec_alu_op;
                        id_ex_op_a_pc        <= dec_op_a_pc;
                        id_ex_op_b_imm       <= dec_op_b_imm;
                        id_ex_reg_write      <= dec_reg_write;
                        id_ex_wb_sel         <= dec_wb_sel;
                        id_ex_mem_read       <= dec_mem_read;
                        id_ex_mem_write      <= dec_mem_write;
                        id_ex_mem_funct3     <= dec_funct3;
                        id_ex_branch         <= dec_branch;
                        id_ex_jal            <= dec_jal;
                        id_ex_jalr           <= dec_jalr;
                        id_ex_csr            <= dec_csr;
                        id_ex_csr_op         <= dec_csr_op;
                        id_ex_csr_imm        <= dec_csr_imm;
                        id_ex_csr_addr       <= dec_csr_addr;
                        id_ex_mret           <= dec_mret;
                        id_ex_illegal_shadow <= dec_illegal;
                        if_id_valid          <= 1'b0;

                        fetch_pc      <= pc;
                        wb_adr_o      <= pc;
                        wb_dat_o      <= 32'd0;
                        wb_sel_o      <= 4'hF;
                        wb_we_o       <= 1'b0;
                        wb_cyc_o      <= 1'b1;
                        wb_stb_o      <= 1'b1;
                        bus_is_data   <= 1'b0;
                        pc            <= pc + 32'd4;
                        fetch_pending <= 1'b1;
                        data_pending  <= 1'b0;
                    end else begin
                        id_ex_valid  <= 1'b0;
                        data_pending <= 1'b0;
                    end
                end else if (pipeline_idle) begin
                    id_ex_valid <= 1'b0;
                    if_id_valid <= 1'b0;

                    if (trap_taken) begin
                        csr_mepc       <= trap_pc & 32'hFFFF_FFFE;
                        csr_mcause     <= trap_cause;
                        csr_mstatus[7] <= csr_mstatus[3];
                        csr_mstatus[3] <= 1'b0;
                        pc             <= pc_execute_next;
                        fetch_pc       <= pc_execute_next;
                        trap_o         <= (trap_cause != MCAUSE_EXT_IRQ);
                        fault_pc_o     <= trap_pc;
                        fault_cause_o  <= trap_cause;
                    end else begin
                        fetch_pc      <= pc;
                        wb_adr_o      <= pc;
                        wb_dat_o      <= 32'd0;
                        wb_sel_o      <= 4'hF;
                        wb_we_o       <= 1'b0;
                        wb_cyc_o      <= 1'b1;
                        wb_stb_o      <= 1'b1;
                        bus_is_data   <= 1'b0;
                        pc            <= pc + 32'd4;
                        fetch_pending <= 1'b1;
                        data_pending  <= 1'b0;
                    end
                end
            end
        end
    end
endmodule

module rv32i_2stage_csr_probe(
    input wire [31:0] mstatus_i,
    input wire [31:0] mie_i,
    input wire [31:0] mtvec_i,
    input wire [31:0] mepc_i,
    input wire [31:0] mcause_i
);
    reg [31:0] mstatus;
    reg [31:0] mie;
    reg [31:0] mtvec;
    reg [31:0] mepc;
    reg [31:0] mcause;

    always @(*) begin
        mstatus = mstatus_i;
        mie     = mie_i;
        mtvec   = mtvec_i;
        mepc    = mepc_i;
        mcause  = mcause_i;
    end
endmodule

module rv32i_2stage_regfile(
    input  wire        clk_i,
    input  wire [4:0]  rs1_i,
    input  wire [4:0]  rs2_i,
    output wire [31:0] rs1_data_o,
    output wire [31:0] rs2_data_o,
    input  wire        write_enable_i,
    input  wire [4:0]  write_addr_i,
    input  wire [31:0] write_data_i
);
    reg [31:0] xreg [0:31];
    integer i;

    initial begin
        for (i = 0; i < 32; i = i + 1)
            xreg[i] = 32'd0;
    end

    assign rs1_data_o = (rs1_i == 5'd0) ? 32'd0 : xreg[rs1_i];
    assign rs2_data_o = (rs2_i == 5'd0) ? 32'd0 : xreg[rs2_i];

    always @(posedge clk_i) begin
        if (write_enable_i && (write_addr_i != 5'd0))
            xreg[write_addr_i] <= write_data_i;
        xreg[0] <= 32'd0;
    end
endmodule
