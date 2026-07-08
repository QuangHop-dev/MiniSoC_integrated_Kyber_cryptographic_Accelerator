`timescale 1ns/1ps

module tb_soc_top_kyber_cpu;
    localparam real CLK_PERIOD_NS = 6.0;

    localparam int PK_BYTES = 800;
    localparam int SK_BYTES = 1632;
    localparam int CT_BYTES = 768;
    localparam int SS_BYTES = 32;

    localparam int PK_OFFSET = 0;
    localparam int SK_OFFSET = 2000;
    localparam int CT_OFFSET = 6000;
    localparam int SS_OFFSET = 8000;

    reg clk;
    reg rst;
    reg [7:0] gpio1_i;

    wire [7:0] gpio0_o;
    wire [7:0] gpio0_oe;
    wire [7:0] gpio1_o;
    wire [7:0] gpio1_oe;
    wire       i2c_scl_o;
    wire       i2c_scl_oe;
    wire       i2c_sda_o;
    wire       i2c_sda_oe;
    wire       uart_tx_o;
    wire       irq_o;
    wire [31:0] irq_vector_o;
    wire       cpu_trap_o;
    wire       cpu_halted_o;
    wire [31:0] cpu_fault_pc_o;
    wire [31:0] cpu_fault_cause_o;
    wire [31:0] cpu_pc_o;

    reg [7:0] pk_vec             [0:PK_BYTES-1];
    reg [7:0] sk_vec             [0:SK_BYTES-1];
    reg [7:0] ct_vec             [0:CT_BYTES-1];
    reg [7:0] ct_invalid_vec     [0:CT_BYTES-1];
    reg [7:0] ss_enc_vec         [0:SS_BYTES-1];
    reg [7:0] ss_dec_valid_vec   [0:SS_BYTES-1];
    reg [7:0] ss_dec_invalid_vec [0:SS_BYTES-1];

    soc_top #(
        .CLK_FREQ_HZ(166_666_667),
        .BOOT_INIT_FILE("vectors/soc_kyber_cpu_boot.hex")
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .gpio0_i(8'd0),
        .gpio0_o(gpio0_o),
        .gpio0_oe(gpio0_oe),
        .gpio1_i(gpio1_i),
        .gpio1_o(gpio1_o),
        .gpio1_oe(gpio1_oe),
        .i2c_scl_i(1'b1),
        .i2c_scl_o(i2c_scl_o),
        .i2c_scl_oe(i2c_scl_oe),
        .i2c_sda_i(1'b1),
        .i2c_sda_o(i2c_sda_o),
        .i2c_sda_oe(i2c_sda_oe),
        .uart_rx_i(1'b1),
        .uart_tx_o(uart_tx_o),
        .ext_irq_i(2'b00),
        .irq_o(irq_o),
        .irq_vector_o(irq_vector_o),
        .cpu_trap_o(cpu_trap_o),
        .cpu_halted_o(cpu_halted_o),
        .cpu_fault_pc_o(cpu_fault_pc_o),
        .cpu_fault_cause_o(cpu_fault_cause_o),
        .cpu_pc_o(cpu_pc_o)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2.0) clk = ~clk;
    end

    task automatic load_vectors;
        begin
            $readmemh("vectors/pk.hex", pk_vec);
            $readmemh("vectors/sk.hex", sk_vec);
            $readmemh("vectors/ct.hex", ct_vec);
            $readmemh("vectors/ct_invalid.hex", ct_invalid_vec);
            $readmemh("vectors/ss_enc.hex", ss_enc_vec);
            $readmemh("vectors/ss_dec_valid.hex", ss_dec_valid_vec);
            $readmemh("vectors/ss_dec_invalid.hex", ss_dec_invalid_vec);
        end
    endtask

    function automatic [7:0] expected_byte(input int region, input int index);
        begin
            case (region)
                0: expected_byte = pk_vec[index];
                1: expected_byte = sk_vec[index];
                2: expected_byte = ct_vec[index];
                3: expected_byte = ct_invalid_vec[index];
                4: expected_byte = ss_enc_vec[index];
                5: expected_byte = ss_dec_valid_vec[index];
                6: expected_byte = ss_dec_invalid_vec[index];
                default: expected_byte = 8'h00;
            endcase
        end
    endfunction

    function automatic [7:0] peek_kyber_data_byte(input int addr);
        begin
            case (addr & 7)
                0: peek_kyber_data_byte = dut.u_kyber.u_data_mem.gen_bank[0].mem[addr >> 3];
                1: peek_kyber_data_byte = dut.u_kyber.u_data_mem.gen_bank[1].mem[addr >> 3];
                2: peek_kyber_data_byte = dut.u_kyber.u_data_mem.gen_bank[2].mem[addr >> 3];
                3: peek_kyber_data_byte = dut.u_kyber.u_data_mem.gen_bank[3].mem[addr >> 3];
                4: peek_kyber_data_byte = dut.u_kyber.u_data_mem.gen_bank[4].mem[addr >> 3];
                5: peek_kyber_data_byte = dut.u_kyber.u_data_mem.gen_bank[5].mem[addr >> 3];
                6: peek_kyber_data_byte = dut.u_kyber.u_data_mem.gen_bank[6].mem[addr >> 3];
                default: peek_kyber_data_byte = dut.u_kyber.u_data_mem.gen_bank[7].mem[addr >> 3];
            endcase
        end
    endfunction

    task automatic compare_region(
        input string name,
        input int region,
        input int hw_offset,
        input int byte_count
    );
        int i;
        int mismatches;
        reg [7:0] got;
        reg [7:0] exp;
        begin
            mismatches = 0;
            for (i = 0; i < byte_count; i = i + 1) begin
                got = peek_kyber_data_byte(hw_offset + i);
                exp = expected_byte(region, i);
                if (got !== exp) begin
                    if (mismatches < 8) begin
                        $display("Mismatch %s byte=%0d got=%02x exp=%02x",
                                 name, i, got, exp);
                    end
                    mismatches = mismatches + 1;
                end
            end

            if (mismatches != 0)
                $fatal(1, "%s mismatch: %0d byte(s) differ", name, mismatches);

            $display("SoC CPU Kyber %-14s compare PASS (%0d bytes)", name, byte_count);
        end
    endtask

    task automatic ack_marker;
        begin
            gpio1_i[0] = 1'b1;
            repeat (200) @(posedge clk);
            gpio1_i[0] = 1'b0;
            repeat (200) @(posedge clk);
        end
    endtask

    task automatic wait_marker(input [7:0] marker, input string name);
        int cycles;
        begin
            cycles = 0;
            while (gpio0_o !== marker && cycles < 10000000) begin
                @(posedge clk);
                cycles = cycles + 1;
                if (cpu_trap_o || cpu_halted_o) begin
                    $fatal(1, "CPU trapped before marker %s pc=0x%08x cause=0x%08x",
                           name, cpu_fault_pc_o, cpu_fault_cause_o);
                end
            end

            if (gpio0_o !== marker)
                $fatal(1, "Timeout waiting marker %s/0x%02x, pc=0x%08x gpio0=0x%02x",
                       name, marker, cpu_pc_o, gpio0_o);

            $display("SoC CPU reached marker %-14s gpio0=0x%02x pc=0x%08x",
                     name, gpio0_o, cpu_pc_o);
        end
    endtask

    initial begin
        gpio1_i = 8'd0;
        load_vectors();

        rst = 1'b1;
        repeat (10) @(posedge clk);
        rst = 1'b0;

        wait_marker(8'h11, "keygen");
        compare_region("pk", 0, PK_OFFSET, PK_BYTES);
        compare_region("sk", 1, SK_OFFSET, SK_BYTES);
        ack_marker();

        wait_marker(8'h22, "encaps");
        compare_region("ct", 2, CT_OFFSET, CT_BYTES);
        compare_region("ss_enc", 4, SS_OFFSET, SS_BYTES);
        ack_marker();

        wait_marker(8'h33, "decaps_valid");
        compare_region("ss_dec_valid", 5, SS_OFFSET, SS_BYTES);
        ack_marker();

        wait_marker(8'h44, "decaps_invalid");
        compare_region("ct_invalid", 3, CT_OFFSET, CT_BYTES);
        compare_region("ss_dec_invalid", 6, SS_OFFSET, SS_BYTES);

        if (gpio0_oe !== 8'hff)
            $fatal(1, "GPIO0 direction mismatch got=0x%02x", gpio0_oe);

        $display("PASS: soc_top CPU drove Kyber through Wishbone and matched C KAT reference");
        $finish;
    end
endmodule
