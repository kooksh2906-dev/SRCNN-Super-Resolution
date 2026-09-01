`timescale 1ns / 1ps

// B-part arithmetic contract:
//   activation/weight : signed INT16
//   product           : signed INT32
//   bias              : signed INT32, sign-extended to INT48
//   accumulator       : signed INT48

// --------------------------------------------------------------------------
// One signed 16x16 multiplier and 48-bit accumulator
// --------------------------------------------------------------------------
module mac16x16_acc48 (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    acc_clear,
    input  wire                    bias_load,
    input  wire                    mac_valid,

    input  wire signed [15:0]      activation,
    input  wire signed [15:0]      weight,
    input  wire signed [31:0]      bias,

    output wire signed [47:0]      accumulator
);

    reg  signed [47:0] acc_reg;

    wire signed [31:0] product;
    wire signed [47:0] product_ext;
    wire signed [47:0] bias_ext;


    // INT16 × INT16 = INT32
    assign product = activation * weight;


    // INT32 Product → INT48 Sign Extension
    assign product_ext = {{16{product[31]}}, product};


    // INT32 Bias → INT48 Sign Extension
    assign bias_ext = {{16{bias[31]}}, bias};


    // Accumulator output
    assign accumulator = acc_reg;


    // 48-bit synchronous accumulator
    always @(posedge clk) begin

        if (!rst_n)
            acc_reg <= 48'sd0;

        else if (bias_load)
            acc_reg <= bias_ext;

        else if (acc_clear)
            acc_reg <= 48'sd0;

        else if (mac_valid)
            acc_reg <= acc_reg + product_ext;

    end

endmodule
