`timescale 1ns / 1ps

module tb_conv_control_fsm;

    reg clk;
    reg rst_n;

    reg start_i;
    reg advance_i;
    reg last_index_i;

    wire run_o;
    wire done_o;

    integer error_count;

    conv_control_fsm dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_i     (start_i),
        .advance_i   (advance_i),
        .last_index_i(last_index_i),
        .run_o       (run_o),
        .done_o      (done_o)
    );

    // 10ns 주기의 Clock 생성
    always #5 clk = ~clk;

    task check_outputs;
        input        expected_run;
        input        expected_done;
        input [31:0] test_number;

        begin
            // Clock Edge 직후 출력이 바뀔 시간을 기다림
            #1;

            if ((run_o !== expected_run) ||
                (done_o !== expected_done)) begin

                $display(
                    "[FAIL %0d] expected run=%0d done=%0d, actual run=%0d done=%0d",
                    test_number,
                    expected_run,
                    expected_done,
                    run_o,
                    done_o
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS %0d] run=%0d done=%0d",
                    test_number,
                    run_o,
                    done_o
                );
            end
        end
    endtask

    initial begin
        clk          = 1'b0;
        rst_n        = 1'b1;
        start_i      = 1'b0;
        advance_i    = 1'b0;
        last_index_i = 1'b0;
        error_count  = 0;

        // --------------------------------------------------
        // Test 1: Sync Active-Low Reset
        // --------------------------------------------------
        #2;
        // 동기식 Reset 입력
        @(negedge clk);
        rst_n = 1'b0;

        // 다음 Clock 상승 에지에서 실제 Reset
        @(posedge clk);
        #1;

        check_outputs(1'b0, 1'b0, 32'd1);

        // Reset 해제
        @(negedge clk);
        rst_n = 1'b1;

        // --------------------------------------------------
        // Test 2: IDLE 상태 유지
        // --------------------------------------------------
        @(posedge clk);
        check_outputs(1'b0, 1'b0, 32'd2);

        // --------------------------------------------------
        // Test 3: start_i 입력으로 IDLE → RUN
        // --------------------------------------------------
        @(negedge clk);
        start_i = 1'b1;

        @(posedge clk);
        check_outputs(1'b1, 1'b0, 32'd3);

        @(negedge clk);
        start_i = 1'b0;

        // --------------------------------------------------
        // Test 4: advance_i=0이면 RUN 유지
        // --------------------------------------------------
        advance_i    = 1'b0;
        last_index_i = 1'b0;

        @(posedge clk);
        check_outputs(1'b1, 1'b0, 32'd4);

        // --------------------------------------------------
        // Test 5: 일반 좌표 처리 후에도 RUN 유지
        // --------------------------------------------------
        @(negedge clk);
        advance_i    = 1'b1;
        last_index_i = 1'b0;

        @(posedge clk);
        check_outputs(1'b1, 1'b0, 32'd5);

        // --------------------------------------------------
        // Test 6: 마지막 좌표 처리 후 RUN → DONE
        // --------------------------------------------------
        @(negedge clk);
        advance_i    = 1'b1;
        last_index_i = 1'b1;

        @(posedge clk);
        check_outputs(1'b0, 1'b1, 32'd6);

        // --------------------------------------------------
        // Test 7: DONE은 1클럭 후 IDLE로 복귀
        // --------------------------------------------------
        @(negedge clk);
        advance_i    = 1'b0;
        last_index_i = 1'b0;

        @(posedge clk);
        check_outputs(1'b0, 1'b0, 32'd7);

        // --------------------------------------------------
        // Test 8: RUN 중 Sync Active-Low Reset
        // --------------------------------------------------
        @(negedge clk);
        start_i = 1'b1;

        // RUN 진입 확인
        @(posedge clk);
        #1;
        check_outputs(1'b1, 1'b0, 32'd8);

        // Reset을 Clock Dalling Edge에서 입력
        @(negedge clk);
        rst_n = 1'b0;

        @(posedge clk);
        #1;

        check_outputs(1'b0, 1'b0, 32'd9);

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL CONTROL FSM TESTS PASSED");
            $display("========================================");
        end
        else begin
            $display("========================================");
            $display("FSM TEST FAILED: %0d error(s)", error_count);
            $display("========================================");
        end

        $finish;
    end

endmodule
