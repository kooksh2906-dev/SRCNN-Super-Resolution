`timescale 1ns / 1ps

module activation_addr_gen (
    input  wire [5:0] channel_i,
    input  wire [4:0] out_y_i,
    input  wire [4:0] out_x_i,
    input  wire [3:0] kernel_y_i,
    input  wire [3:0] kernel_x_i,
    input  wire [3:0] pad_i,

    output reg         padding_o,
    output reg  [15:0] activation_addr_o
);

    // Padding 적용 후 실제로 읽어야 할 입력 좌표
    // 음수 좌표를 표현해야 하므로 signed 7-bit 사용
    reg signed [6:0] input_y;
    reg signed [6:0] input_x;

    // Clock과 Reset이 필요 없는 순수 조합논리
    always @(*) begin
        // Latch 방지를 위한 기본값
        input_y          = 7'sd0;
        input_x          = 7'sd0;
        padding_o        = 1'b0;
        activation_addr_o = 16'd0;

        // TODO 1:
        // 실제 입력 좌표를 계산한다.
        //
        // 입력 Y = 출력 Y + 커널 Y - Padding
        // 입력 X = 출력 X + 커널 X - Padding
        //
        // 서로 다른 비트 폭을 모두 signed 7-bit로 맞출 것
        // 힌트:
        // $signed({2'b00, out_y_i})
        // $signed({3'b000, kernel_y_i})
        // $signed({3'b000, pad_i})
		input_y = $signed({2'b00, out_y_i} )
				+ $signed({3'b000, kernel_y_i})
				- $signed({3'b000, pad_i});

		input_x = $signed({2'b00, out_x_i}) 
				+ $signed({3'b000, kernel_x_i}) 
				- $signed({3'b000, pad_i});

        // TODO 2:
        // input_y 또는 input_x가 0~31 범위를 벗어났는지 검사한다.
        //
        // 범위를 벗어난 경우:
        //   padding_o         = 1'b1;
        //   activation_addr_o = 16'd0;
        //
        // 정상 범위인 경우:
        //   padding_o         = 1'b0;
        //   TODO 3의 주소 계산 수행
		if ((input_y < 7'sd0) || (input_y > 7'sd31) ||
            (input_x < 7'sd0) || (input_x > 7'sd31)) begin
            padding_o         = 1'b1;
            activation_addr_o = 16'd0;
        end
        // TODO 3:
        // 정상 좌표의 Activation BRAM 주소를 계산한다.
        //
        // address = channel_i * 1024
        //         + input_y   * 32
        //         + input_x
        //
        // 곱셈 연산자 대신 Shift 또는 비트 결합을 사용해볼 것
        //
        // channel_i * 1024는 channel_i를 왼쪽으로 10-bit 이동
        // input_y   * 32는 input_y를 왼쪽으로 5-bit 이동
		else begin
			padding_o = 1'b0;
			activation_addr_o = {channel_i,10'b0} 
							  + {6'b0,input_y[4:0],5'b0} // 음수 표현만 빼고 주소 게산
							  + {11'b0,input_x[4:0]};
		end

    end

endmodule
