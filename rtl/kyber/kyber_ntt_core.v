`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// kyber_ntt_core
// Kyber512 RTL source. Comments and unused debug-only code were removed for a
// synthesis-oriented release build.
// -----------------------------------------------------------------------------

module kyber_ntt_core (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire mode,               
    input  wire intt_gs_en,

    
    input  wire        ext_we,
    input  wire        ext_we_b,
    input  wire [7:0]  ext_addr,
    input  wire [7:0]  ext_addr_b,
    input  wire signed [15:0] ext_din,
    input  wire signed [15:0] ext_din_b,
    output wire signed [15:0] ext_dout,
    output wire signed [15:0] ext_dout_b, 

    input  wire [6:0] ext_twiddle_addr,
    output wire signed [15:0] ext_twiddle_dout,

    output reg  done
);

    
    
    
    reg [2:0] state;
    reg [2:0] stage;
    reg [7:0] cnt;
    reg [3:0] warm_cnt;
localparam IDLE = 3'd0;
    localparam WARM = 3'd1;
    localparam CALC = 3'd2;
    localparam PREP = 3'd3;
    localparam DONE = 3'd4;
    localparam integer BF_DELAY = 10;

    wire [7:0]  addr_a, addr_b;
    wire [6:0]  twiddle_addr;

    wire signed [15:0] ram0_dout_a_raw, ram0_dout_b_raw;
    wire signed [15:0] ram1_dout_a_raw, ram1_dout_b_raw;
    wire signed [15:0] zeta_raw;
    reg  signed [15:0] ram0_dout_a_r, ram0_dout_b_r;
    reg  signed [15:0] ram1_dout_a_r, ram1_dout_b_r;
    reg  signed [15:0] zeta_r;

    wire signed [15:0] bf_in_a, bf_in_b;
    wire signed [15:0] bf_out_a, bf_out_b;

    
    
    
    kyber_ntt_address_generator u_addr_gen (
        .stage(stage), .inv_gs_en(intt_gs_en && mode), .cnt(cnt[6:0]),
        .addr_a(addr_a), .addr_b(addr_b), .twiddle_addr(twiddle_addr)
    );

    wire [6:0] twiddle_rom_addr =
        (state == IDLE) ? ext_twiddle_addr : twiddle_addr;

    kyber_twiddle_rom #(.USE_PWMA(1'b0)) u_twiddle (
        .clk(clk), .addr(twiddle_rom_addr), .dout(zeta_raw)
    );
    assign ext_twiddle_dout = zeta_raw;

    wire is_even_stage = (stage[0] == 1'b0);

    always @(posedge clk) begin
        if (rst) begin
            ram0_dout_a_r <= 16'sd0;
            ram0_dout_b_r <= 16'sd0;
            ram1_dout_a_r <= 16'sd0;
            ram1_dout_b_r <= 16'sd0;
            zeta_r        <= 16'sd0;
        end else begin
            ram0_dout_a_r <= ram0_dout_a_raw;
            ram0_dout_b_r <= ram0_dout_b_raw;
            ram1_dout_a_r <= ram1_dout_a_raw;
            ram1_dout_b_r <= ram1_dout_b_raw;
            zeta_r        <= zeta_raw;
        end
    end

    assign bf_in_a = is_even_stage ? ram0_dout_a_r : ram1_dout_a_r;
    assign bf_in_b = is_even_stage ? ram0_dout_b_r : ram1_dout_b_r;

    kyber_ntt_butterfly u_butterfly (
        .clk(clk), .rst(rst), .mode(mode),
        .a(bf_in_a), .b(bf_in_b), .zeta(zeta_r),
        .out_a(bf_out_a), .out_b(bf_out_b)
    );

    
    
    
    reg [7:0] delay_addr_a [0:BF_DELAY-1];
    reg [7:0] delay_addr_b [0:BF_DELAY-1];
    reg       delay_we     [0:BF_DELAY-1];
    reg       delay_we_any;
    integer   delay_i;

    always @(posedge clk) begin
        if (rst) begin
            for (delay_i = 0; delay_i < BF_DELAY; delay_i = delay_i + 1) begin
                delay_addr_a[delay_i] <= 8'd0;
                delay_addr_b[delay_i] <= 8'd0;
                delay_we[delay_i]     <= 1'b0;
            end
        end else begin
            delay_addr_a[0] <= addr_a;
            delay_addr_b[0] <= addr_b;
            delay_we[0] <= (state == CALC && cnt < 8'd128);
            for (delay_i = 1; delay_i < BF_DELAY; delay_i = delay_i + 1) begin
                delay_addr_a[delay_i] <= delay_addr_a[delay_i-1];
                delay_addr_b[delay_i] <= delay_addr_b[delay_i-1];
                delay_we[delay_i]     <= delay_we[delay_i-1];
            end
        end
    end

    always @(*) begin
        delay_we_any = 1'b0;
        for (delay_i = 0; delay_i < BF_DELAY; delay_i = delay_i + 1)
            delay_we_any = delay_we_any | delay_we[delay_i];
    end

    
    
    

    wire we_ram0_a = (state == IDLE) ? ext_we   : (!is_even_stage ? delay_we[BF_DELAY-1] : 1'b0);
    wire we_ram0_b = (state == IDLE) ? ext_we_b : (!is_even_stage ? delay_we[BF_DELAY-1] : 1'b0);
    wire we_ram1   = (state == IDLE) ? 1'b0     : (is_even_stage ? delay_we[BF_DELAY-1] : 1'b0);

    wire [7:0] ram0_addr_a = (state == IDLE) ? ext_addr   : (we_ram0_a ? delay_addr_a[BF_DELAY-1] : addr_a);
    wire [7:0] ram0_addr_b = (state == IDLE) ? ext_addr_b : (we_ram0_b ? delay_addr_b[BF_DELAY-1] : addr_b);

    
    wire [7:0] ram1_addr_a = (state == IDLE) ? ext_addr
                                              : (we_ram1 ? delay_addr_a[BF_DELAY-1] : addr_a);

    
    
    
    wire [7:0] ram1_addr_b = (state == IDLE) ? (ext_addr + 8'd1)
                                              : (we_ram1 ? delay_addr_b[BF_DELAY-1] : addr_b);

    wire signed [15:0] ram0_din_a = (state == IDLE) ? ext_din   : bf_out_a;
    wire signed [15:0] ram0_din_b = (state == IDLE) ? ext_din_b : bf_out_b;

    kyber_dual_port_ram u_ram0 (
        .clk(clk),
        .we_a(we_ram0_a), .addr_a(ram0_addr_a), .din_a(ram0_din_a), .dout_a(ram0_dout_a_raw),
        .we_b(we_ram0_b), .addr_b(ram0_addr_b), .din_b(ram0_din_b), .dout_b(ram0_dout_b_raw)
    );

    kyber_dual_port_ram u_ram1 (
        .clk(clk),
        .we_a(we_ram1), .addr_a(ram1_addr_a), .din_a(bf_out_a), .dout_a(ram1_dout_a_raw),
        .we_b(we_ram1), .addr_b(ram1_addr_b), .din_b(bf_out_b), .dout_b(ram1_dout_b_raw)
    );

    
    
    
    reg last_write_ram;

    always @(posedge clk) begin
        if (rst) begin
            last_write_ram <= 1'b1;
        end else begin
            if (state == IDLE && (ext_we || ext_we_b))
                last_write_ram <= 1'b0;
            else if (state == DONE)
                last_write_ram <= 1'b1;
        end
    end

    
    
    
    assign ext_dout   = (last_write_ram == 1'b1) ? ram1_dout_a_r : ram0_dout_a_r;
    assign ext_dout_b = (last_write_ram == 1'b1) ? ram1_dout_b_r : ram0_dout_b_r;

    
    
    
    always @(posedge clk) begin
        if (rst) begin
            state    <= IDLE;
            stage    <= 3'd0;
            cnt      <= 8'd0;
            warm_cnt <= 2'd0;
            done     <= 1'b0;
end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
state    <= WARM;
                        stage    <= 3'd0;
                        cnt      <= 8'd0;
                        warm_cnt <= 4'd0;
                    end
                end

                WARM: begin
                    
                    
                    if ((mode && intt_gs_en) ? (warm_cnt == 4'd3) : (warm_cnt == 4'd2)) begin
                        state    <= CALC;
                        cnt      <= 8'd0;
                        warm_cnt <= 4'd0;
                    end else begin
                        warm_cnt <= warm_cnt + 4'd1;
                    end
                end

                CALC: begin
                    if (cnt == 8'd128) begin
                        state <= PREP;
                        cnt   <= 8'd0;
                    end else begin
                        cnt <= cnt + 8'd1;
                    end
                end

                PREP: begin
                    if (!delay_we_any) begin
                        if (stage == 3'd6) begin
                            state <= DONE;
                        end else begin
                            stage    <= stage + 3'd1;
                            state    <= WARM;
                            warm_cnt <= 4'd0;
                        end
                    end
                end

                DONE: begin
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
