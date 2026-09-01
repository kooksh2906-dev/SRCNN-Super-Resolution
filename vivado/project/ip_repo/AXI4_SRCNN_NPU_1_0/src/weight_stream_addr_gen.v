`timescale 1ns / 1ps

module weight_stream_addr_gen (
    input  wire        clk,
    input  wire        rst_n,

    // 새로운 Output Pixel 연산을 시작할 때 Group의 첫 Weight 주소를 적재
    input  wire        sequence_start_i,

    // Weight ROM Read가 발생할 때 다음 Packed Weight Word로 이동
    input  wire        read_en_i,

    // 고정 SRCNN Layer 설정과 현재 Output Channel Group
    input  wire [5:0]  out_channel_group_i,
    input  wire [15:0] weight_word_base_addr_i,

    // ROM에 직접 전달되는 Registered Weight Word 주소
    output reg  [15:0] weight_word_addr_o
);

    reg [15:0] group_first_addr;

    // 각 Group의 Weight는 메모리에서 연속 배치되어 있다.
    // 긴 다단 곱셈 대신 Layer Base와 Group 번호로 시작 주소만 선택한다.
    always @(*) begin
        case (weight_word_base_addr_i)
            16'd0: begin
                // Conv1: Group당 1 × 9 × 9 = 81 Weight Word
                case (out_channel_group_i)
                    6'd0:  group_first_addr = 16'd0;
                    6'd1:  group_first_addr = 16'd81;
                    6'd2:  group_first_addr = 16'd162;
                    6'd3:  group_first_addr = 16'd243;
                    6'd4:  group_first_addr = 16'd324;
                    6'd5:  group_first_addr = 16'd405;
                    6'd6:  group_first_addr = 16'd486;
                    6'd7:  group_first_addr = 16'd567;
                    6'd8:  group_first_addr = 16'd648;
                    6'd9:  group_first_addr = 16'd729;
                    6'd10: group_first_addr = 16'd810;
                    6'd11: group_first_addr = 16'd891;
                    6'd12: group_first_addr = 16'd972;
                    6'd13: group_first_addr = 16'd1053;
                    6'd14: group_first_addr = 16'd1134;
                    6'd15: group_first_addr = 16'd1215;
                    default: group_first_addr = 16'd0;
                endcase
            end

            16'd1296: begin
                // Conv2: Group당 64 × 5 × 5 = 1600 Weight Word
                case (out_channel_group_i)
                    6'd0: group_first_addr = 16'd1296;
                    6'd1: group_first_addr = 16'd2896;
                    6'd2: group_first_addr = 16'd4496;
                    6'd3: group_first_addr = 16'd6096;
                    6'd4: group_first_addr = 16'd7696;
                    6'd5: group_first_addr = 16'd9296;
                    6'd6: group_first_addr = 16'd10896;
                    6'd7: group_first_addr = 16'd12496;
                    default: group_first_addr = 16'd1296;
                endcase
            end

            16'd14096: begin
                // Conv3는 Output Channel Group이 하나뿐이다.
                group_first_addr = 16'd14096;
            end

            default: begin
                // 잘못된 Layer 설정에서는 Base 주소부터 시작해 안전하게 동작
                group_first_addr = weight_word_base_addr_i;
            end
        endcase
    end

    // Group 시작 주소는 Bias를 준비하는 동안 미리 적재한다.
    // 이후 READ마다 1씩 증가하므로 BRAM 앞의 긴 조합 주소 경로가 제거된다.
    always @(posedge clk) begin
        if (!rst_n)
            weight_word_addr_o <= 16'd0;
        else if (sequence_start_i)
            weight_word_addr_o <= group_first_addr;
        else if (read_en_i)
            weight_word_addr_o <= weight_word_addr_o + 16'd1;
    end

endmodule
