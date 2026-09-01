`timescale 1ns / 1ps

module conv_inner_last_gen (
    // 현재 Input Channel과 전체 Input Channel 개수
    input  wire [5:0] in_channel_i,
    input  wire [6:0] in_channel_count_i,

    // 현재 Kernel 좌표와 Kernel 크기
    input  wire [3:0] kernel_y_i,
    input  wire [3:0] kernel_x_i,
    input  wire [3:0] kernel_size_i,

    // 한 Output Pixel의 마지막 MAC 좌표
    output reg        inner_last_o
);

    // 마지막 내부 반복 좌표 판정: 순수 조합논리
    always @(*) begin
        // 현재 좌표가 한 Output Pixel을 계산하기 위한 마지막 MAC 좌표인지 검사
        inner_last_o = ({1'b0, in_channel_i} == in_channel_count_i - 7'd1)	&&
					   (kernel_y_i == kernel_size_i - 4'd1)					&&
					   (kernel_x_i == kernel_size_i - 4'd1);
    end

endmodule