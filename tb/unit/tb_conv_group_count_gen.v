`timescale 1ns / 1ps

module tb_conv_group_count_gen;

    reg  [6:0] out_channel_count_i;
    wire [6:0] out_channel_group_count_o;

    integer error_count;

    conv_group_count_gen dut (
        .out_channel_count_i      (out_channel_count_i),
        .out_channel_group_count_o(out_channel_group_count_o)
    );

    task check_case;
        input [6:0] test_channel_count;
        input [6:0] expected_group_count;

        begin
            out_channel_count_i = test_channel_count;

            #10;

            if (out_channel_group_count_o !==
                expected_group_count) begin

                $display(
                    "[FAIL] channels=%0d expected_groups=%0d actual_groups=%0d",
                    test_channel_count,
                    expected_group_count,
                    out_channel_group_count_o
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS] channels=%0d groups=%0d",
                    test_channel_count,
                    out_channel_group_count_o
                );
            end
        end
    endtask

    initial begin
        out_channel_count_i = 7'd0;
        error_count         = 0;

        #10;

        // Output Channel이 없으면 Group도 없음
        check_case(7'd0,   7'd0);  // Output Channel 없음

        // 1~4개 Output Channel은 Group 하나로 처리
        check_case(7'd1,   7'd1);  // 첫 번째 Group
        check_case(7'd2,   7'd1);  // PE 2개를 사용하는 첫 번째 Group
        check_case(7'd3,   7'd1);  // PE 3개를 사용하는 첫 번째 Group
        check_case(7'd4,   7'd1);  // PE 4개를 모두 사용하는 Group

        // 5개부터 두 번째 Group이 필요
        check_case(7'd5,   7'd2);  // 두 번째 Group 필요

        // SRCNN Conv2: 32 Output Channels
        check_case(7'd32,  7'd8);  // Conv2

        // SRCNN Conv1: 64 Output Channels
        check_case(7'd64,  7'd16);  // Conv1

        // 7-bit 입력의 최댓값 경계 검사
        check_case(7'd127, 7'd32);  // 7-bit 최댓값

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL GROUP COUNT TESTS PASSED");
            $display("========================================");
        end
        else begin
            $display("========================================");
            $display(
                "GROUP COUNT TEST FAILED: %0d error(s)",
                error_count
            );
            $display("========================================");
        end

        $finish;
    end

endmodule
