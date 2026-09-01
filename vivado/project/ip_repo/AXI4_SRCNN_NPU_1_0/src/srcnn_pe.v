`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// srcnn_pe.v
//
// SRCNN Processing Element (PE)
//
// 역할
//   1. op_start 시 accumulator clear
//   2. bias_load 시 Bias를 INT48 accumulator에 load
//   3. mac_valid 시 Activation x Weight 누산
//   4. mac_last가 들어온 마지막 MAC에서 result_valid 발생
//   5. pe_enable로 PE 활성/비활성 제어
//
// Arithmetic:
//   Activation : signed INT16
//   Weight     : signed INT16
//   Bias       : signed INT32
//   Accumulator: signed INT48
//
// 내부 MAC:
//   mac16x16_acc48
//
// 정상 제어 순서:
//   op_start
//      ↓
//   bias_load
//      ↓
//   mac_valid × N
//      ↓
//   mac_valid + mac_last
//      ↓
//   result_valid
//
// 주의:
//   op_start와 bias_load는 같은 cycle에 assert하지 않는다.
//   bias_load와 mac_valid도 같은 cycle에 assert하지 않는다.
// -----------------------------------------------------------------------------

module srcnn_pe (
    input  wire                     clk,
    input  wire                     rst_n,
    // -------------------------------------------------------------------------
    // PE Control
    // -------------------------------------------------------------------------
    input  wire                     pe_enable,
    input  wire                     op_start,
    input  wire                     bias_load,
    input  wire                     mac_valid,
    input  wire                     mac_last,
    // -------------------------------------------------------------------------
    // Arithmetic Input
    // -------------------------------------------------------------------------
    input  wire signed [15:0]        activation,
    input  wire signed [15:0]        weight,
    input  wire signed [31:0]        bias,
    // -------------------------------------------------------------------------
    // PE Output
    // -------------------------------------------------------------------------
    output wire signed [47:0]        accumulator,
    output reg                      busy,
    output reg                      result_valid
);
    // =========================================================================
    // Internal control signals
    //
    // PE가 disable되어 있으면 MAC 내부로 제어 신호를 전달하지 않는다.
    // =========================================================================
    wire acc_clear_int;
    wire bias_load_int;
    wire mac_valid_int;

    assign acc_clear_int = op_start  & pe_enable;
    assign bias_load_int = bias_load & pe_enable;
    assign mac_valid_int = mac_valid & pe_enable;
    // =========================================================================
    // MAC Unit
    //
    // signed INT16 x INT16
    //          ↓
    // signed INT32 Product
    //          ↓
    // signed INT48 Accumulator
    // =========================================================================
    mac16x16_acc48 u_mac16x16_acc48 (
        .clk            (clk),
        .rst_n          (rst_n),
        .acc_clear      (acc_clear_int),
        .bias_load      (bias_load_int),
        .mac_valid      (mac_valid_int),
        .activation     (activation),
        .weight         (weight),
        .bias           (bias),
        .accumulator    (accumulator)
    );
    // =========================================================================
    // PE Control
    //
    // busy
    //   op_start 시 1
    //   마지막 MAC 완료 시 0
    //
    // result_valid
    //   마지막 MAC이 수행된 cycle에서 1-cycle pulse
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            busy         <= 1'b0;
            result_valid <= 1'b0;
        end
        else begin
            // 기본값:
            // result_valid는 1 clock pulse
            result_valid <= 1'b0;
            // -------------------------------------------------------------
            // Start new PE operation
            // -------------------------------------------------------------
            if (op_start) begin
                if (pe_enable)
                    busy <= 1'b1;
                else
                    busy <= 1'b0;
            end
            // -------------------------------------------------------------
            // Last MAC
            //
            // 현재 clock edge에서 마지막 Product가 accumulator에
            // 더해지고 동시에 result_valid가 발생한다.
            // -------------------------------------------------------------
            else if (pe_enable && mac_valid && mac_last) begin
                busy         <= 1'b0;
                result_valid <= 1'b1;
            end
        end
    end
endmodule
