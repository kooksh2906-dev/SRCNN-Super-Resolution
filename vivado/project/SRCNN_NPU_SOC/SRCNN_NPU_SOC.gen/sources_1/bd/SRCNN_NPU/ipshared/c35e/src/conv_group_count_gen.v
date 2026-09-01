`timescale 1ns / 1ps

module conv_group_count_gen (
    // 실제 전체 Output Channel 개수
    input  wire [6:0] out_channel_count_i,

    // 4개 PE가 병렬 처리할 Output Channel Group 개수
    output reg  [6:0] out_channel_group_count_o
);

    // 4로 나눈 값을 올림하여 Group 개수 계산
    always @(*) begin
        // 현재 4개 PE가 Output Channel 4개를 동시에 계산하므로 
		// Counter는 개별 채널이 아니라 Group 수만큼 반복해야 함
		// 따라서, 최종 상위 계층에서 계산된 Group 수를 계산 해야 함
        out_channel_group_count_o = ({1'b0, out_channel_count_i} + 8'd3) >> 2'd2;
    end

endmodule
