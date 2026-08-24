`timescale 1ns / 1ps

module conv_index_counter (
    input  wire clk,
    input  wire arstn,

    // 새로운 연산 시작 시 모든 좌표를 0으로 초기화
    input  wire clear_i,

    // 현재 좌표 처리가 끝났을 때 다음 좌표로 이동
    input  wire advance_i,

    // 현재 Layer의 반복 횟수 설정
    input  wire [6:0] out_channel_count_i,
    input  wire [6:0] in_channel_count_i,
    input  wire [5:0] output_size_i,
    input  wire [3:0] kernel_size_i,

    // 현재 합성곱 좌표
    output reg  [5:0] out_channel_o,
    output reg  [5:0] in_channel_o,
    output reg  [4:0] out_y_o,
    output reg  [4:0] out_x_o,
    output reg  [3:0] kernel_y_o,
    output reg  [3:0] kernel_x_o,

    // 전체 Layer의 마지막 좌표에서 1 출력
    output reg        last_index_o
);

    // 여섯 카운터가 모두 마지막 값이면 전체 마지막 좌표로 판정
    always @(*) begin
        last_index_o =
            ({1'b0, out_channel_o} ==
                (out_channel_count_i - 7'd1)) &&
            ({1'b0, out_y_o} ==
                (output_size_i - 6'd1)) &&
            ({1'b0, out_x_o} ==
                (output_size_i - 6'd1)) &&
            ({1'b0, in_channel_o} ==
                (in_channel_count_i - 7'd1)) &&
            (kernel_y_o ==
                (kernel_size_i - 4'd1)) &&
            (kernel_x_o ==
                (kernel_size_i - 4'd1));
    end

    // 가장 안쪽의 kernel_x부터 out_channel까지 Carry 방식으로 증가
    always @(posedge clk or negedge arstn) begin
        if (!arstn) begin
            out_channel_o <= 6'd0;
            in_channel_o  <= 6'd0;
            out_y_o       <= 5'd0;
            out_x_o       <= 5'd0;
            kernel_y_o    <= 4'd0;
            kernel_x_o    <= 4'd0;
        end
        else if (clear_i) begin
            out_channel_o <= 6'd0;
            in_channel_o  <= 6'd0;
            out_y_o       <= 5'd0;
            out_x_o       <= 5'd0;
            kernel_y_o    <= 4'd0;
            kernel_x_o    <= 4'd0;
        end
        else if (advance_i) begin

            // 전체 마지막 좌표에서는 모든 카운터 값을 유지
            if (last_index_o) begin
            end

            // kernel_x가 끝나면 0으로 복귀하고 kernel_y로 Carry
            else if (kernel_x_o ==
                     (kernel_size_i - 4'd1)) begin

                kernel_x_o <= 4'd0;

                // kernel_y가 끝나면 0으로 복귀하고 in_channel로 Carry
                if (kernel_y_o ==
                    (kernel_size_i - 4'd1)) begin

                    kernel_y_o <= 4'd0;

                    // 모든 Kernel 순회 후 다음 Input Channel로 이동
                    if ({1'b0, in_channel_o} ==
                        (in_channel_count_i - 7'd1)) begin

                        in_channel_o <= 6'd0;

                        // 모든 Input Channel 순회 후 다음 Output X로 이동
                        if ({1'b0, out_x_o} ==
                            (output_size_i - 6'd1)) begin

                            out_x_o <= 5'd0;

                            // 한 행이 끝나면 다음 Output Y로 이동
                            if ({1'b0, out_y_o} ==
                                (output_size_i - 6'd1)) begin

                                out_y_o <= 5'd0;

                                // 전체 출력 평면이 끝나면 다음 Output Channel로 이동
                                out_channel_o <= out_channel_o + 6'd1;
                            end
                            else begin
                                out_y_o <= out_y_o + 5'd1;
                            end
                        end
                        else begin
                            out_x_o <= out_x_o + 5'd1;
                        end
                    end
                    else begin
                        in_channel_o <= in_channel_o + 6'd1;
                    end
                end
                else begin
                    kernel_y_o <= kernel_y_o + 4'd1;
                end
            end
            else begin
                kernel_x_o <= kernel_x_o + 4'd1;
            end
        end
    end

endmodule