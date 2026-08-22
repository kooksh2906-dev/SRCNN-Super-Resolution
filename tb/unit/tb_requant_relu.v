`timescale 1ns / 1ps

module tb_requant_relu;

    reg  signed [47:0] acc_i;
    reg         [5:0]  shift_i;
    wire signed [15:0] data_o;

    integer error_count;

    requant_relu dut (
        .acc_i   (acc_i),
        .shift_i (shift_i),
        .data_o  (data_o)
    );

    task check_case;
        input signed [47:0] test_acc;
        input        [5:0]  test_shift;
        input signed [15:0] expected;

        begin
            acc_i   = test_acc;
            shift_i = test_shift;

            #10;

            if (data_o !== expected) begin
                $display(
                    "[FAIL] acc=%0d shift=%0d expected=%0d actual=%0d",
                    test_acc,
                    test_shift,
                    expected,
                    data_o
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS] acc=%0d shift=%0d result=%0d",
                    test_acc,
                    test_shift,
                    data_o
                );
            end
        end
    endtask

    initial begin
        acc_i      = 48'sd0;
        shift_i    = 6'd0;
        error_count = 0;

        #10;

        // 예시: 0은 반올림과 ReLU 이후에도 0
		// check_case(acc_i, shift_i, data_o);
        check_case(48'sd0, 6'd14, 16'sd0);

        // TODO 1: 8191 / 2^14 → 반올림 0 → 출력 0
		check_case(48'sd8191, 6'd14, 16'sd0);

        // TODO 2: 8192 / 2^14 → ties-away 반올림 1
		check_case(48'sd8192, 6'd14, 16'sd1);

        // TODO 3: 24576 / 2^14 → ties-away 반올림 2
		check_case(48'sd24576, 6'd14, 16'sd2);

        // TODO 4: -8192 / 2^14 → 반올림 -1 → ReLU 0
		check_case(-48'sd8192, 6'd14, 16'sd0);

        // TODO 5: 32767 × 2^14 → 정상 최댓값 32767
		check_case(48'sd536854528, 6'd14, 16'sd32767);

        // TODO 6: 32768 × 2^14 → 32768 → Clamp 32767
		check_case(48'sd536870912, 6'd14, 16'sd32767);

        // TODO 7: Conv2용 32768 / 2^16 → 반올림 1
		check_case(48'sd32768, 6'd16, 16'sd1);

        // TODO 8: Conv2용 -32768 / 2^16 → 반올림 -1 → ReLU 0
		check_case(-48'sd32768, 6'd16, 16'sd0);

        // TODO 9: Shift 0에서 40000 → Clamp 32767
		check_case(48'sd40000, 6'd0, 16'sd32767);

        // TODO 10: 지원하지 않는 Shift 48 → 0
		check_case(48'sd32768, 6'd48, 16'sd0);

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL TOP TESTS PASSED");
            $display("========================================");
        end
        else begin
            $display("========================================");
            $display("TOP TEST FAILED: %0d error(s)", error_count);
            $display("========================================");
        end

        $finish;
    end

endmodule