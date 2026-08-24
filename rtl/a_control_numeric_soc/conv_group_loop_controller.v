`timescale 1ns / 1ps

module conv_group_loop_controller (
    input  wire clk,
    input  wire rst_n,

    input  wire start_i,
    input  wire advance_i,

    // 실제 Layer 설정
    input  wire [6:0] out_channel_count_i,
    input  wire [6:0] in_channel_count_i,
    input  wire [5:0] output_size_i,
    input  wire [3:0] kernel_size_i,

    // Controller 상태
    output wire       run_o,
    output wire       done_o,
    output wire       last_index_o,

    // 4-PE Output Channel Group 정보
    output wire [6:0] out_channel_group_count_o,
    output wire [5:0] out_channel_group_o,

    // 현재 내부 MAC 좌표
    output wire [5:0] in_channel_o,
    output wire [4:0] out_y_o,
    output wire [4:0] out_x_o,
    output wire [3:0] kernel_y_o,
    output wire [3:0] kernel_x_o
);

    // 실제 Output Channel 수를 4-PE Group 수로 변환
    conv_group_count_gen u_conv_group_count_gen (
		// Input Port
		.out_channel_count_i(out_channel_count_i),
		// Output Port
		.out_channel_group_count_o(out_channel_group_count_o)
    );

    // 기존 검증된 Loop Controller는 Group을 Output Channel처럼 순회
    conv_loop_controller u_conv_loop_controller (
		// Input Port
		.clk(clk),
		.rst_n(rst_n),
		.start_i(start_i),
		.advance_i(advance_i),
		.out_channel_count_i(out_channel_group_count_o),
		.in_channel_count_i(in_channel_count_i),
		.output_size_i(output_size_i),
		.kernel_size_i(kernel_size_i),
		// Output Port
		.run_o(run_o),
		.done_o(done_o),
		.last_index_o(last_index_o),
		.out_channel_o(out_channel_group_o),
		.in_channel_o(in_channel_o),
		.out_y_o(out_y_o),
		.out_x_o(out_x_o),
		.kernel_y_o(kernel_y_o),
		.kernel_x_o(kernel_x_o)
    );

endmodule
