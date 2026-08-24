`timescale 1ns / 1ps

module tb_conv_mac_feed_fsm;

    reg clk;
    reg rst_n;

    reg run_i;
    reg core_busy_i;
    reg core_done_i;
    reg inner_last_i;
    reg bias_ready_i;

    wire op_start_o;
    wire bias_load_o;
    wire mac_valid_o;
    wire mac_last_o;
    wire bias_fetch_start_o;
    wire data_read_en_o;
    wire advance_o;

    integer error_count;

    conv_mac_feed_fsm dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .run_i             (run_i),
        .core_busy_i       (core_busy_i),
        .core_done_i       (core_done_i),
        .inner_last_i      (inner_last_i),
        .bias_ready_i      (bias_ready_i),
        .op_start_o        (op_start_o),
        .bias_load_o       (bias_load_o),
        .mac_valid_o       (mac_valid_o),
        .mac_last_o        (mac_last_o),
        .bias_fetch_start_o(bias_fetch_start_o),
        .data_read_en_o    (data_read_en_o),
        .advance_o         (advance_o)
    );

    // 10ns 주기의 Clock 생성
    always #5 clk = ~clk;

    // 출력 순서:
    // {op_start, bias_load, mac_valid, mac_last,
    //  bias_fetch_start, data_read_en, advance}
    task check_outputs;
        input [6:0]  expected_control;
        input [31:0] test_number;

        reg [6:0] actual_control;

        begin
            #1;

            actual_control = {
                op_start_o,
                bias_load_o,
                mac_valid_o,
                mac_last_o,
                bias_fetch_start_o,
                data_read_en_o,
                advance_o
            };

            if (actual_control !== expected_control) begin
                $display(
                    "[FAIL %0d] expected=%07b actual=%07b",
                    test_number,
                    expected_control,
                    actual_control
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS %0d] control=%07b",
                    test_number,
                    actual_control
                );
            end
        end
    endtask

    initial begin
        clk          = 1'b0;
        rst_n        = 1'b1;
        run_i        = 1'b0;
        core_busy_i  = 1'b0;
        core_done_i  = 1'b0;
        inner_last_i = 1'b0;
        bias_ready_i = 1'b0;
        error_count  = 0;

        // Test 1: 동기식 Active-Low Reset
        #2;
        @(negedge clk);
        rst_n = 1'b0;

        @(posedge clk);
        check_outputs(7'b0000000, 32'd1);

        // Test 2: Core가 Busy이면 IDLE 유지
        @(negedge clk);
        rst_n       = 1'b1;
        run_i       = 1'b1;
        core_busy_i = 1'b1;

        @(posedge clk);
        check_outputs(
            7'b0000000,  // IDLE 출력
            32'd2
        );

        // Test 3: Core가 비면 START 진입
        @(negedge clk);
        core_busy_i = 1'b0;

        @(posedge clk);
        check_outputs(
            7'b1000100,  // Core와 Bias Loader 동시 시작
            32'd3
        );

        // Test 4: START 다음에는 WAIT_BIAS
        @(posedge clk);
        check_outputs(
            7'b0000000,  // Bias 준비 대기
            32'd4
        );

        // Test 5: bias_ready=0이면 WAIT_BIAS 유지
        @(posedge clk);
        check_outputs(
            7'b0000000,  // Bias 준비 대기
            32'd5
        );

        // Test 6: Bias가 준비되면 BIAS 상태에서 Load
        @(negedge clk);
        bias_ready_i = 1'b1;

        @(posedge clk);
        check_outputs(
            7'b0100000,  // 준비된 Bias를 B파트에 Load
            32'd6
        );

        // Test 7: BIAS 다음에는 BRAM READ
        @(negedge clk);
        bias_ready_i = 1'b0;

        @(posedge clk);
        check_outputs(
            7'b0000010,  // Activation/Weight BRAM 읽기
            32'd7
        );

        // Test 8: 마지막이 아닌 MAC
        @(posedge clk);
        check_outputs(
            7'b0010001,  // 일반 MAC 및 좌표 증가
            32'd8
        );

        // Test 9: 다음 입력을 읽기 위해 READ 복귀
        @(posedge clk);
        check_outputs(
            7'b0000010,  // Activation/Weight BRAM 읽기
            32'd9
        );

        // Test 10: 마지막 MAC
        @(negedge clk);
        inner_last_i = 1'b1;

        @(posedge clk);
        check_outputs(
            7'b0011001,  // 마지막 MAC 및 좌표 증가
            32'd10
        );

        // Test 11: 마지막 MAC 후 Core 완료 대기
        @(posedge clk);
        check_outputs(
            7'b0000000,
            32'd11
        );

        // Test 12: core_done=0이면 WAIT_DONE 유지
        @(posedge clk);
        check_outputs(
            7'b0000000,
            32'd12
        );

        // Test 13: 연산이 남아 있으면 다음 START
        @(negedge clk);
        core_done_i = 1'b1;

        @(posedge clk);
        check_outputs(
            7'b1000100,  // START 출력
            32'd13
        );

        // 두 번째 연산의 Bias 준비
        @(negedge clk);
        core_done_i = 1'b0;

        @(posedge clk);
        check_outputs(7'b0000000, 32'd14);

        @(negedge clk);
        bias_ready_i = 1'b1;

        @(posedge clk);
        check_outputs(
            7'b0100000,  // BIAS 출력
            32'd15
        );

        @(negedge clk);
        bias_ready_i = 1'b0;

        // READ
        @(posedge clk);
        check_outputs(7'b0000010, 32'd16);

        // 마지막 MAC
        @(posedge clk);
        check_outputs(7'b0011001, 32'd17);

        // WAIT_DONE
        @(posedge clk);
        check_outputs(7'b0000000, 32'd18);

        // Test 19: Layer 실행이 끝났으면 IDLE 복귀
        @(negedge clk);
        core_done_i = 1'b1;
        run_i       = 1'b0;

        @(posedge clk);
        check_outputs(
            7'b0000000,  // IDLE 출력
            32'd19
        );

        // Test 20: 실행 중 동기식 Reset
        @(negedge clk);
        core_done_i = 1'b0;
        run_i       = 1'b1;
        inner_last_i = 1'b0;

        @(posedge clk);
        check_outputs(7'b1000100, 32'd20);

        @(negedge clk);
        rst_n = 1'b0;

        @(posedge clk);
        check_outputs(
            7'b0000000,  // Reset 후 IDLE 출력
            32'd21
        );

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL MAC FEED FSM TESTS PASSED");
            $display("========================================");
        end
        else begin
            $display("========================================");
            $display(
                "MAC FEED FSM TEST FAILED: %0d error(s)",
                error_count
            );
            $display("========================================");
        end

        $finish;
    end

endmodule
