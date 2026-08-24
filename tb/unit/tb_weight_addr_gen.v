`timescale 1ns / 1ps

module tb_weight_addr_gen;

    reg  [5:0]  out_channel_i;
    reg  [5:0]  in_channel_i;
    reg  [6:0]  in_channel_count_i;
    reg  [3:0]  kernel_y_i;
    reg  [3:0]  kernel_x_i;
    reg  [3:0]  kernel_size_i;
    reg  [15:0] weight_base_addr_i;

    wire [15:0] weight_addr_o;

    integer error_count;

    weight_addr_gen dut (
        .out_channel_i      (out_channel_i),
        .in_channel_i       (in_channel_i),
        .in_channel_count_i (in_channel_count_i),
        .kernel_y_i         (kernel_y_i),
        .kernel_x_i         (kernel_x_i),
        .kernel_size_i      (kernel_size_i),
        .weight_base_addr_i (weight_base_addr_i),
        .weight_addr_o      (weight_addr_o)
    );

    task check_case;
        input [5:0]  test_out_channel;
        input [5:0]  test_in_channel;
        input [6:0]  test_in_channel_count;
        input [3:0]  test_kernel_y;
        input [3:0]  test_kernel_x;
        input [3:0]  test_kernel_size;
        input [15:0] test_base_addr;
        input [15:0] expected_addr;

        begin
            out_channel_i      = test_out_channel;
            in_channel_i       = test_in_channel;
            in_channel_count_i = test_in_channel_count;
            kernel_y_i         = test_kernel_y;
            kernel_x_i         = test_kernel_x;
            kernel_size_i      = test_kernel_size;
            weight_base_addr_i = test_base_addr;

            #10;

            if (weight_addr_o !== expected_addr) begin
                $display(
                    "[FAIL] oc=%0d ic=%0d kernel=(%0d,%0d) expected=%0d actual=%0d",
                    test_out_channel,
                    test_in_channel,
                    test_kernel_y,
                    test_kernel_x,
                    expected_addr,
                    weight_addr_o
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS] oc=%0d ic=%0d kernel=(%0d,%0d) addr=%0d",
                    test_out_channel,
                    test_in_channel,
                    test_kernel_y,
                    test_kernel_x,
                    weight_addr_o
                );
            end
        end
    endtask

    initial begin
        out_channel_i      = 6'd0;
        in_channel_i       = 6'd0;
        in_channel_count_i = 7'd0;
        kernel_y_i         = 4'd0;
        kernel_x_i         = 4'd0;
        kernel_size_i      = 4'd0;
        weight_base_addr_i = 16'd0;
        error_count        = 0;

        #10;

        // Conv1 첫 번째 Weight
        check_case(6'd0, 6'd0, 7'd1, 4'd0, 4'd0, 4'd9,
                   16'd0, 16'd0);

        // Conv1 Output Channel 1의 첫 번째 Weight
        // 한 Output Channel에는 1×9×9=81개의 Weight가 있음
        check_case(6'd1, 6'd0, 7'd1, 4'd0, 4'd0, 4'd9,
                   16'd0, 16'd81);

        // TODO 1:
        // Conv1 마지막 Weight
        // oc=63, ic=0, ky=8, kx=8
        // in_channel_count=1, kernel_size=9, base=0
        // expected=5183
		check_case(6'd63, 6'd0, 7'd1, 4'd8, 4'd8, 4'd9,
                   16'd0, 16'd5183);

        // TODO 2:
        // Conv2 첫 번째 Weight
        // oc=0, ic=0, ky=0, kx=0
        // in_channel_count=64, kernel_size=5, base=5184
        // expected=5184
		check_case(6'd0, 6'd0, 7'd64, 4'd0, 4'd0, 4'd5,
                   16'd5184, 16'd5184);

        // TODO 3:
        // Conv2 마지막 Weight
        // oc=31, ic=63, ky=4, kx=4
        // in_channel_count=64, kernel_size=5, base=5184
        // expected=56383
		check_case(6'd31, 6'd63, 7'd64, 4'd4, 4'd4, 4'd5,
                   16'd5184, 16'd56383);

        // TODO 4:
        // Conv3 마지막 Weight
        // oc=0, ic=31, ky=4, kx=4
        // in_channel_count=32, kernel_size=5, base=56384
        // expected=57183
		check_case(6'd0, 6'd31, 7'd32, 4'd4, 4'd4, 4'd5,
                   16'd56384, 16'd57183);

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL WEIGHT ADDRESS TESTS PASSED");
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
