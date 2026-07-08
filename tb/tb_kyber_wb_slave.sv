`timescale 1ns/1ps

module tb_kyber_wb_slave;
    localparam int MAX_TESTS  = 100;
    localparam int SEED_BYTES = 64;
    localparam int PK_BYTES   = 800;
    localparam int SK_BYTES   = 1632;
    localparam int CT_BYTES   = 768;
    localparam int SS_BYTES   = 32;

    localparam int SEED_VEC_BYTES   = MAX_TESTS * SEED_BYTES;
    localparam int PK_VEC_BYTES     = MAX_TESTS * PK_BYTES;
    localparam int SK_VEC_BYTES     = MAX_TESTS * SK_BYTES;
    localparam int CT_VEC_BYTES     = MAX_TESTS * CT_BYTES;
    localparam int SS_ENC_VEC_BYTES = MAX_TESTS * SS_BYTES;
    localparam int SS_DEC_VEC_BYTES = MAX_TESTS * SS_BYTES;

    localparam [31:0] PK_OFFSET          = 32'h0000_0000;
    localparam [31:0] SK_OFFSET          = 32'h0000_07D0;
    localparam [31:0] CT_OFFSET          = 32'h0000_1770;
    localparam [31:0] SS_OFFSET          = 32'h0000_1F40;
    localparam [31:0] SEED_OFFSET        = 32'h0000_3000;
    localparam [31:0] CTRL_OFFSET        = 32'h0000_4000;
    localparam [31:0] STATUS_OFFSET      = 32'h0000_4004;
    localparam [31:0] IRQ_ENABLE_OFFSET  = 32'h0000_4008;
    localparam [31:0] IRQ_STATUS_OFFSET  = 32'h0000_400C;

    localparam [1:0] OPCODE_KEYGEN = 2'b01;
    localparam [1:0] OPCODE_ENCAPS = 2'b10;
    localparam [1:0] OPCODE_DECAPS = 2'b11;

    localparam int REGION_PK     = 0;
    localparam int REGION_SK     = 1;
    localparam int REGION_CT     = 2;
    localparam int REGION_SS_ENC = 3;
    localparam int REGION_SS_DEC = 4;

    reg clk;
    reg rst;

    reg  [31:0] wb_adr_i;
    reg  [31:0] wb_dat_i;
    wire [31:0] wb_dat_o;
    reg  [3:0]  wb_sel_i;
    reg         wb_we_i;
    reg         wb_cyc_i;
    reg         wb_stb_i;
    wire        wb_ack_o;
    wire        wb_err_o;
    wire        irq_o;

    reg [7:0] seed_vec   [0:SEED_VEC_BYTES-1];
    reg [7:0] pk_vec     [0:PK_VEC_BYTES-1];
    reg [7:0] sk_vec     [0:SK_VEC_BYTES-1];
    reg [7:0] ct_vec     [0:CT_VEC_BYTES-1];
    reg [7:0] ss_enc_vec [0:SS_ENC_VEC_BYTES-1];
    reg [7:0] ss_dec_vec [0:SS_DEC_VEC_BYTES-1];

    integer num_tests;
    integer max_cycles;
    integer current_test;
    string vec_dir;

    kyber_wb_slave dut (
        .wb_clk_i(clk),
        .wb_rst_i(rst),
        .wb_adr_i(wb_adr_i),
        .wb_dat_i(wb_dat_i),
        .wb_dat_o(wb_dat_o),
        .wb_sel_i(wb_sel_i),
        .wb_we_i(wb_we_i),
        .wb_cyc_i(wb_cyc_i),
        .wb_stb_i(wb_stb_i),
        .wb_ack_o(wb_ack_o),
        .wb_err_o(wb_err_o),
        .irq_o(irq_o)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic require_file(input string path);
        integer fd;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin
                $fatal(1, "Cannot open vector file: %s", path);
            end
            $fclose(fd);
        end
    endtask

    task automatic load_vectors;
        string path;
        begin
            if (!$value$plusargs("VEC_DIR=%s", vec_dir)) begin
                vec_dir = "build/kyber_wb_slave_tb/vectors";
            end

            path = {vec_dir, "/seed.hex"};
            require_file(path);
            $readmemh(path, seed_vec);

            path = {vec_dir, "/pk.hex"};
            require_file(path);
            $readmemh(path, pk_vec);

            path = {vec_dir, "/sk.hex"};
            require_file(path);
            $readmemh(path, sk_vec);

            path = {vec_dir, "/ct.hex"};
            require_file(path);
            $readmemh(path, ct_vec);

            path = {vec_dir, "/ss_enc.hex"};
            require_file(path);
            $readmemh(path, ss_enc_vec);

            path = {vec_dir, "/ss_dec.hex"};
            require_file(path);
            $readmemh(path, ss_dec_vec);
        end
    endtask

    task automatic wb_idle;
        begin
            wb_adr_i <= 32'd0;
            wb_dat_i <= 32'd0;
            wb_sel_i <= 4'd0;
            wb_we_i  <= 1'b0;
            wb_cyc_i <= 1'b0;
            wb_stb_i <= 1'b0;
        end
    endtask

    task automatic wb_write(input [31:0] addr, input [31:0] data, input [3:0] sel);
        begin
            @(posedge clk);
            #1;
            wb_adr_i <= addr;
            wb_dat_i <= data;
            wb_sel_i <= sel;
            wb_we_i  <= 1'b1;
            wb_cyc_i <= 1'b1;
            wb_stb_i <= 1'b1;

            do begin
                @(posedge clk);
                #1;
            end while (!wb_ack_o);

            if (wb_err_o) begin
                $fatal(1, "Wishbone write error at addr=0x%08x data=0x%08x", addr, data);
            end

            wb_idle();
        end
    endtask

    task automatic wb_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            #1;
            wb_adr_i <= addr;
            wb_dat_i <= 32'd0;
            wb_sel_i <= 4'hF;
            wb_we_i  <= 1'b0;
            wb_cyc_i <= 1'b1;
            wb_stb_i <= 1'b1;

            do begin
                @(posedge clk);
                #1;
            end while (!wb_ack_o);

            if (wb_err_o) begin
                $fatal(1, "Wishbone read error at addr=0x%08x", addr);
            end

            data = wb_dat_o;
            wb_idle();
        end
    endtask

    task automatic soft_reset_core;
        begin
            wb_write(CTRL_OFFSET, 32'h0000_0100, 4'hF);
            repeat (4) @(posedge clk);
        end
    endtask

    task automatic load_seed(input int test_idx);
        int i;
        int base;
        reg [31:0] word;
        begin
            base = test_idx * SEED_BYTES;
            for (i = 0; i < SEED_BYTES; i = i + 4) begin
                word = {seed_vec[base+i+3], seed_vec[base+i+2],
                        seed_vec[base+i+1], seed_vec[base+i+0]};
                wb_write(SEED_OFFSET + i[31:0], word, 4'hF);
            end
        end
    endtask

    task automatic run_operation(input [1:0] opcode, input string name);
        int cycles;
        reg [31:0] status;
        begin
            wb_write(IRQ_STATUS_OFFSET, 32'h0000_0001, 4'hF);
            wb_write(CTRL_OFFSET, {29'd0, opcode, 1'b1}, 4'hF);

            cycles = 0;
            while (!irq_o && cycles < max_cycles) begin
                @(posedge clk);
                cycles = cycles + 1;
            end

            if (!irq_o) begin
                wb_read(STATUS_OFFSET, status);
                $fatal(1, "Timeout waiting for %s at test %0d, status=0x%08x", name, current_test, status);
            end

            wb_read(STATUS_OFFSET, status);
            if (!status[1]) begin
                $fatal(1, "%s IRQ asserted but done bit is low at test %0d, status=0x%08x",
                       name, current_test, status);
            end
            if (status[2]) begin
                $fatal(1, "%s completed with wrapper error at test %0d, status=0x%08x",
                       name, current_test, status);
            end

            wb_write(IRQ_STATUS_OFFSET, 32'h0000_0001, 4'hF);
            $display("test %0d %-6s done in %0d cycles, state=0x%02x",
                     current_test, name, cycles, status[15:8]);
        end
    endtask

    function automatic [7:0] expected_byte(input int region, input int test_idx, input int byte_idx);
        begin
            case (region)
                REGION_PK:
                    expected_byte = pk_vec[(test_idx * PK_BYTES) + byte_idx];
                REGION_SK:
                    expected_byte = sk_vec[(test_idx * SK_BYTES) + byte_idx];
                REGION_CT:
                    expected_byte = ct_vec[(test_idx * CT_BYTES) + byte_idx];
                REGION_SS_ENC:
                    expected_byte = ss_enc_vec[(test_idx * SS_BYTES) + byte_idx];
                REGION_SS_DEC:
                    expected_byte = ss_dec_vec[(test_idx * SS_BYTES) + byte_idx];
                default:
                    expected_byte = 8'h00;
            endcase
        end
    endfunction

    task automatic compare_region(
        input string name,
        input int region,
        input [31:0] hw_offset,
        input int byte_count
    );
        int i;
        int lane;
        int mismatches;
        reg [31:0] word;
        reg [7:0] got;
        reg [7:0] exp;
        begin
            mismatches = 0;
            for (i = 0; i < byte_count; i = i + 4) begin
                wb_read(hw_offset + i[31:0], word);
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    if ((i + lane) < byte_count) begin
                        got = word[lane*8 +: 8];
                        exp = expected_byte(region, current_test, i + lane);
                        if (got !== exp) begin
                            if (mismatches < 8) begin
                                $display("Mismatch %s test=%0d byte=%0d got=%02x exp=%02x",
                                         name, current_test, i + lane, got, exp);
                            end
                            mismatches = mismatches + 1;
                        end
                    end
                end
            end

            if (mismatches != 0) begin
                $fatal(1, "%s mismatch at test %0d: %0d byte(s) differ",
                       name, current_test, mismatches);
            end

            $display("test %0d %-6s compare PASS (%0d bytes)", current_test, name, byte_count);
        end
    endtask

    initial begin
        int requested_tests;
        int requested_max_cycles;

        num_tests = MAX_TESTS;
        max_cycles = 20000000;
        current_test = 0;

        if ($value$plusargs("NUM_TESTS=%d", requested_tests)) begin
            num_tests = requested_tests;
        end
        if ($value$plusargs("MAX_CYCLES=%d", requested_max_cycles)) begin
            max_cycles = requested_max_cycles;
        end

        if (num_tests <= 0 || num_tests > MAX_TESTS) begin
            $fatal(1, "NUM_TESTS must be in range 1..%0d, got %0d", MAX_TESTS, num_tests);
        end

        load_vectors();

        rst = 1'b1;
        wb_idle();
        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        wb_write(IRQ_ENABLE_OFFSET, 32'h0000_0001, 4'hF);

        for (current_test = 0; current_test < num_tests; current_test = current_test + 1) begin
            $display("---- Kyber WB randomized test %0d/%0d ----", current_test + 1, num_tests);

            soft_reset_core();
            load_seed(current_test);
            run_operation(OPCODE_KEYGEN, "keygen");
            compare_region("pk", REGION_PK, PK_OFFSET, PK_BYTES);
            compare_region("sk", REGION_SK, SK_OFFSET, SK_BYTES);

            soft_reset_core();
            load_seed(current_test);
            run_operation(OPCODE_ENCAPS, "encaps");
            compare_region("ct", REGION_CT, CT_OFFSET, CT_BYTES);
            compare_region("ss_enc", REGION_SS_ENC, SS_OFFSET, SS_BYTES);

            soft_reset_core();
            run_operation(OPCODE_DECAPS, "decaps");
            compare_region("ss_dec", REGION_SS_DEC, SS_OFFSET, SS_BYTES);
        end

        $display("PASS: kyber_wb_slave matched C reference for %0d randomized test(s)", num_tests);
        $finish;
    end
endmodule
