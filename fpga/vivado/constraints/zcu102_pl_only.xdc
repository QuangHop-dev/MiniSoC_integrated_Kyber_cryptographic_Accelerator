# ZCU102 PL-only constraints for Kyber RISC-V SoC wrapper.
# Top module: zcu102_soc_wrapper
#
# External board clock is 125 MHz differential.
# The SoC clock is generated internally by MMCME4_BASE and is automatically
# derived by Vivado from ref_clk_125m. Supported profiles are 100, 125, 150,
# 166.667, 180, 190, and 200 MHz.

###############################################################################
# 125 MHz differential reference clock
###############################################################################

create_clock -name ref_clk_125m -period 8.000 [get_ports ref_clk_p]

set_property PACKAGE_PIN G21 [get_ports ref_clk_p]
set_property IOSTANDARD LVDS_25 [get_ports ref_clk_p]

set_property PACKAGE_PIN F21 [get_ports ref_clk_n]
set_property IOSTANDARD LVDS_25 [get_ports ref_clk_n]

###############################################################################
# Reset button: CPU_RESET, active high
###############################################################################

set_property PACKAGE_PIN AM13 [get_ports cpu_reset]
set_property IOSTANDARD LVCMOS33 [get_ports cpu_reset]
set_property PULLDOWN true [get_ports cpu_reset]

###############################################################################
# PL UART through ZCU102 USB-UART bridge
###############################################################################

set_property PACKAGE_PIN E13 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

set_property PACKAGE_PIN F13 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

###############################################################################
# User LEDs: active high
###############################################################################

set_property PACKAGE_PIN AG14 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]

set_property PACKAGE_PIN AF13 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

set_property PACKAGE_PIN AE13 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]

set_property PACKAGE_PIN AJ14 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

set_property PACKAGE_PIN AJ15 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[4]}]

set_property PACKAGE_PIN AH13 [get_ports {led[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[5]}]

set_property PACKAGE_PIN AH14 [get_ports {led[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[6]}]

set_property PACKAGE_PIN AL12 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[7]}]

###############################################################################
# GPIO inputs: SW13 DIP switches and directional pushbuttons
###############################################################################

set_property PACKAGE_PIN AN14 [get_ports {dip_sw[0]}]
set_property PACKAGE_PIN AP14 [get_ports {dip_sw[1]}]
set_property PACKAGE_PIN AM14 [get_ports {dip_sw[2]}]
set_property PACKAGE_PIN AN13 [get_ports {dip_sw[3]}]
set_property PACKAGE_PIN AN12 [get_ports {dip_sw[4]}]
set_property PACKAGE_PIN AP12 [get_ports {dip_sw[5]}]
set_property PACKAGE_PIN AL13 [get_ports {dip_sw[6]}]
set_property PACKAGE_PIN AK13 [get_ports {dip_sw[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dip_sw[*]}]

set_property PACKAGE_PIN AG15 [get_ports {pushbutton[0]}]
set_property PACKAGE_PIN AE14 [get_ports {pushbutton[1]}]
set_property PACKAGE_PIN AF15 [get_ports {pushbutton[2]}]
set_property PACKAGE_PIN AE15 [get_ports {pushbutton[3]}]
set_property PACKAGE_PIN AG13 [get_ports {pushbutton[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pushbutton[*]}]

###############################################################################
# External LCD I2C on PMOD0 J55: pin 1=SCL, pin 3=SDA
###############################################################################

set_property PACKAGE_PIN A20 [get_ports i2c_scl]
set_property IOSTANDARD LVCMOS33 [get_ports i2c_scl]
set_property PULLUP true [get_ports i2c_scl]

set_property PACKAGE_PIN B20 [get_ports i2c_sda]
set_property IOSTANDARD LVCMOS33 [get_ports i2c_sda]
set_property PULLUP true [get_ports i2c_sda]
