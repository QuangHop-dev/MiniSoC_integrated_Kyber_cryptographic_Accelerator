`timescale 1ns/1ps

module kyber_pwma_local (
    input  wire                    clk,
    input  wire                    rst,

    input  wire                    bank,
    input  wire                    operand_bank,
    input  wire                    accumulate,

    input  wire                    acc_load_we,
    input  wire                    acc_load_bank,
    input  wire [6:0]              acc_load_addr,
    input  wire [31:0]             acc_load_pair,

    input  wire                    operand_load_we,
    input  wire                    operand_load_bank,
    input  wire [6:0]              operand_load_addr,
    input  wire [31:0]             operand_load_pair,

    input  wire                    start,
    input  wire                    use_tomont,
    input  wire                    stream_valid,
    output wire                    stream_ready,
    input  wire signed [15:0]      stream_c0,
    input  wire signed [15:0]      stream_c1,

    output wire [6:0]              zeta_addr,
    input  wire signed [15:0]      zeta_in,

    input  wire                    result_rd_bank,
    input  wire [6:0]              result_rd_addr,
    output wire [31:0]             result_rd_pair,
    output wire                    result_valid,
    output wire [6:0]              result_index,
    output wire [31:0]             result_pair,

    output reg                     busy,
    output reg                     done
);
    localparam integer BM_PIPE_DELAY = 16;
    localparam integer TOMONT_PIPE_DELAY = 3;

    reg       active_bank;
    reg       active_operand_bank;
    reg       active_accumulate;
    reg [6:0] operand_read_addr_run;
    reg [6:0] zeta_addr_run;
    reg [7:0] issue_index;
    reg       rd_v0;
    reg       rd_v1;
    reg       rd_v2;
    reg [6:0] rd_idx0;
    reg [6:0] rd_idx1;
    reg [6:0] rd_idx2;
    reg signed [15:0] stream_c0_d0;
    reg signed [15:0] stream_c0_d1;
    reg signed [15:0] stream_c0_d2;
    reg signed [15:0] stream_c1_d0;
    reg signed [15:0] stream_c1_d1;
    reg signed [15:0] stream_c1_d2;
    reg signed [15:0] zeta_in_d1;

    wire [31:0] operand_read_pair;
    wire [31:0] acc_read_pair;
    reg  [31:0] operand_read_pair_d1;

    reg [BM_PIPE_DELAY-1:0] pipe_valid;
    reg [6:0] pipe_index [0:BM_PIPE_DELAY-1];
    reg       write_pending;
    reg [6:0] write_index;
    reg signed [15:0] base_c0_hold;
    reg signed [15:0] base_c1_hold;

    wire issue_fire = busy && (issue_index < 8'd128) && stream_valid;
    assign stream_ready = busy && (issue_index < 8'd128);
    assign zeta_addr = zeta_addr_run;

    wire [7:0] operand_read_addr =
        busy ? {active_operand_bank, operand_read_addr_run} :
               {operand_load_bank, operand_load_addr};
    wire [7:0] acc_read_addr =
        busy && pipe_valid[BM_PIPE_DELAY-1] ?
            {active_bank, pipe_index[BM_PIPE_DELAY-1]} :
            {result_rd_bank, result_rd_addr};

    wire signed [15:0] operand_c0 = operand_read_pair_d1[15:0];
    wire signed [15:0] operand_c1 = operand_read_pair_d1[31:16];
    wire signed [15:0] base_c0;
    wire signed [15:0] base_c1;

    kyber_basemul_pipe u_basemul (
        .clk(clk), .rst(rst),
        .a0(operand_c0), .a1(operand_c1),
        .b0(stream_c0_d2), .b1(stream_c1_d2),
        .zeta(rd_idx2[0] ? -zeta_in_d1 : zeta_in_d1),
        .c0(base_c0), .c1(base_c1)
    );

    function signed [31:0] mul_tomont_shiftadd_s16;
        input signed [15:0] x;
        reg signed [31:0] xs;
        begin
            xs = {{16{x[15]}}, x};
            mul_tomont_shiftadd_s16 = (xs <<< 10) + (xs <<< 8) +
                                      (xs <<< 6) + (xs <<< 3) + xs;
        end
    endfunction

    wire signed [15:0] base_c0_tomont;
    wire signed [15:0] base_c1_tomont;
    wire signed [15:0] base_c0_delay;
    wire signed [15:0] base_c1_delay;

    kyber_montgomery_pipe u_tomont_c0 (
        .clk(clk), .rst(rst),
        .din(mul_tomont_shiftadd_s16(base_c0)),
        .dout(base_c0_tomont)
    );

    kyber_montgomery_pipe u_tomont_c1 (
        .clk(clk), .rst(rst),
        .din(mul_tomont_shiftadd_s16(base_c1)),
        .dout(base_c1_tomont)
    );

    kyber_delay_line #(.WIDTH(16), .DEPTH(TOMONT_PIPE_DELAY))
    u_base_c0_delay (
        .clk(clk), .rst(rst), .din(base_c0), .dout(base_c0_delay)
    );

    kyber_delay_line #(.WIDTH(16), .DEPTH(TOMONT_PIPE_DELAY))
    u_base_c1_delay (
        .clk(clk), .rst(rst), .din(base_c1), .dout(base_c1_delay)
    );

    wire signed [15:0] selected_c0 =
        use_tomont ? base_c0_tomont : base_c0_delay;
    wire signed [15:0] selected_c1 =
        use_tomont ? base_c1_tomont : base_c1_delay;

    wire signed [16:0] acc_c0 =
        $signed({acc_read_pair[15], acc_read_pair[15:0]});
    wire signed [16:0] acc_c1 =
        $signed({acc_read_pair[31], acc_read_pair[31:16]});
    wire signed [16:0] sum_c0 =
        active_accumulate ?
            acc_c0 + $signed({base_c0_hold[15], base_c0_hold}) :
            $signed({base_c0_hold[15], base_c0_hold});
    wire signed [16:0] sum_c1 =
        active_accumulate ?
            acc_c1 + $signed({base_c1_hold[15], base_c1_hold}) :
            $signed({base_c1_hold[15], base_c1_hold});
    wire signed [16:0] nonnegative_c0 =
        (sum_c0 < 17'sd0) ? sum_c0 + 17'sd3329 : sum_c0;
    wire signed [16:0] nonnegative_c1 =
        (sum_c1 < 17'sd0) ? sum_c1 + 17'sd3329 : sum_c1;
    wire signed [16:0] reduced_c0 =
        (nonnegative_c0 >= 17'sd3329) ?
            nonnegative_c0 - 17'sd3329 : nonnegative_c0;
    wire signed [16:0] reduced_c1 =
        (nonnegative_c1 >= 17'sd3329) ?
            nonnegative_c1 - 17'sd3329 : nonnegative_c1;

    wire acc_write_we = acc_load_we || write_pending;
    wire [7:0] acc_write_addr =
        acc_load_we ? {acc_load_bank, acc_load_addr} :
                      {active_bank, write_index};
    wire [31:0] acc_write_pair =
        acc_load_we ? acc_load_pair :
                      {reduced_c1[15:0], reduced_c0[15:0]};

    kyber_pair_sdp_bram #(
        .WIDTH(32), .ADDR_W(8), .DEPTH(256)
    ) u_accumulator_ram (
        .clk(clk),
        .rd_addr(acc_read_addr),
        .rd_data(acc_read_pair),
        .wr_en(acc_write_we),
        .wr_addr(acc_write_addr),
        .wr_data(acc_write_pair)
    );

    kyber_pair_sdp_lutram #(
        .WIDTH(32), .ADDR_W(8), .DEPTH(256)
    ) u_operand_ram (
        .clk(clk),
        .rd_addr(operand_read_addr),
        .rd_data(operand_read_pair),
        .wr_en(operand_load_we),
        .wr_addr({operand_load_bank, operand_load_addr}),
        .wr_data(operand_load_pair)
    );

    assign result_rd_pair = acc_read_pair;
    assign result_valid = write_pending;
    assign result_index = write_index;
    assign result_pair = {reduced_c1[15:0], reduced_c0[15:0]};

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            active_bank <= 1'b0;
            active_operand_bank <= 1'b0;
            active_accumulate <= 1'b0;
            operand_read_addr_run <= 7'd0;
            zeta_addr_run <= 7'd64;
            issue_index <= 8'd0;
            rd_v0 <= 1'b0;
            rd_v1 <= 1'b0;
            rd_v2 <= 1'b0;
            rd_idx0 <= 7'd0;
            rd_idx1 <= 7'd0;
            rd_idx2 <= 7'd0;
            stream_c0_d0 <= 16'sd0;
            stream_c0_d1 <= 16'sd0;
            stream_c0_d2 <= 16'sd0;
            stream_c1_d0 <= 16'sd0;
            stream_c1_d1 <= 16'sd0;
            stream_c1_d2 <= 16'sd0;
            zeta_in_d1 <= 16'sd0;
            operand_read_pair_d1 <= 32'd0;
            pipe_valid <= {BM_PIPE_DELAY{1'b0}};
            write_pending <= 1'b0;
            write_index <= 7'd0;
            base_c0_hold <= 16'sd0;
            base_c1_hold <= 16'sd0;
            busy <= 1'b0;
            done <= 1'b0;
            for (i = 0; i < BM_PIPE_DELAY; i = i + 1)
                pipe_index[i] <= 7'd0;
        end else begin
            done <= 1'b0;

            pipe_valid[0] <= rd_v2;
            pipe_index[0] <= rd_idx2;
            for (i = BM_PIPE_DELAY-1; i > 0; i = i - 1) begin
                pipe_valid[i] <= pipe_valid[i-1];
                pipe_index[i] <= pipe_index[i-1];
            end

            write_pending <= pipe_valid[BM_PIPE_DELAY-1];
            if (pipe_valid[BM_PIPE_DELAY-1]) begin
                write_index <= pipe_index[BM_PIPE_DELAY-1];
                base_c0_hold <= selected_c0;
                base_c1_hold <= selected_c1;
            end

            rd_v2 <= rd_v1;
            rd_v1 <= rd_v0;
            rd_v0 <= 1'b0;
            rd_idx2 <= rd_idx1;
            rd_idx1 <= rd_idx0;
            rd_idx0 <= 7'd0;
            stream_c0_d2 <= stream_c0_d1;
            stream_c0_d1 <= stream_c0_d0;
            stream_c1_d2 <= stream_c1_d1;
            stream_c1_d1 <= stream_c1_d0;
            zeta_in_d1 <= zeta_in;
            operand_read_pair_d1 <= operand_read_pair;

            if (start && !busy) begin
                busy <= 1'b1;
                active_bank <= bank;
                active_operand_bank <= operand_bank;
                active_accumulate <= accumulate;
                issue_index <= 8'd0;
                rd_v0 <= 1'b0;
                rd_v1 <= 1'b0;
                rd_v2 <= 1'b0;
                pipe_valid <= {BM_PIPE_DELAY{1'b0}};
                write_pending <= 1'b0;
            end else if (busy) begin
                if (issue_fire) begin
                    operand_read_addr_run <= issue_index[6:0];
                    zeta_addr_run <= 7'd64 + issue_index[7:1];
                    rd_v0 <= 1'b1;
                    rd_idx0 <= issue_index[6:0];
                    stream_c0_d0 <= stream_c0;
                    stream_c1_d0 <= stream_c1;
                    issue_index <= issue_index + 8'd1;
                end

                if ((issue_index == 8'd128) &&
                    !rd_v0 && !rd_v1 && !rd_v2 &&
                    (pipe_valid == {BM_PIPE_DELAY{1'b0}}) &&
                    !write_pending) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end
endmodule
