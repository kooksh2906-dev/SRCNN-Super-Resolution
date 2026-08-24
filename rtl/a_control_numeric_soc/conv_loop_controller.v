`timescale 1ns / 1ps

module conv_loop_controller (
    input  wire clk,
    input  wire rst_n,

    input  wire start_i,
    input  wire advance_i,

    // 현재 Layer의 반복 횟수 설정
    input  wire [6:0] out_channel_count_i,
    input  wire [6:0] in_channel_count_i,
    input  wire [5:0] output_size_i,
    input  wire [3:0] kernel_size_i,

    // Controller 상태
    output wire       run_o,
    output wire       done_o,
    output wire       last_index_o,

    // 현재 합성곱 좌표
    output wire [5:0] out_channel_o,
    output wire [5:0] in_channel_o,
    output wire [4:0] out_y_o,
    output wire [4:0] out_x_o,
    output wire [3:0] kernel_y_o,
    output wire [3:0] kernel_x_o
);

    // RUN 상태에서 승인된 advance_i만 카운터에 전달
    wire counter_advance;

    // IDLE 상태의 새로운 Start에서 카운터 초기화
    wire counter_clear;

    // TODO 1:
    // counter_advance는 run_o와 advance_i가 모두 1일 때 1
    assign counter_advance = run_o && advance_i;

    // TODO 2:
    // Start가 입력됐고 RUN/DONE 상태가 아닐 때만 카운터 초기화
    assign counter_clear = start_i && !run_o && !done_o;

    // 실행 상태와 완료 상태를 관리
    conv_control_fsm u_conv_control_fsm (
		// input port
		.clk(clk),
		.rst_n(rst_n),
		.start_i(start_i),
		.advance_i(counter_advance),
		.last_index_i(last_index_o),
		// output port
		.run_o(run_o),
		.done_o(done_o)
    );

    // 합성곱의 여섯 좌표를 Carry 방식으로 순회
    conv_index_counter u_conv_index_counter (
        // input port
		.clk(clk),
		.rst_n(rst_n),
		.clear_i(counter_clear),
		.advance_i(counter_advance),
		.out_channel_count_i(out_channel_count_i),
		.in_channel_count_i(in_channel_count_i),
		.output_size_i(output_size_i),
		.kernel_size_i(kernel_size_i),
		// output port
		.out_channel_o(out_channel_o),
		.in_channel_o(in_channel_o),
		.out_y_o(out_y_o),
		.out_x_o(out_x_o),
		.kernel_y_o(kernel_y_o),
		.kernel_x_o(kernel_x_o),
		.last_index_o(last_index_o)
    );

endmodule
