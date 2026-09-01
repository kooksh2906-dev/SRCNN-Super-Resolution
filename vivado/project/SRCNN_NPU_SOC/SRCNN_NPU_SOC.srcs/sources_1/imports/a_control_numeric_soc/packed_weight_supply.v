`timescale 1ns / 1ps

module packed_weight_supply (
    // 현재 Output Channel Group과 Layer 설정
    input  wire [5:0]  out_channel_group_i,
    input  wire [6:0]  out_channel_count_i,

    // 현재 Input Channel 및 Kernel 위치
    input  wire [5:0]  in_channel_i,
    input  wire [6:0]  in_channel_count_i,
    input  wire [3:0]  kernel_y_i,
    input  wire [3:0]  kernel_x_i,
    input  wire [3:0]  kernel_size_i,

    // 64-bit Weight Word 단위의 Layer 시작 주소
    input  wire [15:0] weight_word_base_addr_i,

    // Packed Weight BRAM에서 읽은 64-bit Word
    input  wire [63:0] weight_word_i,

    // Weight BRAM 주소와 PE 사용 여부
    output wire [15:0] weight_word_addr_o,
    output wire [3:0]  pe_enable_o,

    // 팀원 B의 PE0~PE3에 전달할 signed INT16 Weight
    output wire signed [15:0] weight_pe0_o,
    output wire signed [15:0] weight_pe1_o,
    output wire signed [15:0] weight_pe2_o,
    output wire signed [15:0] weight_pe3_o
);

    // 주소 생성기의 PE Enable을 Weight Mask에도 사용
    wire [3:0] pe_enable_int;

    // Packed Weight 주소와 현재 Group의 PE Enable 생성
	weight_group_addr_gen	u_weight_group_addr_gen(
		// input port
		.out_channel_group_i(out_channel_group_i),
		.out_channel_count_i(out_channel_count_i),
		.in_channel_i(in_channel_i),
		.in_channel_count_i(in_channel_count_i),
		.kernel_y_i(kernel_y_i),
		.kernel_x_i(kernel_x_i),
		.kernel_size_i(kernel_size_i),
		.weight_word_base_addr_i(weight_word_base_addr_i),
		// output port
		.pe_enable_o(pe_enable_int),
		.weight_word_addr_o(weight_word_addr_o)
	);

    // 내부 PE Enable을 외부 포트로 전달
	assign pe_enable_o = pe_enable_int;

    // 64-bit Packed Word를 PE별 INT16 Weight로 분리하고 비활성 PE를 0으로 Mask
	assign weight_pe0_o = pe_enable_int[0] ? $signed(weight_word_i[15:0])  : 16'sd0;
	assign weight_pe1_o = pe_enable_int[1] ? $signed(weight_word_i[31:16]) : 16'sd0;
	assign weight_pe2_o = pe_enable_int[2] ? $signed(weight_word_i[47:32]) : 16'sd0;
	assign weight_pe3_o = pe_enable_int[3] ? $signed(weight_word_i[63:48]) : 16'sd0;

endmodule
