`timescale 1ns / 1ps

module conv_address_unit (
    // 현재 계산 위치
    input  wire [5:0]  out_channel_i,
    input  wire [5:0]  in_channel_i,
    input  wire [4:0]  out_y_i,
    input  wire [4:0]  out_x_i,
    input  wire [3:0]  kernel_y_i,
    input  wire [3:0]  kernel_x_i,

    // 현재 Layer 설정
    input  wire [6:0]  in_channel_count_i,
    input  wire [3:0]  kernel_size_i,
    input  wire [3:0]  pad_i,
    input  wire [15:0] weight_base_addr_i,

    // 계산된 주소와 Padding 여부
    output wire        padding_o,
    output wire [15:0] activation_addr_o,
    output wire [15:0] weight_addr_o
);
	// 입력 Feature Map을 읽을 주소를 계산
	activation_addr_gen	u_activation_addr_gen(
		// input port
		.channel_i(in_channel_i),	// 입력 이미지의 채널 번호
		.out_y_i(out_y_i),
		.out_x_i(out_x_i),
		.kernel_y_i(kernel_y_i),
		.kernel_x_i(kernel_x_i),
		.pad_i(pad_i),
		// output port
		.padding_o(padding_o),
		.activation_addr_o(activation_addr_o)
	);

	// Weight를 읽을 주소를 계산
	weight_addr_gen	u_weight_addr_gen(
		// input port
		.out_channel_i(out_channel_i),
		.in_channel_i(in_channel_i),	// Input Channel 번호
		.in_channel_count_i(in_channel_count_i),
		.kernel_y_i(kernel_y_i),
		.kernel_x_i(kernel_x_i),
		.kernel_size_i(kernel_size_i),
		.weight_base_addr_i(weight_base_addr_i),
		// output port
		.weight_addr_o(weight_addr_o)
	);

endmodule
