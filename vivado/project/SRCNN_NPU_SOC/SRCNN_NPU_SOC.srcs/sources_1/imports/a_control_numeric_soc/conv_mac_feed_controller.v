`timescale 1ns / 1ps

module conv_mac_feed_controller (
    input  wire clk,
    input  wire rst_n,

    // 전체 합성곱 반복 Controller 상태
    input  wire run_i,

    // B파트 Compute Core 상태
    input  wire core_busy_i,
    input  wire core_done_i,

    // Bias Loader 완료 신호
    input  wire bias_ready_i,

    // 현재 내부 MAC 좌표
    input  wire [5:0] in_channel_i,
    input  wire [6:0] in_channel_count_i,
    input  wire [3:0] kernel_y_i,
    input  wire [3:0] kernel_x_i,
    input  wire [3:0] kernel_size_i,

    // B파트 제어 신호
    output wire       op_start_o,
    output wire       bias_load_o,
    output wire       mac_valid_o,
    output wire       mac_last_o,

    // Bias 및 Activation/Weight 읽기 제어
    output wire       bias_fetch_start_o,
    output wire       data_read_en_o,

    // Index Counter 좌표 증가
    output wire       advance_o
);

    // 현재 좌표가 한 Output Pixel의 마지막 MAC인지 표시
    wire inner_last;

    // 현재 Input Channel과 Kernel 좌표로 마지막 MAC 판정
    conv_inner_last_gen u_conv_inner_last_gen (
		// Input Port
		.in_channel_i(in_channel_i),
		.in_channel_count_i(in_channel_count_i),
		.kernel_y_i(kernel_y_i),
		.kernel_x_i(kernel_x_i),
		.kernel_size_i(kernel_size_i),
		// Output Port
		.inner_last_o(inner_last)
    );

    // Bias 준비, BRAM 읽기, MAC 공급 순서를 제어
    conv_mac_feed_fsm u_conv_mac_feed_fsm (
		// Input Port
		.clk(clk),
		.rst_n(rst_n),
		.run_i(run_i),
		.core_busy_i(core_busy_i),
		.core_done_i(core_done_i),
		.inner_last_i(inner_last),
		.bias_ready_i(bias_ready_i),
		// Output Port
		.op_start_o(op_start_o),
		.bias_load_o(bias_load_o),
		.mac_valid_o(mac_valid_o),
		.mac_last_o(mac_last_o),
		.bias_fetch_start_o(bias_fetch_start_o),
		.data_read_en_o(data_read_en_o),
		.advance_o(advance_o)
    );

endmodule
