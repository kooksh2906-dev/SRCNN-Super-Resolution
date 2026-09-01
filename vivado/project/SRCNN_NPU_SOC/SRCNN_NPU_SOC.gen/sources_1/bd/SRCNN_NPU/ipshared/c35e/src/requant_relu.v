`timescale 1ns / 1ps

module requant_relu (
    input  wire clk,
    input  wire rst_n,

    input  wire signed [47:0] acc_i,
    input  wire        [5:0]  shift_i,

    // 4단 Pipeline을 거친 Requant·ReLU·INT16 결과
    output reg  signed [15:0] data_o
);

    // Stage 1: 양수 누산값, 반올림 Offset, Shift 크기 저장
    reg [47:0] positive_acc_stage1_reg;
    reg [47:0] rounding_offset_stage1_reg;
    reg [5:0]  shift_stage1_reg;

    // Stage 2: 반올림 Offset을 더한 결과 저장
    reg [47:0] rounded_sum_stage2_reg;
    reg [5:0]  shift_stage2_reg;

    // Stage 3: Right Shift 결과 저장
    reg [47:0] shifted_stage3_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            positive_acc_stage1_reg      <= 48'd0;
            rounding_offset_stage1_reg   <= 48'd0;
            shift_stage1_reg             <= 6'd0;

            rounded_sum_stage2_reg       <= 48'd0;
            shift_stage2_reg             <= 6'd0;

            shifted_stage3_reg           <= 48'd0;

            data_o                       <= 16'sd0;
        end
        else begin
            // Stage 1:
            // 음수 누산값은 ReLU 결과가 항상 0이므로 바로 0으로 변환
            if (acc_i[47]) begin
                positive_acc_stage1_reg    <= 48'd0;
                rounding_offset_stage1_reg <= 48'd0;
            end
            else begin
                positive_acc_stage1_reg <= acc_i;

                // Shift 전 2^(shift-1)을 더해 가장 가까운 정수로 반올림
                if (shift_i == 6'd0)
                    rounding_offset_stage1_reg <= 48'd0;
                else
                    rounding_offset_stage1_reg
                        <= 48'd1 << (shift_i - 6'd1);
            end

            shift_stage1_reg <= shift_i;

            // Stage 2:
            // 48-bit 덧셈만 수행해 긴 Carry Chain을 독립 단계로 분리
            rounded_sum_stage2_reg
                <= positive_acc_stage1_reg
                 + rounding_offset_stage1_reg;

            shift_stage2_reg <= shift_stage1_reg;

            // Stage 3:
            // 가변 Right Shift를 별도 Pipeline 단계에서 수행
            if (shift_stage2_reg == 6'd0)
                shifted_stage3_reg <= rounded_sum_stage2_reg;
            else
                shifted_stage3_reg
                    <= rounded_sum_stage2_reg >> shift_stage2_reg;

            // Stage 4:
            // 상위 비트가 하나라도 1이면 INT16 양수 최대값으로 Saturation
            if (|shifted_stage3_reg[47:15])
                data_o <= 16'sd32767;
            else
                data_o <= $signed(shifted_stage3_reg[15:0]);
        end
    end

endmodule
