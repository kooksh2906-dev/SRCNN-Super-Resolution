`timescale 1ns / 1ps

module tb_conv_loop_controller;

    reg clk;
    reg arstn;
    reg start_i;
    reg advance_i;

    reg [6:0] out_channel_count_i;
    reg [6:0] in_channel_count_i;
    reg [5:0] output_size_i;
    reg [3:0] kernel_size_i;

    wire       run_o;
    wire       done_o;
    wire       last_index_o;

    wire [5:0] out_channel_o;
    wire [5:0] in_channel_o;
    wire [4:0] out_y_o;
    wire [4:0] out_x_o;
    wire [3:0] kernel_y_o;
    wire [3:0] kernel_x_o;

    integer error_count;

    conv_loop_controller dut (
        .clk                (clk),
        .arstn              (arstn),
        .start_i            (start_i),
        .advance_i          (advance_i),
        .out_channel_count_i(out_channel_count_i),
        .in_channel_count_i (in_channel_count_i),
        .output_size_i      (output_size_i),
        .kernel_size_i      (kernel_size_i),
        .run_o              (run_o),
        .done_o             (done_o),
        .last_index_o       (last_index_o),
        .out_channel_o      (out_channel_o),
        .in_channel_o       (in_channel_o),
        .out_y_o            (out_y_o),
        .out_x_o            (out_x_o),
        .kernel_y_o         (kernel_y_o),
        .kernel_x_o         (kernel_x_o)
    );

    // 10ns 주기의 Clock
    always #5 clk = ~clk;

    task check_case;
        input       expected_run;
        input       expected_done;
        input       expected_last;
        input [3:0] expected_ky;
        input [3:0] expected_kx;
        input [31:0] test_number;

        begin
            #1;

            if ((run_o         !== expected_run)  ||
                (done_o        !== expected_done) ||
                (last_index_o  !== expected_last) ||
                (kernel_y_o    !== expected_ky)   ||
                (kernel_x_o    !== expected_kx)   ||
                (out_channel_o !== 6'd0)          ||
                (in_channel_o  !== 6'd0)          ||
                (out_y_o       !== 5'd0)          ||
                (out_x_o       !== 5'd0)) begin

                $display(
                    "[FAIL %0d] run=%0d done=%0d last=%0d kernel=(%0d,%0d)",
                    test_number,
                    run_o,
                    done_o,
                    last_index_o,
                    kernel_y_o,
                    kernel_x_o
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS %0d] run=%0d done=%0d last=%0d kernel=(%0d,%0d)",
                    test_number,
                    run_o,
                    done_o,
                    last_index_o,
                    kernel_y_o,
                    kernel_x_o
                );
            end
        end
    endtask

    // IDLE 상태에서 Start Pulse 입력
    task pulse_start;
        begin
            @(negedge clk);
            start_i = 1'b1;

            @(posedge clk);
            #1;
            start_i = 1'b0;
        end
    endtask

    // RUN 상태에서 Advance Pulse 입력
    task pulse_advance;
        begin
            @(negedge clk);
            advance_i = 1'b1;

            @(posedge clk);
            #1;
            advance_i = 1'b0;
        end
    endtask

    initial begin
        clk       = 1'b0;
        arstn     = 1'b1;
        start_i   = 1'b0;
        advance_i = 1'b0;

        out_channel_count_i = 7'd1;
        in_channel_count_i  = 7'd1;
        output_size_i       = 6'd1;
        kernel_size_i       = 4'd2;

        error_count = 0;

        // Test 1: 비동기 Reset
        #2;
        arstn = 1'b0;

        check_case(
            1'b0, 1'b0, 1'b0,
            4'd0, 4'd0, 32'd1
        );

        // Reset 해제
        @(negedge clk);
        arstn = 1'b1;

        // Test 2: IDLE에서 Start를 받으면 RUN 진입 및 좌표 초기화
        pulse_start;

        check_case(
            1'b1, 1'b0, 1'b0,
            4'd0, 4'd0, 32'd2
        );

        // Test 3: 첫 번째 Advance
        pulse_advance;

        check_case(
            1'b1, 1'b0, 1'b0,
            4'd0, 4'd1, 32'd3
        );

        // Test 4: 두 번째 Advance
        pulse_advance;

        check_case(
            1'b1, 1'b0, 1'b0,
            4'd1, 4'd0, 32'd4
        );

        // Test 5: 세 번째 Advance로 마지막 좌표 도착
        pulse_advance;

        check_case(
            1'b1, 1'b0, 1'b1,
            4'd1, 4'd1, 32'd5
        );

        // Test 6: advance_i=0이면 마지막 좌표에서 RUN 유지
        @(posedge clk);

        check_case(
            1'b1, 1'b0, 1'b1,
            4'd1, 4'd1, 32'd6
        );

        // Test 7: 마지막 좌표에서 Advance를 받으면 DONE 진입
        pulse_advance;

        check_case(
            1'b0, 1'b1, 1'b1,
            4'd1, 4'd1, 32'd7
        );

        // Test 8: DONE은 한 클럭 후 IDLE로 복귀
        @(posedge clk);

        check_case(
            1'b0, 1'b0, 1'b1,
            4'd1, 4'd1, 32'd8
        );

        // Test 9: 다시 Start하면 좌표를 0으로 초기화하고 재시작
        pulse_start;

        check_case(
            1'b1, 1'b0, 1'b0,
            4'd0, 4'd0, 32'd9
        );

        // Test 10: RUN 중 비동기 Reset
        #2;
        arstn = 1'b0;

        check_case(
            1'b0, 1'b0, 1'b0,
            4'd0, 4'd0, 32'd10
        );

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL LOOP CONTROLLER TESTS PASSED");
            $display("========================================");
        end
        else begin
            $display("========================================");
            $display("LOOP TEST FAILED: %0d error(s)", error_count);
            $display("========================================");
        end

        $finish;
    end

endmodule
