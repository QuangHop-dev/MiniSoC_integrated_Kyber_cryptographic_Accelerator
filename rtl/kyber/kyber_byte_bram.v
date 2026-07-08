`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// kyber_byte_word64_tdp_forcebram
// 64-bit true-dual-port byte-enable RAM.
//
// In synthesis, this instantiates one word-oriented XPM memory instead of many
// tiny byte-lane XPMs. In normal RTL simulation, it falls back to a behavioral
// true-dual-port RAM, so Questa tests do not need XPM libraries.
// -----------------------------------------------------------------------------
module kyber_byte_word64_tdp_forcebram #(
    parameter ADDR_WIDTH = 8,
    parameter DEPTH      = 256
)(
    input  wire                  clka,
    input  wire [7:0]            wea,
    input  wire [ADDR_WIDTH-1:0] addra,
    input  wire [63:0]           dina,
    output wire [63:0]           douta,

    input  wire                  clkb,
    input  wire [7:0]            web,
    input  wire [ADDR_WIDTH-1:0] addrb,
    input  wire [63:0]           dinb,
    output wire [63:0]           doutb
);
`ifdef SYNTHESIS
    xpm_memory_tdpram #(
        .ADDR_WIDTH_A        (ADDR_WIDTH),
        .ADDR_WIDTH_B        (ADDR_WIDTH),
        .AUTO_SLEEP_TIME     (0),
        .BYTE_WRITE_WIDTH_A  (8),
        .BYTE_WRITE_WIDTH_B  (8),
        .CASCADE_HEIGHT      (0),
        .CLOCKING_MODE       ("independent_clock"),
        .ECC_MODE            ("no_ecc"),
        .MEMORY_INIT_FILE    ("none"),
        .MEMORY_INIT_PARAM   ("0"),
        .MEMORY_OPTIMIZATION ("true"),
        .MEMORY_PRIMITIVE    ("block"),
        .MEMORY_SIZE         (DEPTH * 64),
        .MESSAGE_CONTROL     (0),
        .READ_DATA_WIDTH_A   (64),
        .READ_DATA_WIDTH_B   (64),
        .READ_LATENCY_A      (1),
        .READ_LATENCY_B      (1),
        .READ_RESET_VALUE_A  ("0"),
        .READ_RESET_VALUE_B  ("0"),
        .RST_MODE_A          ("SYNC"),
        .RST_MODE_B          ("SYNC"),
        .SIM_ASSERT_CHK      (0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT        (0),
        .WAKEUP_TIME         ("disable_sleep"),
        .WRITE_DATA_WIDTH_A  (64),
        .WRITE_DATA_WIDTH_B  (64),
        .WRITE_MODE_A        ("read_first"),
        .WRITE_MODE_B        ("read_first")
    ) u_xpm_word64_tdp (
        .clka          (clka),
        .rsta          (1'b0),
        .ena           (1'b1),
        .regcea        (1'b1),
        .wea           (wea),
        .addra         (addra),
        .dina          (dina),
        .douta         (douta),

        .clkb          (clkb),
        .rstb          (1'b0),
        .enb           (1'b1),
        .regceb        (1'b1),
        .web           (web),
        .addrb         (addrb),
        .dinb          (dinb),
        .doutb         (doutb),

        .sleep         (1'b0),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .sbiterra      (),
        .dbiterra      (),
        .sbiterrb      (),
        .dbiterrb      ()
    );
`else
    (* ram_style = "block" *) reg [63:0] mem [0:DEPTH-1];
    reg [63:0] douta_r;
    reg [63:0] doutb_r;
    integer bi_a;
    integer bi_b;

    assign douta = douta_r;
    assign doutb = doutb_r;

    always @(posedge clka) begin
        for (bi_a = 0; bi_a < 8; bi_a = bi_a + 1) begin
            if (wea[bi_a])
                mem[addra][bi_a*8 +: 8] <= dina[bi_a*8 +: 8];
        end
        douta_r <= mem[addra];
    end

    always @(posedge clkb) begin
        for (bi_b = 0; bi_b < 8; bi_b = bi_b + 1) begin
            if (web[bi_b])
                mem[addrb][bi_b*8 +: 8] <= dinb[bi_b*8 +: 8];
        end
        doutb_r <= mem[addrb];
    end
`endif
endmodule


// -----------------------------------------------------------------------------
// kyber_byte_bram_wide
//
// Word-oriented BRAM version.
// Interface keeps byte-addressed reads and wide writes:
//   - 64-bit byte-addressed write port, byte address, wstrb[7:0]
//   - legacy byte synchronous read port
//   - 64-bit byte-addressed synchronous read port
//
// The old implementation used 8 byte lanes and two read copies:
//   8 lanes * 2 copies = 16 forced tiny BRAMs per instance.
//
// This implementation stores bytes in 64-bit words with byte enables. Port B
// reads the wide word at wide_raddr[ADDR_WIDTH-1:3]. For unaligned wide reads,
// Port A reads the following word and the wrapper assembles the 64-bit window.
// Current project instances tie wclk/rclk/wide_rclk to the same clock.
// -----------------------------------------------------------------------------
module kyber_byte_bram_wide #(
    parameter ADDR_WIDTH = 11
)(
    input  wire wclk,

    // 64-bit byte-lane write port. wide_waddr is a BYTE address.
    input  wire wide_we,
    input  wire [ADDR_WIDTH-1:0] wide_waddr,
    input  wire [63:0] wide_din,
    input  wire [7:0] wide_wstrb,

    // Legacy byte synchronous read port
    input  wire rclk,
    input  wire [ADDR_WIDTH-1:0] raddr,
    output reg  [7:0] dout,

    // 64-bit synchronous read port. wide_raddr is a BYTE address.
    input  wire wide_rclk,
    input  wire wide_re,
    input  wire [ADDR_WIDTH-1:0] wide_raddr,
    output reg  [63:0] wide_dout
);
    localparam MEM_DEPTH = 1 << ADDR_WIDTH;
    localparam WORDS     = (MEM_DEPTH + 7) / 8;
    localparam WORD_AW   = (WORDS <= 2) ? 1 : $clog2(WORDS);
    localparam [WORD_AW-1:0] ONE_WORD = 1;

    wire [WORD_AW-1:0] wide_w_word     = wide_waddr >> 3;
    wire [WORD_AW-1:0] r_word          = raddr      >> 3;
    wire [WORD_AW-1:0] wide_r_word     = wide_raddr >> 3;
    wire [WORD_AW-1:0] wide_w_word_p1  = wide_w_word + ONE_WORD;
    wire [WORD_AW-1:0] wide_r_word_p1  = wide_r_word + ONE_WORD;

    reg [7:0] a_we;
    reg [7:0] b_we;
    reg [WORD_AW-1:0] a_addr;
    reg [WORD_AW-1:0] b_addr;
    reg [63:0] a_din;
    reg [63:0] b_din;

    wire [63:0] a_dout;
    wire [63:0] b_dout;

    integer wi;
    integer lane;

    always @(*) begin
        a_we   = 8'h00;
        b_we   = 8'h00;
        a_addr = r_word;
        b_addr = wide_r_word;
        a_din  = 64'd0;
        b_din  = 64'd0;

        if (wide_we) begin
            a_addr = wide_w_word;
            b_addr = wide_w_word_p1;
            for (wi = 0; wi < 8; wi = wi + 1) begin
                lane = wide_waddr[2:0] + wi;
                if (wide_wstrb[wi]) begin
                    if (lane < 8) begin
                        a_we[lane] = 1'b1;
                        a_din[lane*8 +: 8] = wide_din[wi*8 +: 8];
                    end else begin
                        b_we[lane-8] = 1'b1;
                        b_din[(lane-8)*8 +: 8] = wide_din[wi*8 +: 8];
                    end
                end
            end
        end else if (wide_re && (wide_raddr[2:0] != 3'd0)) begin
            a_addr = wide_r_word_p1;
        end
    end

    kyber_byte_word64_tdp_forcebram #(
        .ADDR_WIDTH(WORD_AW),
        .DEPTH(WORDS)
    ) u_word_ram (
        .clka  (wclk),
        .wea   (a_we),
        .addra (a_addr),
        .dina  (a_din),
        .douta (a_dout),

        .clkb  (wide_rclk),
        .web   (b_we),
        .addrb (b_addr),
        .dinb  (b_din),
        .doutb (b_dout)
    );

    reg [2:0] r_lane_q;
    reg [2:0] wide_r_lane_q;

    always @(posedge rclk) begin
        r_lane_q <= raddr[2:0];
    end

    always @(posedge wide_rclk) begin
        if (wide_re)
            wide_r_lane_q <= wide_raddr[2:0];
    end

    always @(*) begin
        case (r_lane_q)
            3'd0: dout = a_dout[ 7: 0];
            3'd1: dout = a_dout[15: 8];
            3'd2: dout = a_dout[23:16];
            3'd3: dout = a_dout[31:24];
            3'd4: dout = a_dout[39:32];
            3'd5: dout = a_dout[47:40];
            3'd6: dout = a_dout[55:48];
            default: dout = a_dout[63:56];
        endcase
    end

    always @(*) begin
        case (wide_r_lane_q)
            3'd0: wide_dout = b_dout;
            3'd1: wide_dout = {a_dout[ 7:0], b_dout[63: 8]};
            3'd2: wide_dout = {a_dout[15:0], b_dout[63:16]};
            3'd3: wide_dout = {a_dout[23:0], b_dout[63:24]};
            3'd4: wide_dout = {a_dout[31:0], b_dout[63:32]};
            3'd5: wide_dout = {a_dout[39:0], b_dout[63:40]};
            3'd6: wide_dout = {a_dout[47:0], b_dout[63:48]};
            default: wide_dout = {a_dout[55:0], b_dout[63:56]};
        endcase
    end
endmodule
