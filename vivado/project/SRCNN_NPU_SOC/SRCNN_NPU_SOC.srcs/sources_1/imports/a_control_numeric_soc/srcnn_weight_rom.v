`timescale 1ns / 1ps

module srcnn_weight_rom #(
    // Vivado Project에 Memory Initialization File로 추가할 파일명
    parameter INIT_FILE = "srcnn_weights_all.hex"
) (
    input  wire        clk,
    input  wire        rst_n,

    // 64-bit Packed Weight Read Interface
    input  wire        read_en_i,
    input  wire [15:0] read_addr_i,

    output reg  [63:0] read_data_o
);

    localparam WEIGHT_WORD_COUNT = 14896;

    // Conv1 1296 + Conv2 12800 + Conv3 800개의 Packed Weight
    // Block ROM 지시문을 사용해 RAMB36 기반 ROM으로 합성
    (* rom_style = "block" *)
    reg [63:0] weight_mem [0:WEIGHT_WORD_COUNT-1];

    // Bitstream 생성 시 Weight 초기값을 Block RAM에 포함
    initial begin
        $readmemh(INIT_FILE, weight_mem);
    end

    // 현재 NPU 테스트벤치와 동일한 1-Clock Read Latency
    // read_en_i가 0이면 마지막 출력값 유지
    always @(posedge clk) begin
        if (!rst_n)
            read_data_o <= 64'd0;
        else if (read_en_i)
            read_data_o <= weight_mem[read_addr_i];
    end

endmodule
