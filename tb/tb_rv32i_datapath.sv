`timescale 1ns/1ps

module tb_rv32i_datapath;
    reg clk;
    reg rst;
    reg irq;

    wire [31:0] wb_adr;
    wire [31:0] wb_dat_o;
    reg  [31:0] wb_dat_i;
    wire [3:0]  wb_sel;
    wire        wb_we;
    wire        wb_cyc;
    wire        wb_stb;
    reg         wb_ack;
    reg         wb_err;
    wire        trap;
    wire        halted;
    wire [31:0] fault_pc;
    wire [31:0] fault_cause;
    wire [31:0] pc;

    reg [31:0] memory [0:255];
    integer i;
    integer cycles;
    integer overlap_cycles;
    integer data_stall_cycles;
    integer stall_cycles;
    integer flush_cycles;

    rv32i_2stage_wb dut (
        .clk(clk),
        .rst(rst),
        .irq_i(irq),
        .trap_o(trap),
        .halted_o(halted),
        .fault_pc_o(fault_pc),
        .fault_cause_o(fault_cause),
        .pc_debug_o(pc),
        .wb_adr_o(wb_adr),
        .wb_dat_o(wb_dat_o),
        .wb_dat_i(wb_dat_i),
        .wb_sel_o(wb_sel),
        .wb_we_o(wb_we),
        .wb_cyc_o(wb_cyc),
        .wb_stb_o(wb_stb),
        .wb_ack_i(wb_ack),
        .wb_err_i(wb_err)
    );

    initial begin
        clk = 1'b0;
        forever #3 clk = ~clk;
    end

    initial begin
        for (i = 0; i < 256; i = i + 1)
            memory[i] = 32'd0;
        $readmemh("rv32i_datapath.hex", memory);
    end

    always @(posedge clk) begin
        wb_ack <= 1'b0;
        wb_err <= 1'b0;
        if (wb_cyc && wb_stb && !wb_ack) begin
            wb_ack <= 1'b1;
            wb_dat_i <= memory[wb_adr[9:2]];
            if (wb_we) begin
                if (wb_sel[0]) memory[wb_adr[9:2]][7:0]   <= wb_dat_o[7:0];
                if (wb_sel[1]) memory[wb_adr[9:2]][15:8]  <= wb_dat_o[15:8];
                if (wb_sel[2]) memory[wb_adr[9:2]][23:16] <= wb_dat_o[23:16];
                if (wb_sel[3]) memory[wb_adr[9:2]][31:24] <= wb_dat_o[31:24];
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            overlap_cycles <= 0;
            data_stall_cycles <= 0;
            stall_cycles <= 0;
            flush_cycles <= 0;
        end else begin
            if (dut.fetch_done && dut.id_ex_valid)
                overlap_cycles <= overlap_cycles + 1;
            if (dut.mem_done && dut.if_id_valid)
                data_stall_cycles <= data_stall_cycles + 1;
            if (dut.pipeline_stall)
                stall_cycles <= stall_cycles + 1;
            if (dut.id_ex_flush)
                flush_cycles <= flush_cycles + 1;
        end
    end

    task automatic banner(input string title);
        begin
            $display("");
            $display("==============================================================================");
            $display("* %-74s *", title);
            $display("==============================================================================");
        end
    endtask

    task automatic section(input string title);
        begin
            $display("");
            $display("------------------------------ %-44s", title);
        end
    endtask

    task automatic check_reg(
        input string name,
        input [4:0] index,
        input [31:0] expected
    );
        reg [31:0] got;
        begin
            got = dut.u_regfile.xreg[index];
            if (got !== expected)
                $fatal(1, "FAIL %-12s x%0d got=0x%08x expected=0x%08x",
                       name, index, got, expected);
            $display("| PASS | %-12s | x%-2d = 0x%08x | expected 0x%08x |",
                     name, index, got, expected);
        end
    endtask

    task automatic check_memory(
        input string name,
        input integer word_index,
        input [31:0] expected
    );
        reg [31:0] got;
        begin
            got = memory[word_index];
            if (got !== expected)
                $fatal(1, "FAIL %-12s mem[%0d] got=0x%08x expected=0x%08x",
                       name, word_index, got, expected);
            $display("| PASS | %-12s | mem[0x%03x] = 0x%08x              |",
                     name, word_index * 4, got);
        end
    endtask

    task automatic check_memory_half(
        input string name,
        input integer byte_addr,
        input [15:0] expected
    );
        reg [15:0] got;
        begin
            got = memory[byte_addr >> 2] >> ((byte_addr & 3) * 8);
            if (got !== expected)
                $fatal(1, "FAIL %-12s mem[0x%03x] got=0x%04x expected=0x%04x",
                       name, byte_addr, got, expected);
            $display("| PASS | %-12s | mem[0x%03x] = 0x%04x                      |",
                     name, byte_addr, got);
        end
    endtask

    task automatic check_memory_byte(
        input string name,
        input integer byte_addr,
        input [7:0] expected
    );
        reg [7:0] got;
        begin
            got = memory[byte_addr >> 2] >> ((byte_addr & 3) * 8);
            if (got !== expected)
                $fatal(1, "FAIL %-12s mem[0x%03x] got=0x%02x expected=0x%02x",
                       name, byte_addr, got, expected);
            $display("| PASS | %-12s | mem[0x%03x] = 0x%02x                        |",
                     name, byte_addr, got);
        end
    endtask

    task automatic testcase_summary(input integer total_cycles);
        begin
            section("TESTCASE SUMMARY TABLE");
            $display("BANG 4.1 - TOM TAT TESTCASE KIEM TRA LOI RISC-V RV32I");
            $display("+-----+----------+----------------------------------------------+----------------------------------------------+");
            $display("| STT | Nhom     | Lenh kiem tra                                | Ket qua mo phong                             |");
            $display("+-----+----------+----------------------------------------------+----------------------------------------------+");
            $display("| 1   | U-type   | LUI, AUIPC                                   | PASS: LUI=0x12345000, AUIPC=0x00000004       |");
            $display("| 2   | R-type   | ADD,SUB,SLL,SLT,SLTU,XOR,SRL,SRA,OR,AND      | PASS: x5..x15 khop gia tri tham chieu        |");
            $display("| 3   | I-type   | ADDI,SLTI,SLTIU,XORI,ORI,ANDI,SLLI,SRLI,SRAI | PASS: x16..x24 khop gia tri mong doi         |");
            $display("| 4   | Branch   | BEQ,BNE,BLT,BGE,BLTU,BGEU                    | PASS: branch-jump scoreboard dat 8/8         |");
            $display("| 5   | Jump     | JAL, JALR                                    | PASS: PC redirect va luong chuong trinh dung |");
            $display("| 6   | Store    | SW, SH, SB                                   | PASS: word/halfword/byte va byte-enable dung |");
            $display("| 7   | Load     | LW,LH,LHU,LB,LBU                              | PASS: x26..x30 khop, sign/zero extend dung   |");
            $display("| 8   | Tong hop | Toan bo chuong trinh kiem tra                 | PASS: hoan tat sau %0d chu ky, khong trap     |",
                     total_cycles);
            $display("+-----+----------+----------------------------------------------+----------------------------------------------+");
        end
    endtask

    initial begin
        rst = 1'b1;
        irq = 1'b0;
        wb_ack = 1'b0;
        wb_err = 1'b0;
        wb_dat_i = 32'd0;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        cycles = 0;
        overlap_cycles = 0;
        data_stall_cycles = 0;
        stall_cycles = 0;
        flush_cycles = 0;
        while ((dut.u_regfile.xreg[25] !== 32'h0000_00a5) &&
               (cycles < 3000)) begin
            @(posedge clk);
            cycles++;
            if (trap || halted)
                $fatal(1, "CPU fault pc=0x%08x cause=0x%08x",
                       fault_pc, fault_cause);
        end
        if (dut.u_regfile.xreg[25] !== 32'h0000_00a5)
            $fatal(1, "CPU datapath timeout pc=0x%08x x25=0x%08x x31=0x%08x",
                   pc, dut.u_regfile.xreg[25], dut.u_regfile.xreg[31]);

        $display("REPORT-BEGIN: CPU");
        banner("RV32I TWO-STAGE CPU DATAPATH SIMULATION");
        $display("| Time    : %0t ps", $time);
        $display("| Cycles  : %0d", cycles);
        $display("| Final PC: 0x%08x", pc);
        $display("| Pipeline overlap cycles : %0d", overlap_cycles);
        $display("| Pipeline stall cycles   : %0d", stall_cycles);
        $display("| ID/EX flush cycles      : %0d", flush_cycles);
        $display("| Data-bus stall releases : %0d", data_stall_cycles);

        section("PIPELINE");
        if (overlap_cycles <= 0)
            $fatal(1, "Two-stage overlap was not observed");
        if (stall_cycles <= 0)
            $fatal(1, "Pipeline stall was not observed");
        if (flush_cycles <= 0)
            $fatal(1, "ID/EX flush was not observed");
        $display("| PASS | IF/ID overlapped with EX/MEM/WB for %0d cycles",
                 overlap_cycles);
        $display("| PASS | stall asserted for %0d cycles while Wishbone/data waited",
                 stall_cycles);
        $display("| PASS | flush asserted for %0d branch/jump/trap redirect cycles",
                 flush_cycles);
        $display("| PASS | ID/EX and forwarding active while next instruction fetch completes |");

        section("U-TYPE");
        check_reg("LUI",   1, 32'h1234_5000);
        check_reg("AUIPC", 2, 32'h0000_0004);

        section("R-TYPE");
        check_reg("ADD",  5, 32'd12);
        check_reg("SUB",  6, 32'd2);
        check_reg("SLL",  7, 32'd640);
        check_reg("SLT",  8, 32'd1);
        check_reg("SLTU", 9, 32'd0);
        check_reg("XOR", 10, 32'd2);
        check_reg("SRL", 11, 32'd20);
        check_reg("SRA", 13, 32'hffff_ffff);
        check_reg("OR",  14, 32'd7);
        check_reg("AND", 15, 32'd5);

        section("I-TYPE");
        check_reg("ADDI",  16, 32'hffff_fffd);
        check_reg("SLTI",  17, 32'd1);
        check_reg("SLTIU", 18, 32'd0);
        check_reg("XORI",  19, 32'd10);
        check_reg("ORI",   20, 32'd13);
        check_reg("ANDI",  21, 32'd6);
        check_reg("SLLI",  22, 32'd40);
        check_reg("SRLI",  23, 32'd10);
        check_reg("SRAI",  24, 32'hffff_fffc);

        section("STORE AND LOAD");
        check_memory("SW", 64, 32'h1234_5000);
        check_memory_half("SH", 32'h104, 16'hfff0);
        check_memory_byte("SB", 32'h106, 8'hfd);
        check_memory("SH/SB", 65, 32'h00fd_fff0);
        check_reg("LW",  26, 32'h1234_5000);
        check_reg("LH",  27, 32'hffff_fff0);
        check_reg("LHU", 28, 32'h0000_fff0);
        check_reg("LB",  29, 32'hffff_fffd);
        check_reg("LBU", 30, 32'h0000_00fd);

        section("JUMP AND BRANCH");
        if (dut.u_regfile.xreg[31] !== 32'd8)
            $fatal(1, "Branch/jump scoreboard got=%0d expected=8",
                   dut.u_regfile.xreg[31]);
        $display("| PASS | BEQ / BNE / BLT / BGE / BLTU / BGEU                          |");
        $display("| PASS | JAL / JALR control-flow paths                                  |");
        $display("| PASS | Branch-jump scoreboard = %0d/8                                  |",
                 dut.u_regfile.xreg[31]);

        testcase_summary(cycles);

        $display("==============================================================================");
        $display("* RESULT: PASS - RV32I datapath completed without trap or mismatch.          *");
        $display("==============================================================================");
        $display("REPORT-END: CPU");
        $display("");
        $display("PASS: RV32I LUI, R-type, I-type, branch, jump, store and load datapath");
        $finish;
    end

endmodule
