`timescale 1ns / 1ps

module requant_relu (
    input  wire signed [47:0] acc_i,
    input  wire        [5:0]  shift_i,
    output wire signed [15:0] data_o
);

    // 반올림 및 Shift가 끝난 signed INT48 중간값
    wire signed [47:0] rounded_value;

    // TODO 1:
    // requant_round_shift Sub Module 인스턴스
	requant_round_shift u_requant_round_shift(
    	.acc_i		(acc_i),
    	.shift_i	(shift_i),
    	.rounded_o	(rounded_value)
	);

    // TODO 2:
    // relu_clamp_int16 Sub Module 인스턴스
	relu_clamp_int16 u_relu_clamp_int16(
    	.rounded_i	(rounded_value),
    	.clamped_o	(data_o)
	);

endmodule