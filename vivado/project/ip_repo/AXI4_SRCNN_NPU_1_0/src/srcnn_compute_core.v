`timescale 1ns / 1ps

// =============================================================================
// srcnn_compute_core.v
//
// SRCNN B-Part Compute Core
//
// 역할
// -----------------------------------------------------------------------------
// 1. A Part로부터 Activation / Weight / Bias / Control 신호 수신
// 2. 내부 srcnn_pe_array4를 이용하여 4개의 Output Channel 병렬 MAC 수행
// 3. Bias가 포함된 signed INT48 accumulator 4개 출력
// 4. busy / acc_valid / core_done 상태 신호 출력
//
// 계층 구조
//
// srcnn_compute_core
//        |
//        +-- srcnn_pe_array4
//                |
//                +-- srcnn_pe PE0
//                |      |
//                |      +-- mac16x16_acc48
//                |
//                +-- srcnn_pe PE1
//                |      |
//                |      +-- mac16x16_acc48
//                |
//                +-- srcnn_pe PE2
//                |      |
//                |      +-- mac16x16_acc48
//                |
//                +-- srcnn_pe PE3
//                       |
//                       +-- mac16x16_acc48
//
// Arithmetic
// -----------------------------------------------------------------------------
// Activation  : signed INT16
// Weight      : signed INT16
// Product     : signed INT32
// Bias        : signed INT32
// Accumulator : signed INT48
//
// ACC = sign_extend(Bias)
// ACC = ACC + sign_extend(Activation * Weight)
//
// Conv1 / Conv2
// -----------------------------------------------------------------------------
// pe_enable = 4'b1111
// → PE0~PE3 모두 사용
//
// Conv3
// -----------------------------------------------------------------------------
// pe_enable = 4'b0001
// → PE0만 사용
//
// IMPORTANT
// -----------------------------------------------------------------------------
// 이 모듈에서는 Requantization, ReLU, Saturation, Clamp를 수행하지 않는다.
// B-Part의 최종 결과는 Bias가 포함된 signed INT48 accumulator이다.
// =============================================================================

module srcnn_compute_core (

    // =========================================================================
    // Clock / Reset
    // =========================================================================

    input  wire                     clk,
    input  wire                     rst_n,


    // =========================================================================
    // Control Input
    // =========================================================================

    // 새로운 Output 연산 시작
    input  wire                     op_start,

    // Bias를 각 PE accumulator의 시작값으로 Load
    input  wire                     bias_load,

    // 현재 Activation × Weight를 누산
    input  wire                     mac_valid,

    // 현재 MAC이 마지막 MAC임을 표시
    input  wire                     mac_last,

    // PE Mask
    //
    // 1111 : PE0~PE3 활성
    // 0001 : PE0만 활성
    input  wire [3:0]               pe_enable,


    // =========================================================================
    // Shared Activation
    // =========================================================================

    // 4개의 PE에 동일한 Activation Broadcast
    input  wire signed [15:0]       activation,


    // =========================================================================
    // PE Weight Input
    // =========================================================================

    input  wire signed [15:0]       weight0,
    input  wire signed [15:0]       weight1,
    input  wire signed [15:0]       weight2,
    input  wire signed [15:0]       weight3,


    // =========================================================================
    // PE Bias Input
    // =========================================================================

    input  wire signed [31:0]       bias0,
    input  wire signed [31:0]       bias1,
    input  wire signed [31:0]       bias2,
    input  wire signed [31:0]       bias3,


    // =========================================================================
    // INT48 Accumulator Output
    // =========================================================================

    output wire signed [47:0]       accumulator0,
    output wire signed [47:0]       accumulator1,
    output wire signed [47:0]       accumulator2,
    output wire signed [47:0]       accumulator3,


    // =========================================================================
    // Status Output
    // =========================================================================

    // 활성 PE 중 하나라도 계산 중이면 1
    output wire                     busy,

    // 최종 accumulator 결과가 유효한 Clock에서 1
    output wire                     acc_valid,

    // 현재 Output 연산이 완료되었음을 알리는 1-Clock Pulse
    output wire                     core_done

);

    // =========================================================================
    // Internal Signals
    // =========================================================================

    wire array_busy;
    wire array_result_valid;

    // =========================================================================
    // 4-PE Array
    // =========================================================================

    srcnn_pe_array4 u_srcnn_pe_array4 (

        // Clock / Reset
        .clk            (clk),
        .rst_n          (rst_n),

        // Control
        .op_start       (op_start),
        .bias_load      (bias_load),
        .mac_valid      (mac_valid),
        .mac_last       (mac_last),

        // PE Mask
        .pe_enable      (pe_enable),

        // Shared Activation
        .activation     (activation),

        // Weight
        .weight0        (weight0),
        .weight1        (weight1),
        .weight2        (weight2),
        .weight3        (weight3),

        // Bias
        .bias0          (bias0),
        .bias1          (bias1),
        .bias2          (bias2),
        .bias3          (bias3),

        // INT48 Accumulator
        .accumulator0   (accumulator0),
        .accumulator1   (accumulator1),
        .accumulator2   (accumulator2),
        .accumulator3   (accumulator3),

        // Status
        .busy           (array_busy),
        .result_valid   (array_result_valid)

    );
    // =========================================================================
    // Core Status Output
    // =========================================================================

    // PE Array가 계산 중이면 Compute Core도 Busy
    assign busy = array_busy;

    // -------------------------------------------------------------------------
    // acc_valid
    //
    // 마지막 MAC이 완료되고 accumulator0~3가 최종값을 가지고 있는 Clock에서
    // 1이 된다.
    //
    // srcnn_pe_array4의 result_valid를 그대로 사용한다.
    // -------------------------------------------------------------------------

    assign acc_valid = array_result_valid;

    // -------------------------------------------------------------------------
    // core_done
    //
    // 현재 Output 연산이 완료되었음을 상위 Controller(A Part)에 알린다.
    //
    // 현재 인터페이스에서는 최종 accumulator가 완성되는 시점과
    // Core 연산 완료 시점이 같으므로 acc_valid와 동일한 1-Clock Pulse로 정의한다.
    //
    // 따라서:
    //
    // mac_valid = 1
    // mac_last  = 1
    //       ↓ posedge clk
    //
    // final accumulator update
    // acc_valid = 1
    // core_done = 1
    // busy      = 0
    //
    // 다음 Clock:
    //
    // acc_valid = 0
    // core_done = 0
    // -------------------------------------------------------------------------

    assign core_done = array_result_valid;
    
endmodule
