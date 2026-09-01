`timescale 1ns / 1ps

module srcnn_layer_controller (
    input  wire clk,
    input  wire rst_n,

    // 전체 SRCNN 실행 시작 Pulse
    input  wire start_i,

    // 현재 Layer의 Group Compute 완료 Pulse
    input  wire layer_done_i,

    // 현재 Layer를 시작하는 1-Clock Pulse
    output reg  layer_start_o,

    // 전체 SRCNN 상태
    output reg  run_o,
    output reg  done_o,

    // 현재 Layer: 0=Conv1, 1=Conv2, 2=Conv3
    output reg  [1:0] layer_index_o,

    // 현재 Layer 설정
    output reg  [6:0]  out_channel_count_o,
    output reg  [6:0]  in_channel_count_o,
    output reg  [5:0]  output_size_o,
    output reg  [3:0]  kernel_size_o,
    output reg  [3:0]  pad_o,
    output reg  [5:0]  requant_shift_o,
    output reg  [15:0] weight_word_base_addr_o,
    output reg  [15:0] bias_base_addr_o,

    // Activation Source:
    // 0=Input Tile, 1=Feature Bank A, 2=Feature Bank B
    output reg  [1:0] activation_source_o,

    // 결과 저장 Bank:
    // 0=Feature Bank A, 1=Feature Bank B
    output reg        feature_write_bank_o
);

    localparam STATE_IDLE        = 2'd0;
    localparam STATE_START_LAYER = 2'd1;
    localparam STATE_WAIT_LAYER  = 2'd2;
    localparam STATE_DONE        = 2'd3;

    reg [1:0] state;
    reg [1:0] next_state;

    // FSM State Register
    always @(posedge clk) begin
        if (!rst_n)
            state <= STATE_IDLE;
        else
            state <= next_state;
    end

    // Next State Logic
    always @(*) begin
        casez ({state, start_i, layer_done_i, layer_index_o})
			// 전체 Start가 들어오면 첫 Layer 시작 상태로 이동
            {STATE_IDLE, 4'b1???}			:	next_state = STATE_START_LAYER;

			// Layer Start Pulse를 한 Clock만 발생시키고 대기 상태로 이동
            {STATE_START_LAYER, 4'b????}	:	 next_state = STATE_WAIT_LAYER;

			// Conv3 완료 시 전체 완료 상태로 이동
			{STATE_WAIT_LAYER, 4'b?110}		:	 next_state = STATE_DONE;

			// Conv1 또는 Conv2 완료 시 다음 Layer 시작
			{STATE_WAIT_LAYER, 4'b?10?}		:	 next_state = STATE_START_LAYER;
			
			// 전체 Done Pulse를 한 Clock 발생한 후 IDLE 복귀
			{STATE_DONE, 4'b????}			:	 next_state = STATE_IDLE;		
            default							:    next_state = state;
        endcase
    end

    // 현재 Layer 번호 관리
    // 전체 실행 시작 및 Layer 완료 조건에 따라 Layer 번호 갱신
    always @(posedge clk) begin
        if (!rst_n)
            layer_index_o <= 2'd0;
        else begin
            casez ({state, start_i, layer_done_i, layer_index_o})
                // 새로운 전체 실행은 항상 Conv1부터 시작
                {STATE_IDLE, 4'b1???}		:	layer_index_o <= 2'd0;

                // Conv1 또는 Conv2 완료 시 다음 Layer로 증가
                {STATE_WAIT_LAYER, 4'b?10?}	:	layer_index_o <= layer_index_o + 2'd1;
                default						:	layer_index_o <= layer_index_o;
            endcase
        end
    end

    // FSM 상태에 따른 Pulse 및 전체 실행 상태
    always @(*) begin
		case(state)
        // START_LAYER 상태에서만 Layer Start Pulse 발생
		STATE_START_LAYER	:	{layer_start_o, run_o, done_o} = 3'b110;

        // START_LAYER 또는 WAIT_LAYER이면 전체 실행 중
		STATE_WAIT_LAYER	:	{layer_start_o, run_o, done_o} = 3'b010;
	
        // DONE 상태에서만 전체 Done Pulse 발생
		STATE_DONE			:	{layer_start_o, run_o, done_o} = 3'b001;
		default				:	{layer_start_o, run_o, done_o} = 3'b000;
		endcase
    end

    // 현재 Layer 번호에 따른 고정 설정값 출력
        // 현재 Layer 번호에 따라 연산 크기, 주소 및 Feature Bank 경로 선택
    always @(*) begin
        case (layer_index_o)
            2'd0: begin
                // Conv1: 입력 영상 1채널을 64채널 특징으로 변환
                // Input Tile을 읽고 결과는 Feature Bank A에 저장
                out_channel_count_o       = 7'd64;
                in_channel_count_o        = 7'd1;
                output_size_o             = 6'd32;
                kernel_size_o             = 4'd9;
                pad_o                     = 4'd4;
                requant_shift_o           = 6'd14;

                // Conv1 Packed Weight와 Bias는 전체 메모리의 첫 주소부터 시작
                weight_word_base_addr_o   = 16'd0;
                bias_base_addr_o          = 16'd0;

                // 0=Input Tile, 0=Feature Bank A
                activation_source_o       = 2'd0;
                feature_write_bank_o      = 1'b0;
            end

            2'd1: begin
                // Conv2: Conv1의 64채널 특징을 32채널 특징으로 변환
                // Feature Bank A를 읽고 결과는 Feature Bank B에 저장
                out_channel_count_o       = 7'd32;
                in_channel_count_o        = 7'd64;
                output_size_o             = 6'd32;
                kernel_size_o             = 4'd5;
                pad_o                     = 4'd2;
                requant_shift_o           = 6'd16;

                // Conv1 Weight Word 1296개와 Bias 64개 다음부터 시작
                weight_word_base_addr_o   = 16'd1296;
                bias_base_addr_o          = 16'd64;

                // 1=Feature Bank A, 1=Feature Bank B
                activation_source_o       = 2'd1;
                feature_write_bank_o      = 1'b1;
            end

            2'd2: begin
                // Conv3: Conv2의 32채널 특징을 최종 출력 1채널로 변환
                // Feature Bank B를 읽고 최종 결과는 Feature Bank A에 저장
                out_channel_count_o       = 7'd1;
                in_channel_count_o        = 7'd32;
                output_size_o             = 6'd32;
                kernel_size_o             = 4'd5;
                pad_o                     = 4'd2;
                requant_shift_o           = 6'd14;

                // Conv1 1296개 + Conv2 12800개 다음 Weight 주소
                // Bias는 Conv1 64개 + Conv2 32개 다음 주소
                weight_word_base_addr_o   = 16'd14096;
                bias_base_addr_o          = 16'd96;

                // 2=Feature Bank B, 0=Feature Bank A
                // Conv1 결과는 더 이상 필요하지 않아 Bank A를 재사용
                activation_source_o       = 2'd2;
                feature_write_bank_o      = 1'b0;
            end

            default: begin
                // 잘못된 Layer 번호에서 연산하지 않도록 안전한 기본값 설정
				out_channel_count_o       = 7'd0;
				in_channel_count_o        = 7'd0;
				output_size_o             = 6'd0;
				kernel_size_o             = 4'd0;
				pad_o                     = 4'd0;
				requant_shift_o           = 6'd0;
				weight_word_base_addr_o   = 16'd0;
				bias_base_addr_o          = 16'd0;
				activation_source_o       = 2'd0;
				feature_write_bank_o      = 1'b0;
            end
        endcase
    end

endmodule
