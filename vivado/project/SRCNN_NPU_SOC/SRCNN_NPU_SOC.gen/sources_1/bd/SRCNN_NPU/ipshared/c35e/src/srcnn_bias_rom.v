`timescale 1ns / 1ps

module srcnn_bias_rom #(
    // Vivado Project에 Memory Initialization File로 추가할 파일명
    parameter INIT_FILE = "srcnn_biases_all.hex"
) (
    input  wire clk,
    input  wire rst_n,

    // signed INT32 Bias Read Interface
    input  wire               read_en_i,
    input  wire        [15:0] read_addr_i,

    output reg  signed [31:0] read_data_o
);

    localparam BIAS_WORD_COUNT = 97;

    // Conv1 64 + Conv2 32 + Conv3 1개의 signed INT32 Bias
    // 동기식 Block ROM으로 합성해 Bitstream에 초기값 포함
    (* rom_style = "block" *)
    reg signed [31:0] bias_mem [0:BIAS_WORD_COUNT-1];

    initial begin
        $readmemh(INIT_FILE, bias_mem);
    end

    // Bias Loader의 REQUEST→CAPTURE 동작과 맞춘 1-Clock Read Latency
    // read_en_i가 0이면 마지막 출력값 유지
    always @(posedge clk) begin
        if (!rst_n)
            read_data_o <= 32'sd0;
        else if (read_en_i)
            read_data_o <= bias_mem[read_addr_i];
    end

endmodule
