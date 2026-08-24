`timescale 1ns / 1ps

module tb_weight_group_addr_gen;

    reg  [5:0]  out_channel_group_i;
    reg  [6:0]  out_channel_count_i;
    reg  [5:0]  in_channel_i;
    reg  [6:0]  in_channel_count_i;
    reg  [3:0]  kernel_y_i;
    reg  [3:0]  kernel_x_i;
    reg  [3:0]  kernel_size_i;
    reg  [15:0] weight_word_base_addr_i;

    wire [3:0]  pe_enable_o;
    wire [15:0] weight_word_addr_o;

    integer error_count;

    weight_group_addr_gen dut (
        .out_channel_group_i   (out_channel_group_i),
        .out_channel_count_i   (out_channel_count_i),
        .in_channel_i          (in_channel_i),
        .in_channel_count_i    (in_channel_count_i),
        .kernel_y_i            (kernel_y_i),
        .kernel_x_i            (kernel_x_i),
        .kernel_size_i         (kernel_size_i),
        .weight_word_base_addr_i(weight_word_base_addr_i),
        .pe_enable_o           (pe_enable_o),
        .weight_word_addr_o    (weight_word_addr_o)
    );

    task check_case;
        input [5:0]  test_group;
        input [6:0]  test_out_channel_count;
        input [5:0]  test_in_channel;
        input [6:0]  test_in_channel_count;
        input [3:0]  test_kernel_y;
        input [3:0]  test_kernel_x;
        input [3:0]  test_kernel_size;
        input [15:0] test_base_addr;
        input [3:0]  expected_pe_enable;
        input [15:0] expected_addr;

        begin
            out_channel_group_i    = test_group;
            out_channel_count_i    = test_out_channel_count;
            in_channel_i           = test_in_channel;
            in_channel_count_i     = test_in_channel_count;
            kernel_y_i             = test_kernel_y;
            kernel_x_i             = test_kernel_x;
            kernel_size_i          = test_kernel_size;
            weight_word_base_addr_i = test_base_addr;

            #10;

            if ((pe_enable_o !== expected_pe_enable) ||
                (weight_word_addr_o !== expected_addr)) begin

                $display(
                    "[FAIL] group=%0d ic=%0d kernel=(%0d,%0d) expected=(%b,%0d) actual=(%b,%0d)",
                    test_group, test_in_channel,
                    test_kernel_y, test_kernel_x,
                    expected_pe_enable, expected_addr,
                    pe_enable_o, weight_word_addr_o
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS] group=%0d ic=%0d kernel=(%0d,%0d) pe=%b addr=%0d",
                    test_group, test_in_channel,
                    test_kernel_y, test_kernel_x,
                    pe_enable_o, weight_word_addr_o
                );
            end
        end
    endtask

    initial begin
        out_channel_group_i     = 6'd0;
        out_channel_count_i     = 7'd0;
        in_channel_i            = 6'd0;
        in_channel_count_i      = 7'd0;
        kernel_y_i              = 4'd0;
        kernel_x_i              = 4'd0;
        kernel_size_i           = 4'd0;
        weight_word_base_addr_i = 16'd0;
        error_count             = 0;

        #10;

        // Conv1 첫 번째 Packed Weight Word
        check_case(
            6'd0, 7'd64, 6'd0, 7'd1,
            4'd0, 4'd0, 4'd9,
            16'd0, 4'b1111, 16'd0
        );

        // Conv1 마지막 Packed Weight Word
        check_case(
            6'd15, 7'd64, 6'd0, 7'd1,
            4'd8, 4'd8, 4'd9,
            16'd0, 4'b1111, 16'd1295
        );

        // Conv2 첫 번째 Packed Weight Word
        check_case(
            6'd0, 7'd32, 6'd0, 7'd64,
            4'd0, 4'd0, 4'd5,
            16'd1296, 4'b1111, 16'd1296
        );

        // Conv2 마지막 Packed Weight Word
        check_case(
            6'd7, 7'd32, 6'd63, 7'd64,
            4'd4, 4'd4, 4'd5,
            16'd1296, 4'b1111, 16'd14095
        );

        // Conv3 마지막 Packed Weight Word
        // 출력 채널이 하나이므로 PE0만 사용
        check_case(
            6'd0, 7'd1, 6'd31, 7'd32,
            4'd4, 4'd4, 4'd5,
            16'd14096, 4'b0001, 16'd14895
        );

        // 출력 채널이 6개인 일반적인 부분 Group
        // Group 1은 OC4, OC5만 존재하므로 PE0·PE1 사용
        check_case(
            6'd1, 7'd6, 6'd0, 7'd1,
            4'd0, 4'd0, 4'd1,
            16'd0, 4'b0011, 16'd1
        );

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL WEIGHT GROUP ADDRESS TESTS PASSED");
            $display("========================================");
        end
        else begin
            $display("========================================");
            $display("TEST FAILED: %0d error(s)", error_count);
            $display("========================================");
        end

        $finish;
    end

endmodule
