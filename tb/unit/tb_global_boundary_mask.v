`timescale 1ns / 1ps

module tb_global_boundary_mask;

    reg        mask_enable_i;
    reg [3:0]  tile_x_i;
    reg [3:0]  tile_y_i;
    reg [4:0]  local_x_i;
    reg [4:0]  local_y_i;

    reg signed [15:0] data0_i;
    reg signed [15:0] data1_i;
    reg signed [15:0] data2_i;
    reg signed [15:0] data3_i;

    wire               inside_image_o;
    wire signed [15:0] data0_o;
    wire signed [15:0] data1_o;
    wire signed [15:0] data2_o;
    wire signed [15:0] data3_o;

    integer mismatch_count;

    global_boundary_mask dut (
        .mask_enable_i(mask_enable_i),
        .tile_x_i      (tile_x_i),
        .tile_y_i      (tile_y_i),
        .local_x_i     (local_x_i),
        .local_y_i     (local_y_i),
        .data0_i       (data0_i),
        .data1_i       (data1_i),
        .data2_i       (data2_i),
        .data3_i       (data3_i),
        .inside_image_o(inside_image_o),
        .data0_o       (data0_o),
        .data1_o       (data1_o),
        .data2_o       (data2_o),
        .data3_o       (data3_o)
    );

    task check_point;
        input [3:0] check_tile_x;
        input [3:0] check_tile_y;
        input [4:0] check_local_x;
        input [4:0] check_local_y;
        input       expected_inside;
        input       check_mask_enable;
        begin
            tile_x_i      = check_tile_x;
            tile_y_i      = check_tile_y;
            local_x_i     = check_local_x;
            local_y_i     = check_local_y;
            mask_enable_i = check_mask_enable;
            #1;

            if (inside_image_o !== expected_inside) begin
                mismatch_count = mismatch_count + 1;
                $display(
                    "[FAIL][VALID] tile=(%0d,%0d) local=(%0d,%0d) actual=%0d expected=%0d",
                    tile_x_i,
                    tile_y_i,
                    local_x_i,
                    local_y_i,
                    inside_image_o,
                    expected_inside
                );
            end

            if (check_mask_enable && !expected_inside) begin
                if ((data0_o !== 16'sd0) ||
                    (data1_o !== 16'sd0) ||
                    (data2_o !== 16'sd0) ||
                    (data3_o !== 16'sd0)) begin
                    mismatch_count = mismatch_count + 1;
                    $display("[FAIL][ZERO] invalid position was not zeroed");
                end
            end
            else begin
                if ((data0_o !== data0_i) ||
                    (data1_o !== data1_i) ||
                    (data2_o !== data2_i) ||
                    (data3_o !== data3_i)) begin
                    mismatch_count = mismatch_count + 1;
                    $display("[FAIL][PASS] valid/disabled position changed data");
                end
            end
        end
    endtask

    initial begin
        mismatch_count = 0;

        data0_i =  16'sd123;
        data1_i = -16'sd456;
        data2_i =  16'sd789;
        data3_i = -16'sd321;

        // 내부 Tile은 32x32 전체가 유효
        check_point(4'd1,  4'd1,  5'd0,  5'd0,  1'b1, 1'b1);
        check_point(4'd14, 4'd14, 5'd31, 5'd31, 1'b1, 1'b1);

        // 위/아래 경계
        check_point(4'd8, 4'd0,  5'd12, 5'd7,  1'b0, 1'b1);
        check_point(4'd8, 4'd0,  5'd12, 5'd8,  1'b1, 1'b1);
        check_point(4'd8, 4'd15, 5'd12, 5'd23, 1'b1, 1'b1);
        check_point(4'd8, 4'd15, 5'd12, 5'd24, 1'b0, 1'b1);

        // 왼쪽/오른쪽 경계
        check_point(4'd0,  4'd8, 5'd7,  5'd12, 1'b0, 1'b1);
        check_point(4'd0,  4'd8, 5'd8,  5'd12, 1'b1, 1'b1);
        check_point(4'd15, 4'd8, 5'd23, 5'd12, 1'b1, 1'b1);
        check_point(4'd15, 4'd8, 5'd24, 5'd12, 1'b0, 1'b1);

        // 모서리는 X/Y 조건을 모두 만족해야 함
        check_point(4'd0,  4'd0,  5'd7,  5'd8,  1'b0, 1'b1);
        check_point(4'd0,  4'd0,  5'd8,  5'd8,  1'b1, 1'b1);
        check_point(4'd15, 4'd15, 5'd23, 5'd23, 1'b1, 1'b1);
        check_point(4'd15, 4'd15, 5'd24, 5'd23, 1'b0, 1'b1);

        // Conv3처럼 Mask를 끄면 영상 밖 좌표도 Data를 그대로 통과
        check_point(4'd0, 4'd0, 5'd0, 5'd0, 1'b0, 1'b0);

        if (mismatch_count == 0)
            $display("[PASS] Global boundary mask test passed");
        else
            $display(
                "[FAIL] Global boundary mask mismatches=%0d",
                mismatch_count
            );

        $finish;
    end

endmodule
