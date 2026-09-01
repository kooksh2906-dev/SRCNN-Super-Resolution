`timescale 1ns / 1ps

module conv_control_fsm (
    input  wire clk,
    input  wire rst_n,

    input  wire start_i,
    input  wire advance_i,
    input  wire last_index_i,

    output reg  run_o,
    output reg  done_o
);

    localparam	IDLE = 2'd0,
    			RUN  = 2'd1,
    			DONE = 2'd2;

    reg [1:0] state;
    reg [1:0] next_state;

    // 1. State Register: 순차논리
    // rst_n=0이면 다음 Clock 상승 에지에서 동기식 Reset
    always @(posedge clk) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // 2. Next-State Logic: 조합논리
    always @(*) begin
        casez({state, start_i, advance_i, last_index_i})
            // TODO 1:
            // start_i가 1이면 RUN으로 이동
			{IDLE,3'b1??}	:	next_state = RUN;

            // TODO 2:
            // advance_i와 last_index_i가 모두 1이면
            // 모든 계산이 끝났으므로 DONE으로 이동
			{RUN,3'b?0?}	:	next_state = RUN;
			{RUN,3'b?10}	:	next_state = RUN;
			{RUN,3'b?11}	:	next_state = DONE;

            // TODO 3:
            // DONE 상태는 1클럭만 유지하고 IDLE로 이동
			{DONE,3'b???}	:	next_state = IDLE;
            default			:	next_state = IDLE;
        endcase
    end

    // 3. Output Logic: 조합논리
    always @(*) begin
        case (state)
			// 기본값 유지
            IDLE	:	{run_o , done_o} = 2'b00;
			
			// TODO 4:
        	// 실행 중이므로 run_o를 1로 설정
            RUN		:	{run_o , done_o} = 2'b10;

			// TODO 5:
            // 완료 상태이므로 done_o를 1로 설정
            DONE	:	{run_o , done_o} = 2'b01;
            default	:	{run_o , done_o} = 2'b00;
        endcase
    end

endmodule
