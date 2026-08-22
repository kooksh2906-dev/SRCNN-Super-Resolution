`timescale 1ns / 1ps

module tb_relu_clamp_int16;

    reg  signed [47:0] rounded_i;
    wire signed [15:0] clamped_o;

    integer error_count;

    relu_clamp_int16 dut (
        .rounded_i (rounded_i),
        .clamped_o (clamped_o)
    );

    task check_case;
        input signed [47:0] test_input;
        input signed [15:0] expected;

        begin
            rounded_i = test_input;

            #10;

            if (clamped_o !== expected) begin
                $display(
                    "[FAIL] input=%0d expected=%0d actual=%0d",
                    test_input,
                    expected,
                    clamped_o
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS] input=%0d result=%0d",
                    test_input,
                    clamped_o
                );
            end
        end
    endtask

    initial begin
        rounded_i  = 48'sd0;
        error_count = 0;

        #10;

        // 예시: 음수는 ReLU에 의해 0
        check_case(-48'sd1, 16'sd0);

        // TODO 1: -32768 입력은 0
		check_case(-48'sd32768, 16'sd0);

        // TODO 2: 0 입력은 0
		check_case(48'sd0, 16'sd0);

        // TODO 3: 1 입력은 1
		check_case(48'sd1, 16'sd1);

        // TODO 4: 32766 입력은 32766
		check_case(48'sd32766, 16'sd32766);

        // TODO 5: 경계값 32767은 32767
		check_case(48'sd32767, 16'sd32767);

        // TODO 6: 32768은 최댓값 32767로 Clamp
		check_case(48'sd32768, 16'sd32767);

        // TODO 7: 큰 양수 1000000도 32767로 Clamp
		check_case(48'sd1000000, 16'sd32767);

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL TESTS PASSED");
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