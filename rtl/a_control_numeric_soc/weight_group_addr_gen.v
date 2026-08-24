`timescale 1ns / 1ps

module weight_group_addr_gen (
    // 현재 Output Channel Group 번호
    // Group 0: OC 0~3, Group 1: OC 4~7
    input  wire [5:0]  out_channel_group_i,

    // 실제 전체 Output Channel 개수
    // Conv1=64, Conv2=32, Conv3=1
    input  wire [6:0]  out_channel_count_i,

    input  wire [5:0]  in_channel_i,
    input  wire [6:0]  in_channel_count_i,

    input  wire [3:0]  kernel_y_i,
    input  wire [3:0]  kernel_x_i,
    input  wire [3:0]  kernel_size_i,

    // 64-bit Weight Word 단위의 Layer 시작 주소
    input  wire [15:0] weight_word_base_addr_i,

    // 사용할 PE 표시: {PE3, PE2, PE1, PE0}
    output reg  [3:0]  pe_enable_o,

    // 64-bit Packed Weight BRAM의 Word 주소
    output wire [15:0] weight_word_addr_o
);

    // 현재 Group에서 PE0가 담당하는 실제 Output Channel
    reg [6:0] out_channel_base;

    // PE Mask 계산: 순수 조합논리
    always @(*) begin
        out_channel_base = 7'd0;
        pe_enable_o      = 4'b0000;

        // TODO 1:
        // Group 번호에 4를 곱하여 실제 시작 Output Channel 계산
        //
        // out_channel_base =
        //     {1'b0, out_channel_group_i}를 왼쪽으로 2-bit Shift
		out_channel_base = {1'b0, out_channel_group_i} << 2'd2;

        // TODO 2:
        // 각 PE가 담당할 실제 Output Channel이
        // out_channel_count_i보다 작으면 해당 PE Enable
        //
        // PE0: out_channel_base + 0
        // PE1: out_channel_base + 1
        // PE2: out_channel_base + 2
        // PE3: out_channel_base + 3
        //
        // 비교 결과를 pe_enable_o[0]~[3]에 각각 저장
        // 7'd0, 7'd1, 7'd2, 7'd3을 사용할 것
		pe_enable_o[0] = (out_channel_base + 7'd0 < out_channel_count_i);
		pe_enable_o[1] = (out_channel_base + 7'd1 < out_channel_count_i);
		pe_enable_o[2] = (out_channel_base + 7'd2 < out_channel_count_i);
		pe_enable_o[3] = (out_channel_base + 7'd3 < out_channel_count_i);
    end

    // 기존 검증된 주소 생성기를 64-bit Word 주소 계산에 재사용
    //
    // 여기서 out_channel_group_i는 기존 주소식의
    // out_channel 차원 대신 Packed Weight Group 차원으로 사용된다.
    weight_addr_gen u_weight_addr_gen (
		//input port
		.out_channel_i(out_channel_group_i),
		.in_channel_i(in_channel_i),
		.in_channel_count_i(in_channel_count_i),
		.kernel_y_i(kernel_y_i),
		.kernel_x_i(kernel_x_i),
		.kernel_size_i(kernel_size_i),
		.weight_base_addr_i(weight_word_base_addr_i),
		//output port
		.weight_addr_o(weight_word_addr_o)
    );

endmodule
