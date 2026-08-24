`timescale 1ns / 1ps

module tb_conv_inner_last_gen;

    reg  [5:0] in_channel_i;
    reg  [6:0] in_channel_count_i;
    reg  [3:0] kernel_y_i;
    reg  [3:0] kernel_x_i;
    reg  [3:0] kernel_size_i;

    wire       inner_last_o;

    integer error_count;

    conv_inner_last_gen dut (
        .in_channel_i      (in_channel_i),
        .in_channel_count_i(in_channel_count_i),
        .kernel_y_i        (kernel_y_i),
        .kernel_x_i        (kernel_x_i),
        .kernel_size_i     (kernel_size_i),
        .inner_last_o      (inner_last_o)
    );

    task check_case;
        input [5:0] test_in_channel;
        input [6:0] test_in_channel_count;
        input [3:0] test_kernel_y;
        input [3:0] test_kernel_x;
        input [3:0] test_kernel_size;
        input       expected_last;

        begin
            in_channel_i       = test_in_channel;
            in_channel_count_i = test_in_channel_count;
            kernel_y_i         = test_kernel_y;
            kernel_x_i         = test_kernel_x;
            kernel_size_i      = test_kernel_size;

            #10;

            if (inner_last_o !== expected_last) begin
                $display(
                    "[FAIL] ic=%0d/%0d kernel=(%0d,%0d)/%0d expected=%0d actual=%0d",
                    test_in_channel,
                    test_in_channel_count,
                    test_kernel_y,
                    test_kernel_x,
                    test_kernel_size,
                    expected_last,
                    inner_last_o
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS] ic=%0d/%0d kernel=(%0d,%0d)/%0d last=%0d",
                    test_in_channel,
                    test_in_channel_count,
                    test_kernel_y,
                    test_kernel_x,
                    test_kernel_size,
                    inner_last_o
                );
            end
        end
    endtask

    initial begin
        in_channel_i       = 6'd0;
        in_channel_count_i = 7'd1;
        kernel_y_i         = 4'd0;
        kernel_x_i         = 4'd0;
        kernel_size_i      = 4'd1;
        error_count        = 0;

        #10;

        // 1×1 Kernel, Input Channel 1개의 유일한 MAC
        check_case(
            6'd0, 7'd1, 4'd0, 4'd0, 4'd1,
            1'b1   // 유일한 MAC이므로 마지막
        );

        // Conv1의 첫 Kernel 좌표이므로 마지막이 아님
        check_case(
            6'd0, 7'd1, 4'd0, 4'd0, 4'd9,
            1'b0   // 첫 Kernel 좌표
        );

        // Conv1에서 kernel_x가 마지막 직전
        check_case(
            6'd0, 7'd1, 4'd8, 4'd7, 4'd9,
            1'b0   // kernel_x가 마지막 직전
        );

        // Conv1에서 kernel_y가 마지막 직전
        check_case(
            6'd0, 7'd1, 4'd7, 4'd8, 4'd9,
            1'b0   // kernel_y가 마지막 직전
        );

        // Conv1의 마지막 내부 MAC 좌표
        check_case(
            6'd0, 7'd1, 4'd8, 4'd8, 4'd9,
            1'b1   // Conv1의 마지막 내부 MAC
        );

        // Conv2에서 Input Channel이 마지막 직전
        check_case(
            6'd62, 7'd64, 4'd4, 4'd4, 4'd5,
            1'b0   // Conv2의 Input Channel이 마지막 직전
        );

        // Conv2의 마지막 내부 MAC 좌표
        check_case(
            6'd63, 7'd64, 4'd4, 4'd4, 4'd5,
            1'b1   // Conv2의 마지막 내부 MAC
        );

        // Conv3의 마지막 내부 MAC 좌표
        check_case(
            6'd31, 7'd32, 4'd4, 4'd4, 4'd5,
            1'b1   // Conv3의 마지막 내부 MAC
        );

        // Conv3에서 kernel_x가 마지막 직전
        check_case(
            6'd31, 7'd32, 4'd4, 4'd3, 4'd5,
            1'b0   // kernel_x가 마지막 직전
        );

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL INNER-LAST TESTS PASSED");
            $display("========================================");
        end
        else begin
            $display("========================================");
            $display(
                "INNER-LAST TEST FAILED: %0d error(s)",
                error_count
            );
            $display("========================================");
        end

        $finish;
    end

endmodule
