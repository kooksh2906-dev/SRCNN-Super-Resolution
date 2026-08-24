`timescale 1ns / 1ps

module tb_conv_index_counter;

    reg clk;
    reg arstn;
    reg clear_i;
    reg advance_i;

    reg [6:0] out_channel_count_i;
    reg [6:0] in_channel_count_i;
    reg [5:0] output_size_i;
    reg [3:0] kernel_size_i;

    wire [5:0] out_channel_o;
    wire [5:0] in_channel_o;
    wire [4:0] out_y_o;
    wire [4:0] out_x_o;
    wire [3:0] kernel_y_o;
    wire [3:0] kernel_x_o;
    wire       last_index_o;

    integer expected_oc;
    integer expected_oy;
    integer expected_ox;
    integer expected_ic;
    integer expected_ky;
    integer expected_kx;

    integer checked_count;
    integer error_count;

    conv_index_counter dut (
        .clk                (clk),
        .arstn              (arstn),
        .clear_i            (clear_i),
        .advance_i          (advance_i),
        .out_channel_count_i(out_channel_count_i),
        .in_channel_count_i (in_channel_count_i),
        .output_size_i      (output_size_i),
        .kernel_size_i      (kernel_size_i),
        .out_channel_o      (out_channel_o),
        .in_channel_o       (in_channel_o),
        .out_y_o            (out_y_o),
        .out_x_o            (out_x_o),
        .kernel_y_o         (kernel_y_o),
        .kernel_x_o         (kernel_x_o),
        .last_index_o       (last_index_o)
    );

    // 10ns 주기의 Clock 생성
    always #5 clk = ~clk;

    // 현재 RTL 좌표와 예상 좌표를 비교
    task check_coordinate;
        input [5:0] expected_out_channel;
        input [4:0] expected_out_y;
        input [4:0] expected_out_x;
        input [5:0] expected_in_channel;
        input [3:0] expected_kernel_y;
        input [3:0] expected_kernel_x;
        input       expected_last;

        begin
            #1;

            checked_count = checked_count + 1;

            if ((out_channel_o !== expected_out_channel) ||
                (out_y_o       !== expected_out_y)       ||
                (out_x_o       !== expected_out_x)       ||
                (in_channel_o  !== expected_in_channel)  ||
                (kernel_y_o    !== expected_kernel_y)    ||
                (kernel_x_o    !== expected_kernel_x)    ||
                (last_index_o  !== expected_last)) begin

                $display(
                    "[FAIL %0d] expected=(%0d,%0d,%0d,%0d,%0d,%0d,%0d) actual=(%0d,%0d,%0d,%0d,%0d,%0d,%0d)",
                    checked_count,
                    expected_out_channel,
                    expected_out_y,
                    expected_out_x,
                    expected_in_channel,
                    expected_kernel_y,
                    expected_kernel_x,
                    expected_last,
                    out_channel_o,
                    out_y_o,
                    out_x_o,
                    in_channel_o,
                    kernel_y_o,
                    kernel_x_o,
                    last_index_o
                );

                error_count = error_count + 1;
            end
        end
    endtask

    // advance_i를 한 클럭 동안 1로 만들어 다음 좌표로 이동
    task advance_counter;
        begin
            @(negedge clk);
            advance_i = 1'b1;

            @(posedge clk);
            #1;
            advance_i = 1'b0;
        end
    endtask

    initial begin
        clk     = 1'b0;
        arstn   = 1'b1;
        clear_i = 1'b0;
        advance_i = 1'b0;

        // 작은 설정으로 모든 Carry를 빠르게 검증
        out_channel_count_i = 7'd2;
        in_channel_count_i  = 7'd2;
        output_size_i       = 6'd2;
        kernel_size_i       = 4'd2;

        checked_count = 0;
        error_count   = 0;

        // 비동기 Reset
        #2;
        arstn = 1'b0;

        check_coordinate(
            6'd0, 5'd0, 5'd0,
            6'd0, 4'd0, 4'd0,
            1'b0
        );

        // Reset 해제 후 Clear
        @(negedge clk);
        arstn   = 1'b1;
        clear_i = 1'b1;

        @(posedge clk);
        #1;

        @(negedge clk);
        clear_i = 1'b0;

        // 총 2×2×2×2×2×2 = 64개 좌표 검사
        for (expected_oc = 0;
             expected_oc < 2;
             expected_oc = expected_oc + 1) begin

            for (expected_oy = 0;
                 expected_oy < 2;
                 expected_oy = expected_oy + 1) begin

                for (expected_ox = 0;
                     expected_ox < 2;
                     expected_ox = expected_ox + 1) begin

                    for (expected_ic = 0;
                         expected_ic < 2;
                         expected_ic = expected_ic + 1) begin

                        for (expected_ky = 0;
                             expected_ky < 2;
                             expected_ky = expected_ky + 1) begin

                            for (expected_kx = 0;
                                 expected_kx < 2;
                                 expected_kx = expected_kx + 1) begin

                                check_coordinate(
                                    expected_oc,
                                    expected_oy,
                                    expected_ox,
                                    expected_ic,
                                    expected_ky,
                                    expected_kx,
                                    (expected_oc == 1) &&
                                    (expected_oy == 1) &&
                                    (expected_ox == 1) &&
                                    (expected_ic == 1) &&
                                    (expected_ky == 1) &&
                                    (expected_kx == 1)
                                );

                                // 마지막 좌표가 아니면 다음 좌표로 이동
                                if (!((expected_oc == 1) &&
                                      (expected_oy == 1) &&
                                      (expected_ox == 1) &&
                                      (expected_ic == 1) &&
                                      (expected_ky == 1) &&
                                      (expected_kx == 1))) begin

                                    advance_counter;
                                end
                            end
                        end
                    end
                end
            end
        end

        // 마지막 좌표에서 advance가 들어와도 값이 유지되는지 검사
        advance_counter;

        check_coordinate(
            6'd1, 5'd1, 5'd1,
            6'd1, 4'd1, 4'd1,
            1'b1
        );

        // clear_i가 모든 좌표를 0으로 초기화하는지 검사
        @(negedge clk);
        clear_i = 1'b1;

        @(posedge clk);
        #1;
        clear_i = 1'b0;

        check_coordinate(
            6'd0, 5'd0, 5'd0,
            6'd0, 4'd0, 4'd0,
            1'b0
        );

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL INDEX COUNTER TESTS PASSED");
            $display("Checked coordinates: %0d", checked_count);
            $display("========================================");
        end
        else begin
            $display("========================================");
            $display("INDEX TEST FAILED: %0d error(s)", error_count);
            $display("========================================");
        end

        $finish;
    end

endmodule
