`timescale 1ns / 1ps

module bias_group_loader (
    input  wire clk,
    input  wire rst_n,

    input  wire start_i,

    input  wire [5:0]  out_channel_group_i,
    input  wire [15:0] bias_base_addr_i,
    input  wire [3:0]  pe_enable_i,

    input  wire signed [31:0] bias_bram_data_i,

    output reg         bias_bram_en_o,
    output reg  [15:0] bias_bram_addr_o,

    output reg signed [31:0] bias_pe0_o,
    output reg signed [31:0] bias_pe1_o,
    output reg signed [31:0] bias_pe2_o,
    output reg signed [31:0] bias_pe3_o,

    output reg         busy_o,
    output reg         bias_ready_o
);

    localparam IDLE    = 2'd0,
               REQUEST = 2'd1,
               CAPTURE = 2'd2,
               DONE    = 2'd3;

    reg [1:0] state;
    reg [1:0] next_state;

    // 현재 읽고 있는 PE 번호
    reg [1:0] pe_index;

    // 현재 Group의 첫 번째 Bias 주소
    reg [15:0] bias_first_addr_reg;

    // 연산 시작 시 고정한 PE Mask
    reg [3:0] pe_enable_reg;

    // State Register: 동기식 Active-Low Reset
    always @(posedge clk) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

	// Next-state Logic
    // PE0~PE3 Bias를 REQUEST와 CAPTURE 상태로 순차 처리하고
	// 네 Bias 처리가 끝나면 DONE 상태로 이동
	always @(*) begin
		casez ({state, start_i, pe_index})
			// IDLE에서 start_i=0이면 대기
			{IDLE, 3'b0??}		:	next_state = IDLE;

			// IDLE에서 start_i=1이면 첫 Bias를 읽기 위해 REQUEST
			{IDLE, 3'b1??}		:	next_state = REQUEST;

			// REQUEST는 BRAM Read Data를 기다리기 위해 CAPTURE
			{REQUEST, 3'b???}	:	next_state = CAPTURE;
			
			// CAPTURE에서 pe_index가 0 또는 1이면 다음 PE의 REQUEST
			{CAPTURE, 3'b?0?}	:	next_state = REQUEST;
			
			// CAPTURE에서 pe_index가 2이면 다음 PE의 REQUEST
			{CAPTURE, 3'b?10}	:	next_state = REQUEST;
			
			// CAPTURE에서 pe_index가 3이면 네 Bias 처리가 끝났으므로 DONE
			{CAPTURE, 3'b?11}	:	next_state = DONE;
			
			// DONE은 1클럭만 유지하고 IDLE
			{DONE, 3'b???}		:	next_state = IDLE;

			// 잘못된 State 값은 안전하게 IDLE로 복귀
			default				:	next_state = IDLE;
		endcase
	end
    
	// Bias 주소, PE Mask 및 읽은 Bias를 저장하는 순차논리
	// Start 시 현재 Group의 첫 Bias 주소와 PE Mask를 저장하고,
	// BRAM에서 읽은 Bias를 PE별 Register에 순차 저장
	always @(posedge clk) begin
		if (!rst_n) begin
			// Reset 시 주소, PE Mask, Bias Register 초기화
			pe_index <= 2'b0;
			bias_first_addr_reg <= 16'b0;
			pe_enable_reg <= 4'b0;
			bias_pe0_o <= 32'b0;
			bias_pe1_o <= 32'b0;
			bias_pe2_o <= 32'b0;
			bias_pe3_o <= 32'b0;
		end
		else begin
			// 현재 Output Channel Group의 첫 Bias 주소와 PE Mask 고정
			// IDLE에서 새로운 Bias Group 읽기를 시작
			if ((state == IDLE) && start_i) begin
				// 첫 번째 Bias 주소 계산
				bias_first_addr_reg <= bias_base_addr_i + {8'd0, out_channel_group_i, 2'b00};	

				// 현재 pe_enable_i를 pe_enable_reg에 저장
				pe_enable_reg <= pe_enable_i;

				// 첫 번째 PE부터 시작하도록 pe_index를 0으로 설정
				pe_index <= 2'b0;

				// 새로운 Group의 Bias 저장 Register 초기화
				bias_pe0_o <= 32'b0;
				bias_pe1_o <= 32'b0;
				bias_pe2_o <= 32'b0;
				bias_pe3_o <= 32'b0;
			end

			// BRAM 출력이 준비된 CAPTURE 상태
			else if (state == CAPTURE) begin
				// 현재 PE가 활성화되어 있으면 BRAM Bias를 저장하고,
				// 비활성 PE이면 안전하게 0 저장
				case(pe_index)
					2'b00	:	bias_pe0_o <= pe_enable_reg[0]? bias_bram_data_i: 32'sd0;
					2'b01	:	bias_pe1_o <= pe_enable_reg[1]? bias_bram_data_i: 32'sd0;
					2'b10	:	bias_pe2_o <= pe_enable_reg[2]? bias_bram_data_i: 32'sd0;
					2'b11	:	bias_pe3_o <= pe_enable_reg[3]? bias_bram_data_i: 32'sd0;
					// pe_index의 모든 비트의 경우의 수에 대해서 모두 기술하였으므로
					// default는 필요 없음
				endcase
				// PE0부터 PE3까지 순서대로 이동
				pe_index <= (pe_index != 2'd3)? pe_index + 2'd1: pe_index;
			end
		end
	end

	// Outpit Logic
    // 상태에 따라 Bias BRAM 주소·Enable과
	// Loader의 Busy·Ready 신호 생성	
	always @(*) begin
		case (state)
			// 새로운 Start를 기다리므로 기본값 유지
			IDLE	:	begin
						busy_o = 1'b0;
						bias_ready_o = 1'b0;
						bias_bram_en_o = 1'b0;
						bias_bram_addr_o = 16'd0;
						end
			
			// 활성 PE에 대해서만 Bias BRAM Read 요청
			REQUEST	:	begin
						busy_o = 1'b1;
						bias_ready_o = 1'b0;
						bias_bram_en_o = pe_enable_reg[pe_index];
						bias_bram_addr_o = pe_enable_reg[pe_index]? bias_first_addr_reg + {14'd0, pe_index}: 16'd0;
						end
			
			// BRAM Read Data가 준비되는 동안 Loader Busy 유지
			CAPTURE	:	begin
						busy_o = 1'b1;
						bias_ready_o = 1'b0;
						bias_bram_en_o = 1'b0;
						bias_bram_addr_o = 16'd0;
						end

			// 네 Bias가 모두 준비됐음을 1클럭 Pulse로 알림
			DONE	:	begin
						busy_o = 1'b0;
						bias_ready_o = 1'b1;
						bias_bram_en_o = 1'b0;
						bias_bram_addr_o = 16'd0;
						end

			default	:	begin
						// 안전한 기본값 유지
						busy_o = 1'b0;
						bias_ready_o = 1'b0;
						bias_bram_en_o = 1'b0;
						bias_bram_addr_o = 16'd0;
						end
		endcase
	end

endmodule
