`timescale 1ns/1ps

// Single-master, multi-slave Wishbone B4 classic interconnect.
// Address presented to each slave is local byte offset from its BASE.
module wb_interconnect #(
    parameter [31:0] BOOT_BASE  = 32'h0000_0000,
    parameter [31:0] BOOT_SIZE  = 32'h0001_0000,
    parameter [31:0] SRAM_BASE  = 32'h0001_0000,
    parameter [31:0] SRAM_SIZE  = 32'h0001_0000,
    parameter [31:0] GPIO0_BASE = 32'h0002_0000,
    parameter [31:0] GPIO0_SIZE = 32'h0001_0000,
    parameter [31:0] GPIO1_BASE = 32'h0003_0000,
    parameter [31:0] GPIO1_SIZE = 32'h0001_0000,
    parameter [31:0] I2C_BASE   = 32'h0004_0000,
    parameter [31:0] I2C_SIZE   = 32'h0001_0000,
    parameter [31:0] PIC_BASE   = 32'h0005_0000,
    parameter [31:0] PIC_SIZE   = 32'h0001_0000,
    parameter [31:0] TIMER_BASE = 32'h0006_0000,
    parameter [31:0] TIMER_SIZE = 32'h0001_0000,
    parameter [31:0] UART_BASE  = 32'h0007_0000,
    parameter [31:0] UART_SIZE  = 32'h0001_0000,
    parameter [31:0] KYBER_BASE = 32'h0008_0000,
    parameter [31:0] KYBER_SIZE = 32'h0001_0000
)(
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] m_adr_i,
    input  wire [31:0] m_dat_i,
    output reg  [31:0] m_dat_o,
    input  wire [3:0]  m_sel_i,
    input  wire        m_we_i,
    input  wire        m_cyc_i,
    input  wire        m_stb_i,
    output reg         m_ack_o,
    output reg         m_err_o,

    output wire [31:0] boot_adr_o,
    output wire [31:0] boot_dat_o,
    input  wire [31:0] boot_dat_i,
    output wire [3:0]  boot_sel_o,
    output wire        boot_we_o,
    output wire        boot_cyc_o,
    output wire        boot_stb_o,
    input  wire        boot_ack_i,
    input  wire        boot_err_i,

    output wire [31:0] sram_adr_o,
    output wire [31:0] sram_dat_o,
    input  wire [31:0] sram_dat_i,
    output wire [3:0]  sram_sel_o,
    output wire        sram_we_o,
    output wire        sram_cyc_o,
    output wire        sram_stb_o,
    input  wire        sram_ack_i,
    input  wire        sram_err_i,

    output wire [31:0] gpio0_adr_o,
    output wire [31:0] gpio0_dat_o,
    input  wire [31:0] gpio0_dat_i,
    output wire [3:0]  gpio0_sel_o,
    output wire        gpio0_we_o,
    output wire        gpio0_cyc_o,
    output wire        gpio0_stb_o,
    input  wire        gpio0_ack_i,
    input  wire        gpio0_err_i,

    output wire [31:0] gpio1_adr_o,
    output wire [31:0] gpio1_dat_o,
    input  wire [31:0] gpio1_dat_i,
    output wire [3:0]  gpio1_sel_o,
    output wire        gpio1_we_o,
    output wire        gpio1_cyc_o,
    output wire        gpio1_stb_o,
    input  wire        gpio1_ack_i,
    input  wire        gpio1_err_i,

    output wire [31:0] i2c_adr_o,
    output wire [31:0] i2c_dat_o,
    input  wire [31:0] i2c_dat_i,
    output wire [3:0]  i2c_sel_o,
    output wire        i2c_we_o,
    output wire        i2c_cyc_o,
    output wire        i2c_stb_o,
    input  wire        i2c_ack_i,
    input  wire        i2c_err_i,

    output wire [31:0] pic_adr_o,
    output wire [31:0] pic_dat_o,
    input  wire [31:0] pic_dat_i,
    output wire [3:0]  pic_sel_o,
    output wire        pic_we_o,
    output wire        pic_cyc_o,
    output wire        pic_stb_o,
    input  wire        pic_ack_i,
    input  wire        pic_err_i,

    output wire [31:0] timer_adr_o,
    output wire [31:0] timer_dat_o,
    input  wire [31:0] timer_dat_i,
    output wire [3:0]  timer_sel_o,
    output wire        timer_we_o,
    output wire        timer_cyc_o,
    output wire        timer_stb_o,
    input  wire        timer_ack_i,
    input  wire        timer_err_i,

    output wire [31:0] uart_adr_o,
    output wire [31:0] uart_dat_o,
    input  wire [31:0] uart_dat_i,
    output wire [3:0]  uart_sel_o,
    output wire        uart_we_o,
    output wire        uart_cyc_o,
    output wire        uart_stb_o,
    input  wire        uart_ack_i,
    input  wire        uart_err_i,

    output wire [31:0] kyber_adr_o,
    output wire [31:0] kyber_dat_o,
    input  wire [31:0] kyber_dat_i,
    output wire [3:0]  kyber_sel_o,
    output wire        kyber_we_o,
    output wire        kyber_cyc_o,
    output wire        kyber_stb_o,
    input  wire        kyber_ack_i,
    input  wire        kyber_err_i
);

    wire sel_boot  = (m_adr_i >= BOOT_BASE)  && (m_adr_i < BOOT_BASE  + BOOT_SIZE);
    wire sel_sram  = (m_adr_i >= SRAM_BASE)  && (m_adr_i < SRAM_BASE  + SRAM_SIZE);
    wire sel_gpio0 = (m_adr_i >= GPIO0_BASE) && (m_adr_i < GPIO0_BASE + GPIO0_SIZE);
    wire sel_gpio1 = (m_adr_i >= GPIO1_BASE) && (m_adr_i < GPIO1_BASE + GPIO1_SIZE);
    wire sel_i2c   = (m_adr_i >= I2C_BASE)   && (m_adr_i < I2C_BASE   + I2C_SIZE);
    wire sel_pic   = (m_adr_i >= PIC_BASE)   && (m_adr_i < PIC_BASE   + PIC_SIZE);
    wire sel_timer = (m_adr_i >= TIMER_BASE) && (m_adr_i < TIMER_BASE + TIMER_SIZE);
    wire sel_uart  = (m_adr_i >= UART_BASE)  && (m_adr_i < UART_BASE  + UART_SIZE);
    wire sel_kyber = (m_adr_i >= KYBER_BASE) && (m_adr_i < KYBER_BASE + KYBER_SIZE);
    wire sel_none  = m_cyc_i & m_stb_i &
                     ~(sel_boot | sel_sram | sel_gpio0 | sel_gpio1 |
                       sel_i2c | sel_pic | sel_timer | sel_uart | sel_kyber);

    assign boot_adr_o  = m_adr_i - BOOT_BASE;
    assign sram_adr_o  = m_adr_i - SRAM_BASE;
    assign gpio0_adr_o = m_adr_i - GPIO0_BASE;
    assign gpio1_adr_o = m_adr_i - GPIO1_BASE;
    assign i2c_adr_o   = m_adr_i - I2C_BASE;
    assign pic_adr_o   = m_adr_i - PIC_BASE;
    assign timer_adr_o = m_adr_i - TIMER_BASE;
    assign uart_adr_o  = m_adr_i - UART_BASE;
    assign kyber_adr_o = m_adr_i - KYBER_BASE;

    assign boot_dat_o  = m_dat_i;
    assign sram_dat_o  = m_dat_i;
    assign gpio0_dat_o = m_dat_i;
    assign gpio1_dat_o = m_dat_i;
    assign i2c_dat_o   = m_dat_i;
    assign pic_dat_o   = m_dat_i;
    assign timer_dat_o = m_dat_i;
    assign uart_dat_o  = m_dat_i;
    assign kyber_dat_o = m_dat_i;

    assign boot_sel_o  = m_sel_i;
    assign sram_sel_o  = m_sel_i;
    assign gpio0_sel_o = m_sel_i;
    assign gpio1_sel_o = m_sel_i;
    assign i2c_sel_o   = m_sel_i;
    assign pic_sel_o   = m_sel_i;
    assign timer_sel_o = m_sel_i;
    assign uart_sel_o  = m_sel_i;
    assign kyber_sel_o = m_sel_i;

    assign boot_we_o  = m_we_i;
    assign sram_we_o  = m_we_i;
    assign gpio0_we_o = m_we_i;
    assign gpio1_we_o = m_we_i;
    assign i2c_we_o   = m_we_i;
    assign pic_we_o   = m_we_i;
    assign timer_we_o = m_we_i;
    assign uart_we_o  = m_we_i;
    assign kyber_we_o = m_we_i;

    assign boot_cyc_o  = m_cyc_i & sel_boot;
    assign sram_cyc_o  = m_cyc_i & sel_sram;
    assign gpio0_cyc_o = m_cyc_i & sel_gpio0;
    assign gpio1_cyc_o = m_cyc_i & sel_gpio1;
    assign i2c_cyc_o   = m_cyc_i & sel_i2c;
    assign pic_cyc_o   = m_cyc_i & sel_pic;
    assign timer_cyc_o = m_cyc_i & sel_timer;
    assign uart_cyc_o  = m_cyc_i & sel_uart;
    assign kyber_cyc_o = m_cyc_i & sel_kyber;

    assign boot_stb_o  = m_stb_i & sel_boot;
    assign sram_stb_o  = m_stb_i & sel_sram;
    assign gpio0_stb_o = m_stb_i & sel_gpio0;
    assign gpio1_stb_o = m_stb_i & sel_gpio1;
    assign i2c_stb_o   = m_stb_i & sel_i2c;
    assign pic_stb_o   = m_stb_i & sel_pic;
    assign timer_stb_o = m_stb_i & sel_timer;
    assign uart_stb_o  = m_stb_i & sel_uart;
    assign kyber_stb_o = m_stb_i & sel_kyber;

    reg none_err_pending;
    always @(posedge clk) begin
        if (rst) begin
            none_err_pending <= 1'b0;
        end else begin
            if (sel_none && !none_err_pending)
                none_err_pending <= 1'b1;
            else
                none_err_pending <= 1'b0;
        end
    end

    always @(*) begin
        m_dat_o = 32'd0;
        m_ack_o = 1'b0;
        m_err_o = none_err_pending;
        if (sel_boot) begin
            m_dat_o = boot_dat_i; m_ack_o = boot_ack_i; m_err_o = boot_err_i;
        end else if (sel_sram) begin
            m_dat_o = sram_dat_i; m_ack_o = sram_ack_i; m_err_o = sram_err_i;
        end else if (sel_gpio0) begin
            m_dat_o = gpio0_dat_i; m_ack_o = gpio0_ack_i; m_err_o = gpio0_err_i;
        end else if (sel_gpio1) begin
            m_dat_o = gpio1_dat_i; m_ack_o = gpio1_ack_i; m_err_o = gpio1_err_i;
        end else if (sel_i2c) begin
            m_dat_o = i2c_dat_i; m_ack_o = i2c_ack_i; m_err_o = i2c_err_i;
        end else if (sel_pic) begin
            m_dat_o = pic_dat_i; m_ack_o = pic_ack_i; m_err_o = pic_err_i;
        end else if (sel_timer) begin
            m_dat_o = timer_dat_i; m_ack_o = timer_ack_i; m_err_o = timer_err_i;
        end else if (sel_uart) begin
            m_dat_o = uart_dat_i; m_ack_o = uart_ack_i; m_err_o = uart_err_i;
        end else if (sel_kyber) begin
            m_dat_o = kyber_dat_i; m_ack_o = kyber_ack_i; m_err_o = kyber_err_i;
        end
    end
endmodule
