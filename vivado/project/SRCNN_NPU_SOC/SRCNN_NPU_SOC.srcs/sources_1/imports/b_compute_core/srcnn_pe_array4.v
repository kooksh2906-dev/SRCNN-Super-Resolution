`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// srcnn_pe_array4.v
//
// SRCNN 4-PE Parallel Array
//
// 역할
//   1. 하나의 Activation을 4개의 PE에 Broadcast
//   2. 각 PE에 서로 다른 Weight / Bias 공급
//   3. 4개의 Output Channel을 병렬 계산
//   4. pe_enable[3:0]을 이용한 PE Mask
//   5. 각 PE의 signed INT48 accumulator 출력
//   6. PE들의 busy / result_valid를 Array 단위 신호로 통합
//
// 구조
//
//                    activation
//                        │
//          ┌─────────────┼─────────────┐
//          │             │             │
//          ▼             ▼             ▼             ▼
//        PE0           PE1           PE2           PE3
//        W0            W1            W2            W3
//        B0            B1            B2            B3
//          │             │             │             │
//          ▼             ▼             ▼             ▼
//        ACC0          ACC1          ACC2          ACC3
//
// Conv1 / Conv2:
//   pe_enable = 4'b1111
//
// Conv3:
//   pe_enable = 4'b0001
//
// Arithmetic per PE:
//   Activation : signed INT16
//   Weight     : signed INT16
//   Bias       : signed INT32
//   Accumulator: signed INT48
// -----------------------------------------------------------------------------

module srcnn_pe_array4 (

    input  wire                     clk,
    input  wire                     rst_n,

    // -------------------------------------------------------------------------
    // Array Control
    // -------------------------------------------------------------------------
    input  wire                     op_start,
    input  wire                     bias_load,
    input  wire                     mac_valid,
    input  wire                     mac_last,

    // PE Mask
    input  wire [3:0]               pe_enable,

    // -------------------------------------------------------------------------
    // Shared Activation
    // -------------------------------------------------------------------------
    input  wire signed [15:0]       activation,

    // -------------------------------------------------------------------------
    // PE Weight
    // -------------------------------------------------------------------------
    input  wire signed [15:0]       weight0,
    input  wire signed [15:0]       weight1,
    input  wire signed [15:0]       weight2,
    input  wire signed [15:0]       weight3,

    // -------------------------------------------------------------------------
    // PE Bias
    // -------------------------------------------------------------------------
    input  wire signed [31:0]       bias0,
    input  wire signed [31:0]       bias1,
    input  wire signed [31:0]       bias2,
    input  wire signed [31:0]       bias3,

    // -------------------------------------------------------------------------
    // INT48 Accumulator Output
    // -------------------------------------------------------------------------
    output wire signed [47:0]       accumulator0,
    output wire signed [47:0]       accumulator1,
    output wire signed [47:0]       accumulator2,
    output wire signed [47:0]       accumulator3,

    // -------------------------------------------------------------------------
    // Array Status
    // -------------------------------------------------------------------------
    output wire                     busy,
    output wire                     result_valid

);
    // =========================================================================
    // Individual PE Status
    // =========================================================================

    wire busy0;
    wire busy1;
    wire busy2;
    wire busy3;

    wire result_valid0;
    wire result_valid1;
    wire result_valid2;
    wire result_valid3;


    // =========================================================================
    // PE0
    // =========================================================================

    srcnn_pe u_pe0 (

        .clk            (clk),
        .rst_n          (rst_n),

        .pe_enable      (pe_enable[0]),

        .op_start       (op_start),
        .bias_load      (bias_load),

        .mac_valid      (mac_valid),
        .mac_last       (mac_last),

        .activation     (activation),
        .weight         (weight0),
        .bias           (bias0),

        .accumulator    (accumulator0),

        .busy           (busy0),
        .result_valid   (result_valid0)

    );
    // =========================================================================
    // PE1
    // =========================================================================
    srcnn_pe u_pe1 (

        .clk            (clk),
        .rst_n          (rst_n),

        .pe_enable      (pe_enable[1]),

        .op_start       (op_start),
        .bias_load      (bias_load),

        .mac_valid      (mac_valid),
        .mac_last       (mac_last),

        .activation     (activation),
        .weight         (weight1),
        .bias           (bias1),

        .accumulator    (accumulator1),

        .busy           (busy1),
        .result_valid   (result_valid1)

    );
    // =========================================================================
    // PE2
    // =========================================================================
    srcnn_pe u_pe2 (

        .clk            (clk),
        .rst_n          (rst_n),

        .pe_enable      (pe_enable[2]),

        .op_start       (op_start),
        .bias_load      (bias_load),

        .mac_valid      (mac_valid),
        .mac_last       (mac_last),

        .activation     (activation),
        .weight         (weight2),
        .bias           (bias2),

        .accumulator    (accumulator2),

        .busy           (busy2),
        .result_valid   (result_valid2)

    );
    // =========================================================================
    // PE3
    // =========================================================================
    srcnn_pe u_pe3 (

        .clk            (clk),
        .rst_n          (rst_n),

        .pe_enable      (pe_enable[3]),

        .op_start       (op_start),
        .bias_load      (bias_load),

        .mac_valid      (mac_valid),
        .mac_last       (mac_last),

        .activation     (activation),
        .weight         (weight3),
        .bias           (bias3),

        .accumulator    (accumulator3),

        .busy           (busy3),
        .result_valid   (result_valid3)

    );
    // =========================================================================
    // Array Busy
    //
    // 활성 PE 중 하나라도 계산 중이면 Array 전체를 Busy로 본다.
    // =========================================================================

    assign busy = (busy0 & pe_enable[0]) | (busy1 & pe_enable[1]) | (busy2 & pe_enable[2]) | (busy3 & pe_enable[3]);

    // =========================================================================
    // Array Result Valid
    //
    // 활성화된 PE의 마지막 MAC이 완료되면
    // Array 결과가 유효하다고 판단한다.
    //
    // 모든 활성 PE는 동일한 op_start / mac_valid / mac_last를
    // 공유하므로 정상 동작에서는 같은 Clock에 완료된다.
    // =========================================================================

    assign result_valid = (result_valid0 & pe_enable[0]) | (result_valid1 & pe_enable[1]) | (result_valid2 & pe_enable[2]) | (result_valid3 & pe_enable[3]);

endmodule
