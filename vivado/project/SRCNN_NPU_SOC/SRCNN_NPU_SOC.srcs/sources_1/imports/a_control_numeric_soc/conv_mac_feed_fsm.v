`timescale 1ns / 1ps

module conv_mac_feed_fsm (
    input  wire clk,
    input  wire rst_n,

    // 전체 합성곱 Controller 상태
    input  wire run_i,

    // B파트 Compute Core 상태
    input  wire core_busy_i,
    input  wire core_done_i,

    // 현재 MAC 입력이 한 Output Pixel의 마지막 값인지 표시
    input  wire inner_last_i,

	// Bias Loader가 Bias 4개를 모두 준비했음을 알리는 1-Clock Pulse
	input wire bias_ready_i,

    // B파트 제어 신호
    output reg  op_start_o,
    output reg  bias_load_o,
    output reg  mac_valid_o,
    output reg  mac_last_o,

    // BRAM 읽기 제어
    output reg  bias_fetch_start_o,
    output reg  data_read_en_o,

    // 현재 좌표 처리가 끝났음을 Index Counter에 전달
    output reg  advance_o
);

    localparam	IDLE      = 3'd0,
				START     = 3'd1,
				WAIT_BIAS = 3'd2,
				BIAS      = 3'd3,
				READ      = 3'd4,
				MAC       = 3'd5,
				WAIT_DONE = 3'd6;

    reg [2:0] state;
    reg [2:0] next_state;

    // 1. State Register: 동기식 Active-Low Reset
    always @(posedge clk) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // 2. Next-State Logic: 조합논리
    always @(*) begin
        next_state = state;

        casez ({
            state,
            run_i,
            core_busy_i,
            core_done_i,
            inner_last_i,
			bias_ready_i
        })
            // IDLE에서 실행 중이고 B파트가 비어 있으면 새 연산 시작
			{IDLE, 5'b10???}		:	next_state = START;
            // B파트 연산과 Bias Loader를 시작한 후 Bias 준비 대기
			{START, 5'b?????}		:	next_state = WAIT_BIAS;
            // Bias가 아직 준비되지 않았으면 대기
			{WAIT_BIAS, 5'b????0}	:	next_state = WAIT_BIAS;
			// Bias 네 개가 준비되면 B파트 Bias Load
			{WAIT_BIAS, 5'b????1}	:	next_state = BIAS;
            // Bias Load 후 Activation/Weight BRAM Read
			{BIAS, 5'b?????}		:	next_state = READ;
			// BRAM의 1-Clock Read Latency 후 MAC
			{READ, 5'b?????}		:	next_state = MAC;
            // 현재 입력이 마지막 MAC이 아니면 다음 BRAM Read
			{MAC, 5'b???0?}			:	next_state = READ;
            // 현재 입력이 마지막 MAC이면 B파트 완료 대기
			{MAC, 5'b???1?}			:	next_state = WAIT_DONE;
            // B파트 연산이 아직 끝나지 않았으면 대기
			{WAIT_DONE, 5'b??0??}	:	next_state = WAIT_DONE;
            // B파트 완료 후 전체 Layer 실행도 끝났으면 IDLE
			{WAIT_DONE, 5'b0?1??}	:	next_state = IDLE;
			// B파트 완료 후 다음 Output 연산이 남았으면 START
			{WAIT_DONE, 5'b1?1??}	:	next_state = START;
            // 잘못된 State 값은 안전하게 IDLE로 복귀
            default					:	next_state = IDLE;
        endcase
    end

    // 3. Output Logic: 조합논리
    always @(*) begin
        case (state)
			START	:	{
							op_start_o,
							bias_load_o,
							mac_valid_o,
							mac_last_o,
							bias_fetch_start_o,
							data_read_en_o,
							advance_o
						} = 7'b1000100;

			WAIT_BIAS:	{
							op_start_o,
							bias_load_o,
							mac_valid_o,
							mac_last_o,
							bias_fetch_start_o,
							data_read_en_o,
							advance_o
						} = 7'b0000000;
						
			BIAS	: 	{
							op_start_o,
							bias_load_o,
							mac_valid_o,
							mac_last_o,
							bias_fetch_start_o,
							data_read_en_o,
							advance_o
						} = 7'b0100000;

			READ	:	{
							op_start_o,
							bias_load_o,
							mac_valid_o,
							mac_last_o,
							bias_fetch_start_o,
							data_read_en_o,
							advance_o
						} = 7'b0000010;


			MAC		:	{
							op_start_o,
							bias_load_o,
							mac_valid_o,
							mac_last_o,
							bias_fetch_start_o,
							data_read_en_o,
							advance_o
						} = {3'b001, inner_last_i, 3'b001};

            IDLE	:	{
							op_start_o,
							bias_load_o,
							mac_valid_o,
							mac_last_o,
							bias_fetch_start_o,
							data_read_en_o,
							advance_o
						} = 7'b0000000;

            WAIT_DONE:	{
							op_start_o,
							bias_load_o,
							mac_valid_o,
							mac_last_o,
							bias_fetch_start_o,
							data_read_en_o,
							advance_o
						} = 7'b0000000;

            default:	{
							op_start_o,
							bias_load_o,
							mac_valid_o,
							mac_last_o,
							bias_fetch_start_o,
							data_read_en_o,
							advance_o
						} = 7'b0000000;
        endcase
    end

endmodule
