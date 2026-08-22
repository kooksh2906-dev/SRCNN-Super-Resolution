`timescale 1ns / 1ps

module relu_clamp_int16 (
    input  wire signed [47:0] rounded_i,
    output reg  signed [15:0] clamped_o
);

    // 순수 조합논리
    always @(*) begin
        // Latch 방지를 위한 기본값
        clamped_o = 16'sd0;

        // TODO 1:
        // rounded_i가 음수이면 0 출력
		if(rounded_i[47])
			clamped_o = 16'sd0;

        // TODO 2:
        // rounded_i가 signed INT16 양수 최댓값인
        // 32767보다 크면 32767 출력
		else if(rounded_i > 48'sd32767)
			clamped_o = 16'sd32767;

        // TODO 3:
        // 0~32767 범위이면 rounded_i의
        // 하위 16-bit를 그대로 출력
		else
			clamped_o = rounded_i[15:0];
    end

endmodule