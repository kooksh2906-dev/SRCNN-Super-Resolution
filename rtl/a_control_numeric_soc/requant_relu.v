`timescale 1ns / 1ps

module requant_relu (
    input  wire signed [47:0] acc_i,
    input  wire        [5:0]  shift_i,

    output reg  signed [15:0] data_o
);

    reg        [47:0] magnitude;
    reg        [47:0] rounding_offset;
    reg        [47:0] rounded_magnitude;
    reg signed [48:0] rounded_signed;

    always @(*) begin
		// INT48 입력의 부호를 분리하고 절댓값 계산
        // 음수이면 2의 보수로 절댓값을 만들고, 양수이면 입력값을 그대로 사용
        magnitude = acc_i[47]? (acc_i ^ {48{1'b1}}) + 1'b1: acc_i;

        // Round-to-nearest를 위한 절반 크기 Offset 계산
		// shift=0이면 반올림 값은 0, 그 외에는 2^(shift_i-1)
        rounding_offset = !shift_i? 48'b0: 48'd1 << (shift_i-1'b1);

		// Offset을 더한 후 지정된 크기만큼 Right Shift
        // shift=0이면 원래 크기를 유지, 그 외에는 반올림 값을 더한 뒤 오른쪽 Shift
        rounded_magnitude = !shift_i? magnitude: (magnitude + rounding_offset) >> shift_i;

		// 절댓값 기반 반올림 후 원래 부호 복원
        // 원래 acc_i가 음수였다면 다시 음수로 부호 복원
        rounded_signed = acc_i[47]? -$signed({1'b0, rounded_magnitude}): $signed({1'b0, rounded_magnitude});

		// 음수는 ReLU로 제거하고 INT16 최대값을 초과하면 포화
        // ReLU 및 signed INT16 양수 범위로 Saturation
        if (rounded_signed < 16'sd0)
            data_o = 16'sd0;
        else if (rounded_signed > 16'sd32767)
            data_o = 16'sd32767;
        else
            data_o = rounded_signed[15:0];
    end

endmodule
