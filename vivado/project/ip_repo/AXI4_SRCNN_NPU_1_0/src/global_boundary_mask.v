`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// 256x256 전체 영상 기준 Global Boundary Mask
//
// PC는 16x16 유효 영역 주변에 Halo 8을 붙인 32x32 Tile을 전송한다.
// Local 좌표의 Global 좌표는 다음과 같다.
//
//   global_x = tile_x * 16 + local_x - 8
//   global_y = tile_y * 16 + local_y - 8
//
// Conv1/Conv2 Requant 및 ReLU 결과 중 전체 영상 밖의 위치는 Bias 때문에
// 0이 아닐 수 있으므로 Feature Map BRAM에 명시적으로 0을 저장한다.
// Conv3에서는 mask_enable_i를 0으로 두어 결과를 그대로 통과시킨다.
//------------------------------------------------------------------------------
module global_boundary_mask (
    input  wire       mask_enable_i,
    input  wire [3:0] tile_x_i,
    input  wire [3:0] tile_y_i,
    input  wire [4:0] local_x_i,
    input  wire [4:0] local_y_i,

    input  wire signed [15:0] data0_i,
    input  wire signed [15:0] data1_i,
    input  wire signed [15:0] data2_i,
    input  wire signed [15:0] data3_i,

    output wire               inside_image_o,
    output wire signed [15:0] data0_o,
    output wire signed [15:0] data1_o,
    output wire signed [15:0] data2_o,
    output wire signed [15:0] data3_o
);

    wire x_inside;
    wire y_inside;
    wire force_zero;

    // 첫 Tile은 왼쪽 Halo 8칸, 마지막 Tile은 오른쪽 Halo 8칸 제외
    assign x_inside = ((tile_x_i != 4'd0)  || (local_x_i >= 5'd8)) &&
                      ((tile_x_i != 4'd15) || (local_x_i <= 5'd23));

    // 첫 Tile은 위쪽 Halo 8칸, 마지막 Tile은 아래쪽 Halo 8칸 제외
    assign y_inside = ((tile_y_i != 4'd0)  || (local_y_i >= 5'd8)) &&
                      ((tile_y_i != 4'd15) || (local_y_i <= 5'd23));

    assign inside_image_o = x_inside && y_inside;
    assign force_zero     = mask_enable_i && !inside_image_o;

    // Write Enable을 끄지 않고 0을 써서 이전 Tile의 BRAM 값이 남지 않게 한다.
    assign data0_o = force_zero ? 16'sd0 : data0_i;
    assign data1_o = force_zero ? 16'sd0 : data1_i;
    assign data2_o = force_zero ? 16'sd0 : data2_i;
    assign data3_o = force_zero ? 16'sd0 : data3_i;

endmodule
