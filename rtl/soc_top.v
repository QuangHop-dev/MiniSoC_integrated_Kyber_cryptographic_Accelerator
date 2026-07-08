`timescale 1ns/1ps

module soc_top #(
    parameter integer CLK_FREQ_HZ     = 50_000_000,
    parameter integer GPIO_WIDTH      = 8,
    parameter integer BOOT_BYTES      = 16*1024,
    parameter integer BOOT_WRITABLE   = 0,
    parameter integer BOOTLOADER_ENABLE = 0,
    parameter integer BOOT_ROM_BYTES  = 16*1024,
    parameter integer SRAM_BYTES      = 16*1024,
    parameter integer KYBER_DATA_BYTES = 8192,
    parameter         BOOT_INIT_FILE  = "",
    parameter         SRAM_INIT_FILE  = "",
    parameter [31:0]  RESET_VECTOR    = 32'h0000_0000
)(
    input  wire                   clk_i,
    input  wire                   rst_i,

    input  wire [GPIO_WIDTH-1:0]  gpio0_i,
    output wire [GPIO_WIDTH-1:0]  gpio0_o,
    output wire [GPIO_WIDTH-1:0]  gpio0_oe,

    input  wire [GPIO_WIDTH-1:0]  gpio1_i,
    output wire [GPIO_WIDTH-1:0]  gpio1_o,
    output wire [GPIO_WIDTH-1:0]  gpio1_oe,

    input  wire                   i2c_scl_i,
    output wire                   i2c_scl_o,
    output wire                   i2c_scl_oe,
    input  wire                   i2c_sda_i,
    output wire                   i2c_sda_o,
    output wire                   i2c_sda_oe,

    input  wire                   uart_rx_i,
    output wire                   uart_tx_o,

    input  wire [1:0]             ext_irq_i,
    output wire                   irq_o,
    output wire [31:0]            irq_vector_o,

    output wire                   cpu_trap_o,
    output wire                   cpu_halted_o,
    output wire [31:0]            cpu_fault_pc_o,
    output wire [31:0]            cpu_fault_cause_o,
    output wire [31:0]            cpu_pc_o
);
    localparam [31:0] BOOT_BASE  = 32'h0000_0000;
    localparam [31:0] BOOT_SIZE  = BOOT_BYTES;
    localparam [31:0] SRAM_BASE  = 32'h0001_0000;
    localparam [31:0] SRAM_SIZE  = SRAM_BYTES;
    localparam [31:0] GPIO0_BASE = 32'h0002_0000;
    localparam [31:0] GPIO0_SIZE = 32'h0001_0000;
    localparam [31:0] GPIO1_BASE = 32'h0003_0000;
    localparam [31:0] GPIO1_SIZE = 32'h0001_0000;
    localparam [31:0] I2C_BASE   = 32'h0004_0000;
    localparam [31:0] I2C_SIZE   = 32'h0001_0000;
    localparam [31:0] PIC_BASE   = 32'h0005_0000;
    localparam [31:0] PIC_SIZE   = 32'h0001_0000;
    localparam [31:0] TIMER_BASE = 32'h0006_0000;
    localparam [31:0] TIMER_SIZE = 32'h0001_0000;
    localparam [31:0] UART_BASE  = 32'h0007_0000;
    localparam [31:0] UART_SIZE  = 32'h0001_0000;
    localparam [31:0] KYBER_BASE = 32'h0008_0000;
    localparam [31:0] KYBER_SIZE = 32'h0001_0000;

    wire [31:0] cpu_wb_adr;
    wire [31:0] cpu_wb_dat_o;
    wire [31:0] cpu_wb_dat_i;
    wire [3:0]  cpu_wb_sel;
    wire        cpu_wb_we;
    wire        cpu_wb_cyc;
    wire        cpu_wb_stb;
    wire        cpu_wb_ack;
    wire        cpu_wb_err;

    wire [31:0] boot_adr;
    wire [31:0] boot_dat_o;
    wire [31:0] boot_dat_i;
    wire [3:0]  boot_sel;
    wire        boot_we;
    wire        boot_cyc;
    wire        boot_stb;
    wire        boot_ack;
    wire        boot_err;

    wire [31:0] sram_adr;
    wire [31:0] sram_dat_o;
    wire [31:0] sram_dat_i;
    wire [3:0]  sram_sel;
    wire        sram_we;
    wire        sram_cyc;
    wire        sram_stb;
    wire        sram_ack;
    wire        sram_err;

    wire [31:0] gpio0_adr;
    wire [31:0] gpio0_dat_o;
    wire [31:0] gpio0_dat_i;
    wire [3:0]  gpio0_sel;
    wire        gpio0_we;
    wire        gpio0_cyc;
    wire        gpio0_stb;
    wire        gpio0_ack;
    wire        gpio0_err;

    wire [31:0] gpio1_adr;
    wire [31:0] gpio1_dat_o;
    wire [31:0] gpio1_dat_i;
    wire [3:0]  gpio1_sel;
    wire        gpio1_we;
    wire        gpio1_cyc;
    wire        gpio1_stb;
    wire        gpio1_ack;
    wire        gpio1_err;

    wire [31:0] i2c_adr;
    wire [31:0] i2c_dat_o;
    wire [31:0] i2c_dat_i;
    wire [3:0]  i2c_sel;
    wire        i2c_we;
    wire        i2c_cyc;
    wire        i2c_stb;
    wire        i2c_ack;
    wire        i2c_err;

    wire [31:0] pic_adr;
    wire [31:0] pic_dat_o;
    wire [31:0] pic_dat_i;
    wire [3:0]  pic_sel;
    wire        pic_we;
    wire        pic_cyc;
    wire        pic_stb;
    wire        pic_ack;
    wire        pic_err;

    wire [31:0] timer_adr;
    wire [31:0] timer_dat_o;
    wire [31:0] timer_dat_i;
    wire [3:0]  timer_sel;
    wire        timer_we;
    wire        timer_cyc;
    wire        timer_stb;
    wire        timer_ack;
    wire        timer_err;

    wire [31:0] uart_adr;
    wire [31:0] uart_dat_o;
    wire [31:0] uart_dat_i;
    wire [3:0]  uart_sel;
    wire        uart_we;
    wire        uart_cyc;
    wire        uart_stb;
    wire        uart_ack;
    wire        uart_err;

    wire [31:0] kyber_adr;
    wire [31:0] kyber_dat_o;
    wire [31:0] kyber_dat_i;
    wire [3:0]  kyber_sel;
    wire        kyber_we;
    wire        kyber_cyc;
    wire        kyber_stb;
    wire        kyber_ack;
    wire        kyber_err;

    wire gpio0_irq;
    wire gpio1_irq;
    wire i2c_irq;
    wire timer_irq;
    wire uart_irq;
    wire kyber_irq;
    wire pic_irq;
    wire [7:0] irq_sources = {
        ext_irq_i[1],
        ext_irq_i[0],
        kyber_irq,
        uart_irq,
        timer_irq,
        i2c_irq,
        gpio1_irq,
        gpio0_irq
    };

    assign irq_o = pic_irq;

    rv32i_2stage_wb #(
        .RESET_VECTOR(RESET_VECTOR)
    ) u_cpu (
        .clk(clk_i),
        .rst(rst_i),
        .irq_i(pic_irq),
        .trap_o(cpu_trap_o),
        .halted_o(cpu_halted_o),
        .fault_pc_o(cpu_fault_pc_o),
        .fault_cause_o(cpu_fault_cause_o),
        .pc_debug_o(cpu_pc_o),
        .wb_adr_o(cpu_wb_adr),
        .wb_dat_o(cpu_wb_dat_o),
        .wb_dat_i(cpu_wb_dat_i),
        .wb_sel_o(cpu_wb_sel),
        .wb_we_o(cpu_wb_we),
        .wb_cyc_o(cpu_wb_cyc),
        .wb_stb_o(cpu_wb_stb),
        .wb_ack_i(cpu_wb_ack),
        .wb_err_i(cpu_wb_err)
    );

    wb_interconnect #(
        .BOOT_BASE(BOOT_BASE),   .BOOT_SIZE(BOOT_SIZE),
        .SRAM_BASE(SRAM_BASE),   .SRAM_SIZE(SRAM_SIZE),
        .GPIO0_BASE(GPIO0_BASE), .GPIO0_SIZE(GPIO0_SIZE),
        .GPIO1_BASE(GPIO1_BASE), .GPIO1_SIZE(GPIO1_SIZE),
        .I2C_BASE(I2C_BASE),     .I2C_SIZE(I2C_SIZE),
        .PIC_BASE(PIC_BASE),     .PIC_SIZE(PIC_SIZE),
        .TIMER_BASE(TIMER_BASE), .TIMER_SIZE(TIMER_SIZE),
        .UART_BASE(UART_BASE),   .UART_SIZE(UART_SIZE),
        .KYBER_BASE(KYBER_BASE), .KYBER_SIZE(KYBER_SIZE)
    ) u_bus (
        .clk(clk_i),
        .rst(rst_i),
        .m_adr_i(cpu_wb_adr),
        .m_dat_i(cpu_wb_dat_o),
        .m_dat_o(cpu_wb_dat_i),
        .m_sel_i(cpu_wb_sel),
        .m_we_i(cpu_wb_we),
        .m_cyc_i(cpu_wb_cyc),
        .m_stb_i(cpu_wb_stb),
        .m_ack_o(cpu_wb_ack),
        .m_err_o(cpu_wb_err),
        .boot_adr_o(boot_adr),
        .boot_dat_o(boot_dat_o),
        .boot_dat_i(boot_dat_i),
        .boot_sel_o(boot_sel),
        .boot_we_o(boot_we),
        .boot_cyc_o(boot_cyc),
        .boot_stb_o(boot_stb),
        .boot_ack_i(boot_ack),
        .boot_err_i(boot_err),
        .sram_adr_o(sram_adr),
        .sram_dat_o(sram_dat_o),
        .sram_dat_i(sram_dat_i),
        .sram_sel_o(sram_sel),
        .sram_we_o(sram_we),
        .sram_cyc_o(sram_cyc),
        .sram_stb_o(sram_stb),
        .sram_ack_i(sram_ack),
        .sram_err_i(sram_err),
        .gpio0_adr_o(gpio0_adr),
        .gpio0_dat_o(gpio0_dat_o),
        .gpio0_dat_i(gpio0_dat_i),
        .gpio0_sel_o(gpio0_sel),
        .gpio0_we_o(gpio0_we),
        .gpio0_cyc_o(gpio0_cyc),
        .gpio0_stb_o(gpio0_stb),
        .gpio0_ack_i(gpio0_ack),
        .gpio0_err_i(gpio0_err),
        .gpio1_adr_o(gpio1_adr),
        .gpio1_dat_o(gpio1_dat_o),
        .gpio1_dat_i(gpio1_dat_i),
        .gpio1_sel_o(gpio1_sel),
        .gpio1_we_o(gpio1_we),
        .gpio1_cyc_o(gpio1_cyc),
        .gpio1_stb_o(gpio1_stb),
        .gpio1_ack_i(gpio1_ack),
        .gpio1_err_i(gpio1_err),
        .i2c_adr_o(i2c_adr),
        .i2c_dat_o(i2c_dat_o),
        .i2c_dat_i(i2c_dat_i),
        .i2c_sel_o(i2c_sel),
        .i2c_we_o(i2c_we),
        .i2c_cyc_o(i2c_cyc),
        .i2c_stb_o(i2c_stb),
        .i2c_ack_i(i2c_ack),
        .i2c_err_i(i2c_err),
        .pic_adr_o(pic_adr),
        .pic_dat_o(pic_dat_o),
        .pic_dat_i(pic_dat_i),
        .pic_sel_o(pic_sel),
        .pic_we_o(pic_we),
        .pic_cyc_o(pic_cyc),
        .pic_stb_o(pic_stb),
        .pic_ack_i(pic_ack),
        .pic_err_i(pic_err),
        .timer_adr_o(timer_adr),
        .timer_dat_o(timer_dat_o),
        .timer_dat_i(timer_dat_i),
        .timer_sel_o(timer_sel),
        .timer_we_o(timer_we),
        .timer_cyc_o(timer_cyc),
        .timer_stb_o(timer_stb),
        .timer_ack_i(timer_ack),
        .timer_err_i(timer_err),
        .uart_adr_o(uart_adr),
        .uart_dat_o(uart_dat_o),
        .uart_dat_i(uart_dat_i),
        .uart_sel_o(uart_sel),
        .uart_we_o(uart_we),
        .uart_cyc_o(uart_cyc),
        .uart_stb_o(uart_stb),
        .uart_ack_i(uart_ack),
        .uart_err_i(uart_err),
        .kyber_adr_o(kyber_adr),
        .kyber_dat_o(kyber_dat_o),
        .kyber_dat_i(kyber_dat_i),
        .kyber_sel_o(kyber_sel),
        .kyber_we_o(kyber_we),
        .kyber_cyc_o(kyber_cyc),
        .kyber_stb_o(kyber_stb),
        .kyber_ack_i(kyber_ack),
        .kyber_err_i(kyber_err)
    );

    generate
        if (BOOTLOADER_ENABLE != 0) begin : gen_bootloader_mem
            bootloader_mem_wb #(
                .BOOT_BYTES(BOOT_BYTES),
                .ROM_BYTES(BOOT_ROM_BYTES),
                .INIT_FILE(BOOT_INIT_FILE)
            ) u_bootloader_mem (
                .wb_clk_i(clk_i),
                .wb_rst_i(rst_i),
                .wb_adr_i(boot_adr),
                .wb_dat_i(boot_dat_o),
                .wb_dat_o(boot_dat_i),
                .wb_sel_i(boot_sel),
                .wb_we_i(boot_we),
                .wb_cyc_i(boot_cyc),
                .wb_stb_i(boot_stb),
                .wb_ack_o(boot_ack),
                .wb_err_o(boot_err)
            );
        end else if (BOOT_WRITABLE != 0) begin : gen_imem
            imem_wb #(
                .IMEM_BYTES(BOOT_BYTES),
                .INIT_FILE(BOOT_INIT_FILE)
            ) u_boot_imem (
                .wb_clk_i(clk_i),
                .wb_rst_i(rst_i),
                .wb_adr_i(boot_adr),
                .wb_dat_i(boot_dat_o),
                .wb_dat_o(boot_dat_i),
                .wb_sel_i(boot_sel),
                .wb_we_i(boot_we),
                .wb_cyc_i(boot_cyc),
                .wb_stb_i(boot_stb),
                .wb_ack_o(boot_ack),
                .wb_err_o(boot_err)
            );
        end else begin : gen_boot_rom
            boot_rom_wb #(
                .ROM_BYTES(BOOT_BYTES),
                .INIT_FILE(BOOT_INIT_FILE)
            ) u_boot_rom (
                .wb_clk_i(clk_i),
                .wb_rst_i(rst_i),
                .wb_adr_i(boot_adr),
                .wb_dat_i(boot_dat_o),
                .wb_dat_o(boot_dat_i),
                .wb_sel_i(boot_sel),
                .wb_we_i(boot_we),
                .wb_cyc_i(boot_cyc),
                .wb_stb_i(boot_stb),
                .wb_ack_o(boot_ack),
                .wb_err_o(boot_err)
            );
        end
    endgenerate

    sram_wb #(
        .SRAM_BYTES(SRAM_BYTES),
        .INIT_FILE(SRAM_INIT_FILE)
    ) u_sram (
        .wb_clk_i(clk_i),
        .wb_rst_i(rst_i),
        .wb_adr_i(sram_adr),
        .wb_dat_i(sram_dat_o),
        .wb_dat_o(sram_dat_i),
        .wb_sel_i(sram_sel),
        .wb_we_i(sram_we),
        .wb_cyc_i(sram_cyc),
        .wb_stb_i(sram_stb),
        .wb_ack_o(sram_ack),
        .wb_err_o(sram_err)
    );

    gpio_wb #(.WIDTH(GPIO_WIDTH)) u_gpio0 (
        .wb_clk_i(clk_i),
        .wb_rst_i(rst_i),
        .wb_adr_i(gpio0_adr),
        .wb_dat_i(gpio0_dat_o),
        .wb_dat_o(gpio0_dat_i),
        .wb_sel_i(gpio0_sel),
        .wb_we_i(gpio0_we),
        .wb_cyc_i(gpio0_cyc),
        .wb_stb_i(gpio0_stb),
        .wb_ack_o(gpio0_ack),
        .wb_err_o(gpio0_err),
        .gpio_i(gpio0_i),
        .gpio_o(gpio0_o),
        .gpio_oe(gpio0_oe),
        .irq_o(gpio0_irq)
    );

    gpio_wb #(.WIDTH(GPIO_WIDTH)) u_gpio1 (
        .wb_clk_i(clk_i),
        .wb_rst_i(rst_i),
        .wb_adr_i(gpio1_adr),
        .wb_dat_i(gpio1_dat_o),
        .wb_dat_o(gpio1_dat_i),
        .wb_sel_i(gpio1_sel),
        .wb_we_i(gpio1_we),
        .wb_cyc_i(gpio1_cyc),
        .wb_stb_i(gpio1_stb),
        .wb_ack_o(gpio1_ack),
        .wb_err_o(gpio1_err),
        .gpio_i(gpio1_i),
        .gpio_o(gpio1_o),
        .gpio_oe(gpio1_oe),
        .irq_o(gpio1_irq)
    );

    i2c_wb u_i2c (
        .wb_clk_i(clk_i),
        .wb_rst_i(rst_i),
        .wb_adr_i(i2c_adr),
        .wb_dat_i(i2c_dat_o),
        .wb_dat_o(i2c_dat_i),
        .wb_sel_i(i2c_sel),
        .wb_we_i(i2c_we),
        .wb_cyc_i(i2c_cyc),
        .wb_stb_i(i2c_stb),
        .wb_ack_o(i2c_ack),
        .wb_err_o(i2c_err),
        .scl_i(i2c_scl_i),
        .scl_o(i2c_scl_o),
        .scl_oe(i2c_scl_oe),
        .sda_i(i2c_sda_i),
        .sda_o(i2c_sda_o),
        .sda_oe(i2c_sda_oe),
        .irq_o(i2c_irq)
    );

    pic_wb #(.NIRQ(8)) u_pic (
        .wb_clk_i(clk_i),
        .wb_rst_i(rst_i),
        .wb_adr_i(pic_adr),
        .wb_dat_i(pic_dat_o),
        .wb_dat_o(pic_dat_i),
        .wb_sel_i(pic_sel),
        .wb_we_i(pic_we),
        .wb_cyc_i(pic_cyc),
        .wb_stb_i(pic_stb),
        .wb_ack_o(pic_ack),
        .wb_err_o(pic_err),
        .irq_sources_i(irq_sources),
        .irq_o(pic_irq),
        .irq_vector_o(irq_vector_o)
    );

    timer_wb u_timer (
        .wb_clk_i(clk_i),
        .wb_rst_i(rst_i),
        .wb_adr_i(timer_adr),
        .wb_dat_i(timer_dat_o),
        .wb_dat_o(timer_dat_i),
        .wb_sel_i(timer_sel),
        .wb_we_i(timer_we),
        .wb_cyc_i(timer_cyc),
        .wb_stb_i(timer_stb),
        .wb_ack_o(timer_ack),
        .wb_err_o(timer_err),
        .irq_o(timer_irq)
    );

    uart_wb #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_DEFAULT(115200)
    ) u_uart (
        .wb_clk_i(clk_i),
        .wb_rst_i(rst_i),
        .wb_adr_i(uart_adr),
        .wb_dat_i(uart_dat_o),
        .wb_dat_o(uart_dat_i),
        .wb_sel_i(uart_sel),
        .wb_we_i(uart_we),
        .wb_cyc_i(uart_cyc),
        .wb_stb_i(uart_stb),
        .wb_ack_o(uart_ack),
        .wb_err_o(uart_err),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o),
        .irq_o(uart_irq)
    );

    kyber_wb_slave #(
        .DATA_BYTES(KYBER_DATA_BYTES)
    ) u_kyber (
        .wb_clk_i(clk_i),
        .wb_rst_i(rst_i),
        .wb_adr_i(kyber_adr),
        .wb_dat_i(kyber_dat_o),
        .wb_dat_o(kyber_dat_i),
        .wb_sel_i(kyber_sel),
        .wb_we_i(kyber_we),
        .wb_cyc_i(kyber_cyc),
        .wb_stb_i(kyber_stb),
        .wb_ack_o(kyber_ack),
        .wb_err_o(kyber_err),
        .irq_o(kyber_irq)
    );
endmodule
