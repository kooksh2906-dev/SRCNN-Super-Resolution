`timescale 1ns / 1ps

module weight_addr_gen (
    input  wire [5:0]  out_channel_i,
    input  wire [5:0]  in_channel_i,

    // 현재 Layer의 전체 Input Channel 개수
    // 64를 표현해야 하므로 7-bit
    input  wire [6:0]  in_channel_count_i,

    input  wire [3:0]  kernel_y_i,
    input  wire [3:0]  kernel_x_i,
    input  wire [3:0]  kernel_size_i,

    // 현재 Layer의 Weight가 시작되는 주소
    input  wire [15:0] weight_base_addr_i,

    output reg  [15:0] weight_addr_o
);

    // 계산 도중 비트가 잘리지 않도록 32-bit 중간값 사용
    reg [31:0] addr_step0;
    reg [31:0] addr_step1;
    reg [31:0] addr_step2;
    reg [31:0] addr_step3;

    // Clock과 Reset이 필요 없는 순수 조합논리
    always @(*) begin
        // Latch 방지를 위한 기본값
        addr_step0   = 32'd0;
        addr_step1   = 32'd0;
        addr_step2   = 32'd0;
        addr_step3   = 32'd0;
        weight_addr_o = 16'd0;

        // 첫 번째 값은 Output Channel
        addr_step0 = {26'd0, out_channel_i};

        // TODO 1:
        // addr_step1 =
        //     addr_step0 × in_channel_count_i
        //     + in_channel_i
		addr_step1 = (addr_step0 * in_channel_count_i) + in_channel_i;

        // TODO 2:
        // addr_step2 =
        //     addr_step1 × kernel_size_i
        //     + kernel_y_i
		addr_step2 = (addr_step1 * kernel_size_i) + kernel_y_i;

        // TODO 3:
        // addr_step3 =
        //     addr_step2 × kernel_size_i
        //     + kernel_x_i
		addr_step3 = (addr_step2 * kernel_size_i) + kernel_x_i;

        // TODO 4:
        // 최종 주소 =
        //     weight_base_addr_i
        //     + addr_step3의 하위 16-bit
		weight_addr_o = weight_base_addr_i + addr_step3[15:0];
    end

endmodule
