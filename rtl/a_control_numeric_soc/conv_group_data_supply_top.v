`timescale 1ns / 1ps

module conv_group_data_supply_top (
    input  wire clk,
    input  wire rst_n,

    // 전체 Layer 연산 시작
    input  wire start_i,

    // B파트 Compute Core 상태
    input  wire core_busy_i,
    input  wire core_done_i,

    // 현재 Layer 설정
    input  wire [6:0]  out_channel_count_i,
    input  wire [6:0]  in_channel_count_i,
    input  wire [5:0]  output_size_i,
    input  wire [3:0]  kernel_size_i,
    input  wire [3:0]  pad_i,
    input  wire [15:0] weight_word_base_addr_i,
    input  wire [15:0] bias_base_addr_i,

    // BRAM에서 읽은 데이터
    input  wire signed [15:0] activation_bram_data_i,
    input  wire        [63:0] weight_word_i,
    input  wire signed [31:0] bias_bram_data_i,

    // 전체 Controller 상태
    output wire        run_o,
    output wire        done_o,
    output wire        last_index_o,

    // 현재 Group 및 내부 MAC 좌표
    output wire [6:0]  out_channel_group_count_o,
    output wire [5:0]  out_channel_group_o,
    output wire [5:0]  in_channel_o,
    output wire [4:0]  out_y_o,
    output wire [4:0]  out_x_o,
    output wire [3:0]  kernel_y_o,
    output wire [3:0]  kernel_x_o,

    // Activation BRAM Interface
    output wire        activation_bram_en_o,
    output wire [15:0] activation_bram_addr_o,
    output wire        padding_o,

    // Packed Weight BRAM Interface
    output wire        weight_bram_en_o,
    output wire [15:0] weight_word_addr_o,

    // Bias BRAM Interface
    output wire        bias_bram_en_o,
    output wire [15:0] bias_bram_addr_o,

    // B파트 제어 신호
    output wire        op_start_o,
    output wire        bias_load_o,
    output wire        mac_valid_o,
    output wire        mac_last_o,

    // B파트 PE Enable
    output wire [3:0]  pe_enable_o,

    // B파트 Activation 및 Weight 입력
    output wire signed [15:0] activation_o,
    output wire signed [15:0] weight_pe0_o,
    output wire signed [15:0] weight_pe1_o,
    output wire signed [15:0] weight_pe2_o,
    output wire signed [15:0] weight_pe3_o,

    // B파트 Bias 입력
    output wire signed [31:0] bias_pe0_o,
    output wire signed [31:0] bias_pe1_o,
    output wire signed [31:0] bias_pe2_o,
    output wire signed [31:0] bias_pe3_o
);

    // MAC 처리 시 Index Counter를 한 좌표 증가
    wire advance_int;

    // Bias Loader 시작 Pulse
    wire bias_fetch_start_int;

    // Activation/Weight BRAM 동시 읽기 Enable
    wire data_read_en_int;

    // Bias Loader가 Bias 네 개를 준비했음을 알리는 Pulse
    wire bias_ready_int;

    // Bias Loader 동작 상태
    wire bias_busy_int;

    // 현재 Group 좌표로 계산한 PE Enable
    wire [3:0] pe_enable_comb;

    // B파트 결과가 나올 때까지 유지할 PE Enable
    reg  [3:0] pe_enable_reg;

    // 실제 Output Channel을 4-PE Group 단위로 순회
    conv_group_loop_controller u_conv_group_loop_controller (
        // Input Port
        .clk                      (clk),
        .rst_n                    (rst_n),
        .start_i                  (start_i),
        .advance_i                (advance_int),
        .out_channel_count_i      (out_channel_count_i),
        .in_channel_count_i       (in_channel_count_i),
        .output_size_i            (output_size_i),
        .kernel_size_i            (kernel_size_i),

        // Output Port
        .run_o                    (run_o),
        .done_o                   (done_o),
        .last_index_o             (last_index_o),
        .out_channel_group_count_o(out_channel_group_count_o),
        .out_channel_group_o      (out_channel_group_o),
        .in_channel_o             (in_channel_o),
        .out_y_o                  (out_y_o),
        .out_x_o                  (out_x_o),
        .kernel_y_o               (kernel_y_o),
        .kernel_x_o               (kernel_x_o)
    );

    // Bias 준비와 BRAM Read, MAC 공급 순서를 관리
    conv_mac_feed_controller u_conv_mac_feed_controller (
        // Input Port
        .clk               (clk),
        .rst_n             (rst_n),
        .run_i             (run_o),
        .core_busy_i       (core_busy_i),
        .core_done_i       (core_done_i),
        .bias_ready_i      (bias_ready_int),
        .in_channel_i      (in_channel_o),
        .in_channel_count_i(in_channel_count_i),
        .kernel_y_i        (kernel_y_o),
        .kernel_x_i        (kernel_x_o),
        .kernel_size_i     (kernel_size_i),

        // Output Port
        .op_start_o        (op_start_o),
        .bias_load_o       (bias_load_o),
        .mac_valid_o       (mac_valid_o),
        .mac_last_o        (mac_last_o),
        .bias_fetch_start_o(bias_fetch_start_int),
        .data_read_en_o    (data_read_en_int),
        .advance_o         (advance_int)
    );

    // 현재 MAC 좌표로 Activation 주소와 Padding 여부를 계산
    activation_addr_gen u_activation_addr_gen (
        // Input Port
        .channel_i         (in_channel_o),
        .out_y_i           (out_y_o),
        .out_x_i           (out_x_o),
        .kernel_y_i        (kernel_y_o),
        .kernel_x_i        (kernel_x_o),
        .pad_i             (pad_i),
        // Output Port
        .padding_o         (padding_o),
        .activation_addr_o (activation_bram_addr_o)
    );

     // 64-bit Weight Word를 읽고 PE0~PE3의 INT16 Weight로 분리
    packed_weight_supply u_packed_weight_supply (
        // Input Port
        .out_channel_group_i    (out_channel_group_o),
        .out_channel_count_i    (out_channel_count_i),
        .in_channel_i           (in_channel_o),
        .in_channel_count_i     (in_channel_count_i),
        .kernel_y_i             (kernel_y_o),
        .kernel_x_i             (kernel_x_o),
        .kernel_size_i          (kernel_size_i),
        .weight_word_base_addr_i(weight_word_base_addr_i),
        .weight_word_i          (weight_word_i),
        // Output Port
        .weight_word_addr_o     (weight_word_addr_o),
        .pe_enable_o            (pe_enable_comb),
        .weight_pe0_o           (weight_pe0_o),
        .weight_pe1_o           (weight_pe1_o),
        .weight_pe2_o           (weight_pe2_o),
        .weight_pe3_o           (weight_pe3_o)
    );

    // 현재 Output Channel Group에 필요한 Bias를 순서대로 읽어 저장
    bias_group_loader u_bias_group_loader (
        // Input Port
        .clk                (clk),
        .rst_n              (rst_n),
        .start_i            (bias_fetch_start_int),
        .out_channel_group_i(out_channel_group_o),
        .bias_base_addr_i   (bias_base_addr_i),
        .pe_enable_i        (pe_enable_comb),
        .bias_bram_data_i   (bias_bram_data_i),
        // Output Port
        .bias_bram_en_o     (bias_bram_en_o),
        .bias_bram_addr_o   (bias_bram_addr_o),
        .bias_pe0_o         (bias_pe0_o),
        .bias_pe1_o         (bias_pe1_o),
        .bias_pe2_o         (bias_pe2_o),
        .bias_pe3_o         (bias_pe3_o),
        .busy_o             (bias_busy_int),
        .bias_ready_o       (bias_ready_int)
    );

    // MAC Feed Controller의 READ 상태에서 Activation과 Weight BRAM을 함께 읽음
    // 두 BRAM Enable에 공통 내부 Read Enable 연결
    assign activation_bram_en_o = data_read_en_int;
    assign weight_bram_en_o     = data_read_en_int;

    // Padding 좌표는 BRAM 데이터 대신 signed 16-bit 0을 B파트에 전달
    // padding_o가 1이면 0, 아니면 activation_bram_data_i 선택
    assign activation_o = padding_o? 16'sd0: activation_bram_data_i;

    // 연산 시작 시 저장한 PE Mask를 B파트에 전달
    // 유지 레지스터를 최종 출력에 연결
    assign pe_enable_o = pe_enable_reg;

    // B파트 결과가 나올 때까지 현재 Group의 PE Mask를 유지
    always @(posedge clk) begin
        if (!rst_n)
            // 동기식 Reset에서 모든 PE 비활성화
            pe_enable_reg <= 4'b0000;
        else if (op_start_o)
            // 새로운 Output Pixel 연산 시작 시 현재 PE Mask 저장
            pe_enable_reg <= pe_enable_comb;
    end

endmodule
