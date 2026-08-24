`timescale 1ns / 1ps

module conv_control_address_top (
    input  wire clk,
    input  wire rst_n,

    // 합성곱 실행 제어
    input  wire start_i,
    input  wire advance_i,

    // 현재 Layer 설정
    input  wire [6:0]  out_channel_count_i,
    input  wire [6:0]  in_channel_count_i,
    input  wire [5:0]  output_size_i,
    input  wire [3:0]  kernel_size_i,
    input  wire [3:0]  pad_i,
    input  wire [15:0] weight_base_addr_i,

    // Controller 상태
    output wire        run_o,
    output wire        done_o,
    output wire        last_index_o,

    // 현재 합성곱 좌표
    output wire [5:0]  out_channel_o,
    output wire [5:0]  in_channel_o,
    output wire [4:0]  out_y_o,
    output wire [4:0]  out_x_o,
    output wire [3:0]  kernel_y_o,
    output wire [3:0]  kernel_x_o,

    // 현재 좌표에 해당하는 BRAM 주소
    output wire        padding_o,
    output wire [15:0] activation_addr_o,
    output wire [15:0] weight_addr_o
);

    // 합성곱 좌표와 실행 상태를 관리
    conv_loop_controller u_conv_loop_controller (
		// input port
		.clk(clk),
    	.rst_n(rst_n),
		.start_i(start_i),
		.advance_i(advance_i),
		.out_channel_count_i(out_channel_count_i),
		.in_channel_count_i(in_channel_count_i),
		.output_size_i(output_size_i),
		.kernel_size_i(kernel_size_i),
		// output port
		.run_o(run_o),
		.done_o(done_o),
		.last_index_o(last_index_o),
		.out_channel_o(out_channel_o),
		.in_channel_o(in_channel_o),
		.out_y_o(out_y_o),
		.out_x_o(out_x_o),
		.kernel_y_o(kernel_y_o),
		.kernel_x_o(kernel_x_o)
    );

    // Controller가 만든 좌표를 BRAM 주소로 변환
    conv_address_unit u_conv_address_unit (
		// output port
		.out_channel_i(out_channel_o),
		.in_channel_i(in_channel_o),
		.out_y_i(out_y_o),
		.out_x_i(out_x_o),
		.kernel_y_i(kernel_y_o),
		.kernel_x_i(kernel_x_o),
		.in_channel_count_i(in_channel_count_i),
		.kernel_size_i(kernel_size_i),
		.pad_i(pad_i),
		.weight_base_addr_i(weight_base_addr_i),
		// output port
		.padding_o(padding_o),
		.activation_addr_o(activation_addr_o),
		.weight_addr_o(weight_addr_o)
    );

endmodule
