`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// kyber_dual_port_ram
// Kyber512 RTL source. Comments and unused debug-only code were removed for a
// synthesis-oriented release build.
// -----------------------------------------------------------------------------

module kyber_dual_port_ram (
    input  wire clk,
    
    input  wire we_a,               
    input  wire [7:0] addr_a,       
    input  wire signed [15:0] din_a,
    output reg  signed [15:0] dout_a,
    
    
    input  wire we_b,               
    input  wire [7:0] addr_b,       
    input  wire signed [15:0] din_b,
    output reg  signed [15:0] dout_b
);

    
    reg signed [15:0] ram [0:255];

    
    always @(posedge clk) begin
        if (we_a) begin
            ram[addr_a] <= din_a;
        end
        dout_a <= ram[addr_a]; 
    end

    
    always @(posedge clk) begin
        if (we_b) begin
            ram[addr_b] <= din_b;
        end
        dout_b <= ram[addr_b];
    end

endmodule