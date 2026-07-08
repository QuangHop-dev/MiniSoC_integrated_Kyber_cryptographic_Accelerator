`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// keccak_round_function
// Kyber512 RTL source. Comments and unused debug-only code were removed for a
// synthesis-oriented release build.
// -----------------------------------------------------------------------------

module keccak_round_function(
    input wire [1599:0] in_state,
    input wire [63:0] rc,
    output wire [1599:0] out_state
);
    wire [63:0] state [0:4][0:4];
    genvar x, y;
    generate
        for (x = 0; x < 5; x = x + 1) begin : state_gen
            for (y = 0; y < 5; y = y + 1) begin : state_row_gen
                assign state[x][y] = in_state[(x + 5*y) * 64 +: 64];
            end
        end
    endgenerate

    
    wire [63:0] c [0:4];
    wire [63:0] d [0:4];
    wire [63:0] theta_state [0:4][0:4];
    generate 
        for (x = 0; x < 5; x = x + 1) begin: theta_c 
            assign c[x] = state[x][0] ^ state[x][1] ^ state[x][2] ^ state[x][3] ^ state[x][4];
        end
        for (x = 0; x < 5; x = x + 1) begin: theta_d 
            assign d[x] = c[(x+4)%5] ^ {c[(x+1)%5][62:0], c[(x+1)%5][63]};
        end
        for (y = 0; y < 5; y = y + 1) begin: theta_out_y
            for (x = 0; x < 5; x = x + 1) begin: theta_out_x
                assign theta_state[x][y] = d[x] ^ state[x][y];
            end
        end
    endgenerate

    
    wire [63:0] rho_pi_state [0:4][0:4];

    assign rho_pi_state[0][0] = theta_state[0][0];
    assign rho_pi_state[0][2] = {theta_state[1][0][62:0], theta_state[1][0][63:63]};
    assign rho_pi_state[0][4] = {theta_state[2][0][1:0], theta_state[2][0][63:2]};
    assign rho_pi_state[0][1] = {theta_state[3][0][35:0], theta_state[3][0][63:36]};
    assign rho_pi_state[0][3] = {theta_state[4][0][36:0], theta_state[4][0][63:37]};
    assign rho_pi_state[1][3] = {theta_state[0][1][27:0], theta_state[0][1][63:28]};
    assign rho_pi_state[1][0] = {theta_state[1][1][19:0], theta_state[1][1][63:20]};
    assign rho_pi_state[1][2] = {theta_state[2][1][57:0], theta_state[2][1][63:58]};
    assign rho_pi_state[1][4] = {theta_state[3][1][8:0], theta_state[3][1][63:9]};
    assign rho_pi_state[1][1] = {theta_state[4][1][43:0], theta_state[4][1][63:44]};
    assign rho_pi_state[2][1] = {theta_state[0][2][60:0], theta_state[0][2][63:61]};
    assign rho_pi_state[2][3] = {theta_state[1][2][53:0], theta_state[1][2][63:54]};
    assign rho_pi_state[2][0] = {theta_state[2][2][20:0], theta_state[2][2][63:21]};
    assign rho_pi_state[2][2] = {theta_state[3][2][38:0], theta_state[3][2][63:39]};
    assign rho_pi_state[2][4] = {theta_state[4][2][24:0], theta_state[4][2][63:25]};
    assign rho_pi_state[3][4] = {theta_state[0][3][22:0], theta_state[0][3][63:23]};
    assign rho_pi_state[3][1] = {theta_state[1][3][18:0], theta_state[1][3][63:19]};
    assign rho_pi_state[3][3] = {theta_state[2][3][48:0], theta_state[2][3][63:49]};
    assign rho_pi_state[3][0] = {theta_state[3][3][42:0], theta_state[3][3][63:43]};
    assign rho_pi_state[3][2] = {theta_state[4][3][55:0], theta_state[4][3][63:56]};
    assign rho_pi_state[4][2] = {theta_state[0][4][45:0], theta_state[0][4][63:46]};
    assign rho_pi_state[4][4] = {theta_state[1][4][61:0], theta_state[1][4][63:62]};
    assign rho_pi_state[4][1] = {theta_state[2][4][2:0], theta_state[2][4][63:3]};
    assign rho_pi_state[4][3] = {theta_state[3][4][7:0], theta_state[3][4][63:8]};
    assign rho_pi_state[4][0] = {theta_state[4][4][49:0], theta_state[4][4][63:50]};

    
    wire [63:0] chi_state [0:4][0:4];
    generate 
        for (y = 0; y < 5; y = y + 1) begin: chi_y
            for (x = 0; x < 5; x = x + 1) begin: chi_x
                assign chi_state[x][y] = rho_pi_state[x][y] ^ ((~rho_pi_state[(x+1)%5][y]) & rho_pi_state[(x+2)%5][y]);
            end
        end
    endgenerate

    
    wire [63:0] iota_state [0:4][0:4];
    generate
        for (y = 0; y < 5; y = y + 1) begin: iota_y
            for (x = 0; x < 5; x = x + 1) begin: iota_x
                if (x == 0 && y == 0) begin
                    assign iota_state[x][y] = chi_state[x][y] ^ rc;
                end
                else begin
                    assign iota_state[x][y] = chi_state[x][y];
                end
            end
        end
    endgenerate

    
    generate
        for (y = 0; y < 5; y = y + 1) begin: out_y
            for (x = 0; x < 5; x = x + 1) begin: out_x
                assign out_state[(x + 5*y) * 64 +: 64] = iota_state[x][y];
            end
        end
    endgenerate
endmodule