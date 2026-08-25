`timescale 1ns / 1ps

module srcnn_npu_top (
    input  wire clk,
    input  wire rst_n,

    // 전체 SRCNN 실행 시작 Pulse
    input  wire start_i,

    // 원본 32×32 Input Tile BRAM Read Data
    input  wire signed [15:0] input_tile_data_i,

    // 전체 Layer의 Packed Weight와 Bias Memory Read Data
    input  wire        [63:0] weight_word_i,
    input  wire signed [31:0] bias_data_i,

    // Input Tile BRAM Read Interface
    output wire        input_tile_bram_en_o,
    output wire [15:0] input_tile_bram_addr_o,

    // Packed Weight BRAM Read Interface
    output wire        weight_bram_en_o,
    output wire [15:0] weight_word_addr_o,

    // Bias BRAM Read Interface
    output wire        bias_bram_en_o,
    output wire [15:0] bias_bram_addr_o,

    // 전체 연산 완료 후 Feature Bank A의 Conv3 결과 Read Interface
    input  wire               final_read_en_i,
    input  wire        [15:0] final_read_addr_i,
    output wire signed [15:0] final_read_data_o,

    // 전체 SRCNN 상태
    output wire       run_o,
    output wire       done_o,
    output wire [1:0] layer_index_o,

    // 현재 내부 Memory 경로 확인용 출력
    output wire [1:0] activation_source_o,
    output wire       feature_write_bank_o
);

    // Layer Controller가 생성하는 Layer 시작 및 전체 실행 상태
    wire layer_start_int;
    wire network_run_int;
    wire network_done_int;

    // 현재 Layer 연산 설정
    wire [6:0]  out_channel_count_int;
    wire [6:0]  in_channel_count_int;
    wire [5:0]  output_size_int;
    wire [3:0]  kernel_size_int;
    wire [3:0]  pad_int;
    wire [5:0]  requant_shift_int;
    wire [15:0] weight_word_base_addr_int;
    wire [15:0] bias_base_addr_int;

    // 현재 Activation 입력과 결과 저장 Bank 선택
    wire [1:0] activation_source_int;
    wire       feature_write_bank_int;

    // 현재 Layer Compute 상태
    wire compute_run_int;
    wire compute_done_int;

    // Group Compute가 요청하는 Activation Read Interface
    wire        compute_activation_en_int;
    wire [15:0] compute_activation_addr_int;
    reg signed [15:0] compute_activation_data_int;

    // Compute Core의 PE별 INT48 결과
    wire signed [47:0] accumulator0_int;
    wire signed [47:0] accumulator1_int;
    wire signed [47:0] accumulator2_int;
    wire signed [47:0] accumulator3_int;
    wire               acc_valid_int;

    // Requant 및 ReLU 후 PE별 INT16 결과
    wire signed [15:0] requant_pe0_int;
    wire signed [15:0] requant_pe1_int;
    wire signed [15:0] requant_pe2_int;
    wire signed [15:0] requant_pe3_int;
    wire               requant_valid_int;

    // Requant 결과와 함께 유효한 Output 위치
    wire [5:0] result_group_int;
    wire [4:0] result_y_int;
    wire [4:0] result_x_int;
    wire [3:0] result_pe_enable_int;

    // Feature Bank A Read Interface
    wire               bank_a_read_en_int;
    wire        [15:0] bank_a_read_addr_int;
    wire signed [15:0] bank_a_read_data_int;

    // Feature Bank B Read Interface
    wire               bank_b_read_en_int;
    wire        [15:0] bank_b_read_addr_int;
    wire signed [15:0] bank_b_read_data_int;

    // Requant 결과의 Feature Bank별 Write Enable
    wire bank_a_write_valid_int;
    wire bank_b_write_valid_int;

    // Conv1 → Conv2 → Conv3 실행 순서와 고정 설정값 관리
    srcnn_layer_controller u_srcnn_layer_controller (
        // Input Port
        .clk                    (clk),
        .rst_n                  (rst_n),
        .start_i                (start_i),
        .layer_done_i           (compute_done_int),

        // Output Port
        .layer_start_o          (layer_start_int),
        .run_o                  (network_run_int),
        .done_o                 (network_done_int),
        .layer_index_o          (layer_index_o),

        .out_channel_count_o    (out_channel_count_int),
        .in_channel_count_o     (in_channel_count_int),
        .output_size_o          (output_size_int),
        .kernel_size_o          (kernel_size_int),
        .pad_o                  (pad_int),
        .requant_shift_o        (requant_shift_int),
        .weight_word_base_addr_o(weight_word_base_addr_int),
        .bias_base_addr_o       (bias_base_addr_int),

        .activation_source_o    (activation_source_int),
        .feature_write_bank_o   (feature_write_bank_int)
    );

    // A파트 주소 제어, B파트 MAC 및 PE4 Requant를 통합한 Layer 연산기
    srcnn_group_compute_top u_srcnn_group_compute_top (
        // Input Port
        .clk                      (clk),
        .rst_n                    (rst_n),
        .start_i                  (layer_start_int),

        .out_channel_count_i      (out_channel_count_int),
        .in_channel_count_i       (in_channel_count_int),
        .output_size_i            (output_size_int),
        .kernel_size_i            (kernel_size_int),
        .pad_i                    (pad_int),
        .weight_word_base_addr_i  (weight_word_base_addr_int),
        .bias_base_addr_i         (bias_base_addr_int),
        .requant_shift_i          (requant_shift_int),

        .activation_bram_data_i   (compute_activation_data_int),
        .weight_word_i            (weight_word_i),
        .bias_bram_data_i         (bias_data_i),

        // Output Port
        .activation_bram_en_o     (compute_activation_en_int),
        .activation_bram_addr_o   (compute_activation_addr_int),

        .weight_bram_en_o         (weight_bram_en_o),
        .weight_word_addr_o       (weight_word_addr_o),

        .bias_bram_en_o           (bias_bram_en_o),
        .bias_bram_addr_o         (bias_bram_addr_o),

        .run_o                    (compute_run_int),
        .done_o                   (compute_done_int),

        .accumulator0_o           (accumulator0_int),
        .accumulator1_o           (accumulator1_int),
        .accumulator2_o           (accumulator2_int),
        .accumulator3_o           (accumulator3_int),
        .acc_valid_o              (acc_valid_int),

        .requant_pe0_o            (requant_pe0_int),
        .requant_pe1_o            (requant_pe1_int),
        .requant_pe2_o            (requant_pe2_int),
        .requant_pe3_o            (requant_pe3_int),
        .requant_valid_o          (requant_valid_int),

        .result_out_channel_group_o(result_group_int),
        .result_y_o                (result_y_int),
        .result_x_o                (result_x_int),
        .result_pe_enable_o        (result_pe_enable_int)
    );

    // Conv1 결과를 저장하고 Conv2 입력으로 공급
    // Conv3 완료 후 최종 결과도 다시 Bank A에 저장
    feature_map_bank4 u_feature_map_bank_a (
        // Input Port
        .clk              (clk),
        .rst_n            (rst_n),

        .write_valid_i    (bank_a_write_valid_int),
        .write_pe_enable_i(result_pe_enable_int),
        .write_group_i    (result_group_int),
        .write_y_i        (result_y_int),
        .write_x_i        (result_x_int),

        .write_data0_i    (requant_pe0_int),
        .write_data1_i    (requant_pe1_int),
        .write_data2_i    (requant_pe2_int),
        .write_data3_i    (requant_pe3_int),

        .read_en_i        (bank_a_read_en_int),
        .read_addr_i      (bank_a_read_addr_int),

        // Output Port
        .read_data_o      (bank_a_read_data_int)
    );

    // Conv2 결과를 저장하고 Conv3 입력으로 공급
    feature_map_bank4 u_feature_map_bank_b (
        // Input Port
        .clk              (clk),
        .rst_n            (rst_n),

        .write_valid_i    (bank_b_write_valid_int),
        .write_pe_enable_i(result_pe_enable_int),
        .write_group_i    (result_group_int),
        .write_y_i        (result_y_int),
        .write_x_i        (result_x_int),

        .write_data0_i    (requant_pe0_int),
        .write_data1_i    (requant_pe1_int),
        .write_data2_i    (requant_pe2_int),
        .write_data3_i    (requant_pe3_int),

        .read_en_i        (bank_b_read_en_int),
        .read_addr_i      (bank_b_read_addr_int),

        // Output Port
        .read_data_o      (bank_b_read_data_int)
    );

    // Conv1에서만 외부 Input Tile BRAM을 활성화
    assign input_tile_bram_en_o =
        (activation_source_int == 2'd0) &&
        compute_activation_en_int;

    // Compute가 생성한 Activation 주소를 Input Tile BRAM으로 전달
    assign input_tile_bram_addr_o = compute_activation_addr_int;

    // Conv2 실행 중에는 Compute가 Feature Bank A를 읽음
    // 전체 연산이 끝난 뒤에는 외부 Final Read가 Bank A를 읽음
    assign bank_a_read_en_int =
        ((activation_source_int == 2'd1) &&
         compute_activation_en_int) ?
        1'b1 :
        ((!network_run_int) ? final_read_en_i : 1'b0);

    // Conv2 실행 중에는 Compute 주소, 완료 후에는 외부 Read 주소 선택
    assign bank_a_read_addr_int =
        ((activation_source_int == 2'd1) &&
         compute_activation_en_int) ?
        compute_activation_addr_int :
        final_read_addr_i;

    // Conv3에서만 Feature Bank B를 Activation으로 읽음
    assign bank_b_read_en_int =
        (activation_source_int == 2'd2) &&
        compute_activation_en_int;

    assign bank_b_read_addr_int = compute_activation_addr_int;

    // Layer에 따라 Input Tile, Feature Bank A, Feature Bank B 중 하나 선택
    always @(*) begin
        case (activation_source_int)
            // Conv1 Activation
            2'd0:
                compute_activation_data_int = input_tile_data_i;

            // Conv2 Activation
            2'd1:
                compute_activation_data_int = bank_a_read_data_int;

            // Conv3 Activation
            2'd2:
                compute_activation_data_int = bank_b_read_data_int;

            // 잘못된 Source에서는 signed 0 전달
            default:
                compute_activation_data_int = 16'sd0;
        endcase
    end

    // Conv1과 Conv3 결과는 Feature Bank A에 저장
    assign bank_a_write_valid_int =
        requant_valid_int &&
        (feature_write_bank_int == 1'b0);

    // Conv2 결과는 Feature Bank B에 저장
    assign bank_b_write_valid_int =
        requant_valid_int &&
        (feature_write_bank_int == 1'b1);

    // 전체 SRCNN 완료 후 Bank A의 Conv3 INT16 결과를 외부로 전달
    assign final_read_data_o = bank_a_read_data_int;

    // 내부 Layer Controller 상태를 최상위 출력으로 전달
    assign run_o                = network_run_int;
    assign done_o               = network_done_int;
    assign activation_source_o  = activation_source_int;
    assign feature_write_bank_o = feature_write_bank_int;

endmodule
