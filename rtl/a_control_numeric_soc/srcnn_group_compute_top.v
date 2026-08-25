`timescale 1ns / 1ps

module srcnn_group_compute_top (
    input  wire clk,
    input  wire rst_n,
    input  wire start_i,

    // 현재 Layer 설정
    input  wire [6:0]  out_channel_count_i,
    input  wire [6:0]  in_channel_count_i,
    input  wire [5:0]  output_size_i,
    input  wire [3:0]  kernel_size_i,
    input  wire [3:0]  pad_i,
    input  wire [15:0] weight_word_base_addr_i,
    input  wire [15:0] bias_base_addr_i,

	// Layer별 Requant Right Shift 크기
    input  wire [5:0] requant_shift_i,

    // BRAM Read Data
    input  wire signed [15:0] activation_bram_data_i,
    input  wire        [63:0] weight_word_i,
    input  wire signed [31:0] bias_bram_data_i,

    // Activation BRAM
    output wire        activation_bram_en_o,
    output wire [15:0] activation_bram_addr_o,

    // Weight BRAM
    output wire        weight_bram_en_o,
    output wire [15:0] weight_word_addr_o,

    // Bias BRAM
    output wire        bias_bram_en_o,
    output wire [15:0] bias_bram_addr_o,

    // 전체 Layer 상태
    output wire run_o,
    output wire done_o,

    // B파트 INT48 결과
    output wire signed [47:0] accumulator0_o,
    output wire signed [47:0] accumulator1_o,
    output wire signed [47:0] accumulator2_o,
    output wire signed [47:0] accumulator3_o,
    output wire               acc_valid_o,

	// Requant, ReLU 및 INT16 Saturation 결과
    output wire signed [15:0] requant_pe0_o,
    output wire signed [15:0] requant_pe1_o,
    output wire signed [15:0] requant_pe2_o,
    output wire signed [15:0] requant_pe3_o,
    output wire               requant_valid_o,

    // acc_valid_o와 함께 유효한 결과 위치
    output wire [5:0] result_out_channel_group_o,
    output wire [4:0] result_y_o,
    output wire [4:0] result_x_o,
    output wire [3:0] result_pe_enable_o
);

    // A파트에서 B파트로 전달하는 제어 신호
    wire op_start_int;
    wire bias_load_int;
    wire mac_valid_int;
    wire mac_last_int;

    // A파트가 관찰하는 B파트 상태
    wire core_busy_int;
    wire core_done_int;

    // A파트가 생성하는 현재 연산 좌표
    wire [5:0] out_channel_group_int;
    wire [5:0] in_channel_int;
    wire [4:0] out_y_int;
    wire [4:0] out_x_int;
    wire [3:0] kernel_y_int;
    wire [3:0] kernel_x_int;

    wire [6:0] out_channel_group_count_int;
    wire       last_index_int;
    wire       padding_int;

    // A파트에서 B파트로 전달하는 PE Mask
    wire [3:0] pe_enable_int;

    // A파트에서 B파트로 전달하는 연산 데이터
    wire signed [15:0] activation_int;
    wire signed [15:0] weight_pe0_int;
    wire signed [15:0] weight_pe1_int;
    wire signed [15:0] weight_pe2_int;
    wire signed [15:0] weight_pe3_int;

    wire signed [31:0] bias_pe0_int;
    wire signed [31:0] bias_pe1_int;
    wire signed [31:0] bias_pe2_int;
    wire signed [31:0] bias_pe3_int;

	// Mask 적용 전 PE별 Requant 결과
    wire signed [15:0] requant_pe0_int;
    wire signed [15:0] requant_pe1_int;
    wire signed [15:0] requant_pe2_int;
    wire signed [15:0] requant_pe3_int;

    // 결과가 나올 때까지 유지할 Output 위치와 PE Mask
    reg [5:0] result_out_channel_group_reg;
    reg [4:0] result_y_reg;
    reg [4:0] result_x_reg;
    reg [3:0] result_pe_enable_reg;

    // BRAM 주소·데이터와 전체 합성곱 순서를 관리하는 A파트
    conv_group_data_supply_top u_conv_group_data_supply_top (
		// Input Port
        // Clock / Reset / Start
        .clk                      (clk),
        .rst_n                    (rst_n),
        .start_i                  (start_i),

        // B파트의 Busy와 Done 내부 신호
        .core_busy_i              (core_busy_int),
        .core_done_i              (core_done_int),

        // Layer 설정
        .out_channel_count_i      (out_channel_count_i),
        .in_channel_count_i       (in_channel_count_i),
        .output_size_i            (output_size_i),
        .kernel_size_i            (kernel_size_i),
        .pad_i                    (pad_i),
        .weight_word_base_addr_i  (weight_word_base_addr_i),
        .bias_base_addr_i         (bias_base_addr_i),

        // 외부 BRAM Read Data
        .activation_bram_data_i   (activation_bram_data_i),
        .weight_word_i            (weight_word_i),
        .bias_bram_data_i         (bias_bram_data_i),
		// Output Port

        // 전체 Layer 상태
        .run_o                    (run_o),
        .done_o                   (done_o),
        .last_index_o             (last_index_int),

        // 현재 Group과 MAC 좌표 내부 신호
        .out_channel_group_count_o(out_channel_group_count_int),
        .out_channel_group_o      (out_channel_group_int),
        .in_channel_o             (in_channel_int),
        .out_y_o                  (out_y_int),
        .out_x_o                  (out_x_int),
        .kernel_y_o               (kernel_y_int),
        .kernel_x_o               (kernel_x_int),

        // 외부 Activation BRAM
        .activation_bram_en_o     (activation_bram_en_o),
        .activation_bram_addr_o   (activation_bram_addr_o),
        .padding_o                (padding_int),

        // 외부 Packed Weight BRAM
        .weight_bram_en_o         (weight_bram_en_o),
        .weight_word_addr_o       (weight_word_addr_o),

        // 외부 Bias BRAM
        .bias_bram_en_o           (bias_bram_en_o),
        .bias_bram_addr_o         (bias_bram_addr_o),

        // B파트 제어 내부 신호
        .op_start_o               (op_start_int),
        .bias_load_o              (bias_load_int),
        .mac_valid_o              (mac_valid_int),
        .mac_last_o               (mac_last_int),

        // B파트 PE Mask 내부 신호
        .pe_enable_o              (pe_enable_int),

        // Activation과 PE별 Weight 내부 신호
        .activation_o             (activation_int),
        .weight_pe0_o             (weight_pe0_int),
        .weight_pe1_o             (weight_pe1_int),
        .weight_pe2_o             (weight_pe2_int),
        .weight_pe3_o             (weight_pe3_int),

        // PE별 Bias 내부 신호
        .bias_pe0_o               (bias_pe0_int),
        .bias_pe1_o               (bias_pe1_int),
        .bias_pe2_o               (bias_pe2_int),
        .bias_pe3_o               (bias_pe3_int)
    );

    // A파트가 공급한 데이터로 4개 Output Channel을 병렬 연산
    srcnn_compute_core u_srcnn_compute_core (
		// Input Port
        // Clock / Reset
        .clk            (clk),
        .rst_n          (rst_n),

        // A파트가 생성한 연산 제어 신호
        .op_start       (op_start_int),
        .bias_load      (bias_load_int),
        .mac_valid      (mac_valid_int),
        .mac_last       (mac_last_int),

        // 현재 Output Channel Group의 PE Mask
        .pe_enable      (pe_enable_int),

        // 공통 Activation
        .activation     (activation_int),

        // PE0~PE3 Weight
        .weight0        (weight_pe0_int),
        .weight1        (weight_pe1_int),
        .weight2        (weight_pe2_int),
        .weight3        (weight_pe3_int),

        // PE0~PE3 Bias
        .bias0          (bias_pe0_int),
        .bias1          (bias_pe1_int),
        .bias2          (bias_pe2_int),
        .bias3          (bias_pe3_int),

		// Output Port
        // PE0~PE3 INT48 누산 결과를 외부 출력에 연결
        .accumulator0   (accumulator0_o),
        .accumulator1   (accumulator1_o),
        .accumulator2   (accumulator2_o),
        .accumulator3   (accumulator3_o),

        // B파트 상태를 A파트 및 외부 출력에 연결
        .busy           (core_busy_int),
        .acc_valid      (acc_valid_o),
        .core_done      (core_done_int)
    );

	// PE0 INT48 결과를 Layer 설정에 맞춰 INT16으로 후처리
    requant_relu	u_requant_relu_pe0 (
		// Input Port
		.acc_i(accumulator0_o),
		.shift_i(requant_shift_i),
		// Oupput Port
		.data_o(requant_pe0_int)
    );

	// PE1 INT48 결과를 Layer 설정에 맞춰 INT16으로 후처리
    requant_relu	u_requant_relu_pe1 (
		// Input Port
		.acc_i(accumulator1_o),
		.shift_i(requant_shift_i),
		// Oupput Port
		.data_o(requant_pe1_int)
    );

	// PE2 INT48 결과를 Layer 설정에 맞춰 INT16으로 후처리
    requant_relu	u_requant_relu_pe2 (
		// Input Port
		.acc_i(accumulator2_o),
		.shift_i(requant_shift_i),
		// Oupput Port
		.data_o(requant_pe2_int)
    );

	// PE3 INT48 결과를 Layer 설정에 맞춰 INT16으로 후처리
    requant_relu	u_requant_relu_pe3 (
		// Input Port
		.acc_i(accumulator3_o),
		.shift_i(requant_shift_i),
		// Oupput Port
		.data_o(requant_pe3_int)
    );

	// 비활성 PE는 이전 연산값이 외부로 전달되지 않도록 0으로 Mask
	// 저장된 결과 PE Mask의 각 비트로 내부 Requant 결과 선택
    assign requant_pe0_o = result_pe_enable_reg[0]? requant_pe0_int: 16'sd0;
    assign requant_pe1_o = result_pe_enable_reg[1]? requant_pe1_int: 16'sd0;
    assign requant_pe2_o = result_pe_enable_reg[2]? requant_pe2_int: 16'sd0;
    assign requant_pe3_o = result_pe_enable_reg[3]? requant_pe3_int: 16'sd0;
	
	// Requant는 조합논리이므로 INT48 결과와 같은 Cycle에 유효
	// B파트 결과 Valid를 Requant 결과 Valid로 전달
    assign requant_valid_o = acc_valid_o;

    // Bias Load 시점의 Output 위치와 PE Mask를 결과 완료까지 유지
    always @(posedge clk) begin
        if (!rst_n) begin
            result_out_channel_group_reg <= 6'd0;
            result_y_reg                 <= 5'd0;
            result_x_reg                 <= 5'd0;
            result_pe_enable_reg         <= 4'b0000;
        end
        else if (bias_load_int) begin
            result_out_channel_group_reg <= out_channel_group_int;
            result_y_reg                 <= out_y_int;
            result_x_reg                 <= out_x_int;
            result_pe_enable_reg         <= pe_enable_int;
        end
    end

    // 저장된 위치를 INT48 결과와 함께 외부에 전달
    assign result_out_channel_group_o = result_out_channel_group_reg;
    assign result_y_o                 = result_y_reg;
    assign result_x_o                 = result_x_reg;
    assign result_pe_enable_o         = result_pe_enable_reg;

endmodule
