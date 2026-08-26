`timescale 1ns / 1ps

module srcnn_npu_fixed_top #(
    // Bitstream에 포함할 고정 SRCNN Weight/Bias 초기화 파일
    parameter WEIGHT_INIT_FILE = "srcnn_weights_all.hex",
    parameter BIAS_INIT_FILE   = "srcnn_biases_all.hex"
) (
    input  wire clk,
    input  wire rst_n,

    // 전체 SRCNN 실행 시작 Pulse
    input  wire start_i,

    // 원본 32×32 Input Tile BRAM Read Data
    input  wire signed [15:0] input_tile_data_i,

    // Input Tile BRAM Read Interface
    output wire        input_tile_bram_en_o,
    output wire [15:0] input_tile_bram_addr_o,

    // 전체 연산 완료 후 Conv3 결과 Read Interface
    input  wire               final_read_en_i,
    input  wire        [15:0] final_read_addr_i,
    output wire signed [15:0] final_read_data_o,

    // 전체 SRCNN 상태
    output wire       run_o,
    output wire       done_o,
    output wire [1:0] layer_index_o,

    // 내부 Layer Memory 경로 확인용 출력
    output wire [1:0] activation_source_o,
    output wire       feature_write_bank_o
);

    // 기존 NPU가 생성하는 Packed Weight ROM Read Interface
    wire        weight_read_en_int;
    wire [15:0] weight_read_addr_int;
    wire [63:0] weight_read_data_int;

    // 기존 NPU가 생성하는 Bias ROM Read Interface
    wire               bias_read_en_int;
    wire        [15:0] bias_read_addr_int;
    wire signed [31:0] bias_read_data_int;

    // Conv1·Conv2·Conv3의 Packed Weight를 Bitstream에 포함하는 ROM
    srcnn_weight_rom #(
        .INIT_FILE(WEIGHT_INIT_FILE)
    ) u_srcnn_weight_rom (
        .clk        (clk),
        .rst_n      (rst_n),
        .read_en_i  (weight_read_en_int),
        .read_addr_i(weight_read_addr_int),
        .read_data_o(weight_read_data_int)
    );

    // Conv1·Conv2·Conv3의 Bias를 Bitstream에 포함하는 ROM
    srcnn_bias_rom #(
        .INIT_FILE(BIAS_INIT_FILE)
    ) u_srcnn_bias_rom (
        .clk        (clk),
        .rst_n      (rst_n),
        .read_en_i  (bias_read_en_int),
        .read_addr_i(bias_read_addr_int),
        .read_data_o(bias_read_data_int)
    );

    // 기존 검증 완료된 SRCNN 연산 Top은 수정하지 않고 그대로 재사용
    srcnn_npu_top u_srcnn_npu_top (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .start_i                (start_i),

        .input_tile_data_i      (input_tile_data_i),

        // 외부 테스트 메모리 대신 Bitstream 초기화 ROM 연결
        .weight_word_i          (weight_read_data_int),
        .bias_data_i            (bias_read_data_int),

        .input_tile_bram_en_o   (input_tile_bram_en_o),
        .input_tile_bram_addr_o (input_tile_bram_addr_o),

        .weight_bram_en_o       (weight_read_en_int),
        .weight_word_addr_o     (weight_read_addr_int),

        .bias_bram_en_o         (bias_read_en_int),
        .bias_bram_addr_o       (bias_read_addr_int),

        .final_read_en_i        (final_read_en_i),
        .final_read_addr_i      (final_read_addr_i),
        .final_read_data_o      (final_read_data_o),

        .run_o                  (run_o),
        .done_o                 (done_o),
        .layer_index_o          (layer_index_o),

        .activation_source_o    (activation_source_o),
        .feature_write_bank_o   (feature_write_bank_o)
    );

endmodule
