`timescale 1ns / 1ps

module requant_round_shift (
    input  wire signed [47:0] acc_i,
    input  wire        [5:0]  shift_i,
    output reg  signed [47:0] rounded_o
);

    // acc_i의 부호를 제거한 절댓값
    reg [47:0] magnitude;

    // 반올림을 위해 더할 값: 2^(shift_i - 1)
    reg [47:0] rounding_offset;

    // 반올림 값을 더한 후 오른쪽 Shift한 절댓값
    reg [47:0] rounded_magnitude;

    // 순수 조합논리
    always @(*) begin
        // Latch 발생을 방지하기 위한 기본값
        magnitude         = 48'd0;
        rounding_offset   = 48'd0;
        rounded_magnitude = 48'd0;
        rounded_o         = 48'sd0;

        // Shift가 0이면 입력값을 그대로 출력
        if (shift_i == 6'd0) begin
            rounded_o = acc_i;
        end

        // 프로젝트에서 사용하는 정상적인 Shift 범위
        else if (shift_i <= 6'd47) begin

            // TODO 1:
            // acc_i가 음수이면 2의 보수를 이용해 절댓값을 계산
            // acc_i가 0 또는 양수이면 그대로 magnitude에 저장
			magnitude = acc_i[47]? (acc_i ^ {48{1'b1}}) + 1'b1: acc_i;

            // TODO 2:
            // rounding_offset = 2^(shift_i - 1)
            // 48'd1을 왼쪽으로 이동하는 방법 사용
            rounding_offset = 48'd1 << (shift_i - 6'd1);

            // TODO 3:
            // magnitude에 rounding_offset을 더한 후
            // shift_i만큼 오른쪽으로 이동하여 rounded_magnitude 계산
            rounded_magnitude = (magnitude + rounding_offset) >> shift_i;

            // TODO 4:
            // 원래 acc_i가 음수였다면 rounded_magnitude에 다시 음수 부호 적용
            // 원래 값이 양수였다면 rounded_magnitude를 그대로 출력
            rounded_o = acc_i[47]? (rounded_magnitude ^ {48{1'b1}}) + 1'b1: rounded_magnitude;

        end

        // 지원하지 않는 Shift 값은 안전하게 0 출력
        else begin
            rounded_o = 48'sd0;
        end
    end

endmodule