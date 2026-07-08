`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// kyber_ct_compare
// Streaming 64-bit ciphertext comparator.
//
// The FSM reads original ciphertext words and presents them here alongside
// freshly packed re-encryption words.  The compare result is accumulated until
// finish is pulsed.
// -----------------------------------------------------------------------------

module kyber_ct_compare (
    input  wire clk,
    input  wire rst,
    input  wire start,

    input  wire        word_valid,
    input  wire [63:0] data_c,
    input  wire [63:0] data_c_prime,
    input  wire        finish,

    output reg  not_equal,
    output reg  done
);

    reg        diff_accumulator;
    wire       current_diff = word_valid && (data_c != data_c_prime);

    always @(posedge clk) begin
        if (rst) begin
            diff_accumulator <= 1'b0;
            not_equal <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start) begin
                diff_accumulator <= 1'b0;
                not_equal <= 1'b0;
            end else begin
                if (current_diff)
                    diff_accumulator <= 1'b1;

                if (finish) begin
                    not_equal <= diff_accumulator | current_diff;
                    done <= 1'b1;
                end
            end
        end
    end

endmodule
