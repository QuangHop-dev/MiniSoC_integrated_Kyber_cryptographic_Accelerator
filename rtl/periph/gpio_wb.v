`timescale 1ns/1ps

// GPIO Wishbone slave used by the Kyber-512 SoC register map.
module gpio_wb #(
    parameter integer WIDTH = 8
)(
    input  wire             wb_clk_i,
    input  wire             wb_rst_i,
    input  wire [31:0]      wb_adr_i,
    input  wire [31:0]      wb_dat_i,
    output reg  [31:0]      wb_dat_o,
    input  wire [3:0]       wb_sel_i,
    input  wire             wb_we_i,
    input  wire             wb_cyc_i,
    input  wire             wb_stb_i,
    output reg              wb_ack_o,
    output reg              wb_err_o,

    input  wire [WIDTH-1:0] gpio_i,
    output wire [WIDTH-1:0] gpio_o,
    output wire [WIDTH-1:0] gpio_oe,
    output wire             irq_o
);
    localparam [7:0] REG_IO_DIR      = 8'h00;
    localparam [7:0] REG_IO_VAL      = 8'h04;
    localparam [7:0] REG_INT_ENABLE  = 8'h08;
    localparam [7:0] REG_INT_TYPE    = 8'h0C;
    localparam [7:0] REG_INT_METHOD  = 8'h10;
    localparam [7:0] REG_INT_STATUS  = 8'h14;
    localparam [7:0] REG_GPIO_SET    = 8'h1C;
    localparam [7:0] REG_GPIO_CLEAR  = 8'h20;

    reg [WIDTH-1:0] io_dir;
    reg [WIDTH-1:0] io_val;
    reg [WIDTH-1:0] int_enable;
    reg [WIDTH-1:0] int_type;
    reg [WIDTH-1:0] int_method;
    reg [WIDTH-1:0] int_status;
    reg [WIDTH-1:0] sync_gpio_1;
    reg [WIDTH-1:0] sync_gpio_2;
    reg [WIDTH-1:0] sync_gpio_d;

    wire [WIDTH-1:0] gpio_sample = sync_gpio_2;
    wire [WIDTH-1:0] level_event = ( int_method &  gpio_sample) |
                                   (~int_method & ~gpio_sample);
    wire [WIDTH-1:0] edge_event  = ( int_method &  gpio_sample & ~sync_gpio_d) |
                                   (~int_method & ~gpio_sample &  sync_gpio_d);
    wire [WIDTH-1:0] irq_event   = (int_type & edge_event) |
                                   (~int_type & level_event);

    assign gpio_o  = io_val;
    assign gpio_oe = io_dir;
    assign irq_o   = |(int_status & int_enable);

    function [WIDTH-1:0] apply_wstrb;
        input [WIDTH-1:0] oldv;
        input [31:0]      newv;
        input [3:0]       sel;
        integer i;
        begin
            apply_wstrb = oldv;
            for (i = 0; i < WIDTH; i = i + 1) begin
                if (sel[i/8]) apply_wstrb[i] = newv[i];
            end
        end
    endfunction

    function [31:0] zext_gpio;
        input [WIDTH-1:0] v;
        integer i;
        begin
            zext_gpio = 32'd0;
            for (i = 0; i < WIDTH; i = i + 1)
                zext_gpio[i] = v[i];
        end
    endfunction

    function valid_addr;
        input [7:0] addr;
        begin
            case (addr)
                REG_IO_DIR, REG_IO_VAL, REG_INT_ENABLE, REG_INT_TYPE,
                REG_INT_METHOD, REG_INT_STATUS, REG_GPIO_SET, REG_GPIO_CLEAR:
                    valid_addr = 1'b1;
                default:
                    valid_addr = 1'b0;
            endcase
        end
    endfunction

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o    <= 1'b0;
            wb_err_o    <= 1'b0;
            wb_dat_o    <= 32'd0;
            io_dir      <= {WIDTH{1'b0}};
            io_val      <= {WIDTH{1'b0}};
            int_enable  <= {WIDTH{1'b0}};
            int_type    <= {WIDTH{1'b0}};
            int_method  <= {WIDTH{1'b0}};
            int_status  <= {WIDTH{1'b0}};
            sync_gpio_1 <= {WIDTH{1'b0}};
            sync_gpio_2 <= {WIDTH{1'b0}};
            sync_gpio_d <= {WIDTH{1'b0}};
        end else begin
            wb_ack_o    <= 1'b0;
            wb_err_o    <= 1'b0;
            sync_gpio_1 <= gpio_i;
            sync_gpio_2 <= sync_gpio_1;
            sync_gpio_d <= sync_gpio_2;

            int_status <= int_status | irq_event;

            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                wb_ack_o <= 1'b1;
                wb_err_o <= !valid_addr(wb_adr_i[7:0]);

                if (wb_we_i) begin
                    case (wb_adr_i[7:0])
                        REG_IO_DIR:     io_dir     <= apply_wstrb(io_dir,     wb_dat_i, wb_sel_i);
                        REG_IO_VAL:     io_val     <= apply_wstrb(io_val,     wb_dat_i, wb_sel_i);
                        REG_INT_ENABLE: int_enable <= apply_wstrb(int_enable, wb_dat_i, wb_sel_i);
                        REG_INT_TYPE:   int_type   <= apply_wstrb(int_type,   wb_dat_i, wb_sel_i);
                        REG_INT_METHOD: int_method <= apply_wstrb(int_method, wb_dat_i, wb_sel_i);
                        REG_INT_STATUS: int_status <= (int_status | irq_event) &
                                                      ~apply_wstrb({WIDTH{1'b0}}, wb_dat_i, wb_sel_i);
                        REG_GPIO_SET:   io_val     <= io_val | wb_dat_i[WIDTH-1:0];
                        REG_GPIO_CLEAR: io_val     <= io_val & ~wb_dat_i[WIDTH-1:0];
                        default: ;
                    endcase
                end else begin
                    case (wb_adr_i[7:0])
                        REG_IO_DIR:     wb_dat_o <= zext_gpio(io_dir);
                        REG_IO_VAL:     wb_dat_o <= zext_gpio((io_dir & io_val) | (~io_dir & gpio_sample));
                        REG_INT_ENABLE: wb_dat_o <= zext_gpio(int_enable);
                        REG_INT_TYPE:   wb_dat_o <= zext_gpio(int_type);
                        REG_INT_METHOD: wb_dat_o <= zext_gpio(int_method);
                        REG_INT_STATUS: wb_dat_o <= zext_gpio(int_status);
                        default:        wb_dat_o <= 32'd0;
                    endcase
                end
            end
        end
    end
endmodule
