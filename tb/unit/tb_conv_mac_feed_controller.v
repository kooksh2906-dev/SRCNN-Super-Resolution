`timescale 1ns / 1ps

module tb_conv_mac_feed_controller;

    reg clk;
    reg rst_n;

    reg run_i;
    reg core_busy_i;
    reg core_done_i;
    reg bias_ready_i;

    reg [5:0] in_channel_i;
    reg [6:0] in_channel_count_i;
    reg [3:0] kernel_y_i;
    reg [3:0] kernel_x_i;
    reg [3:0] kernel_size_i;

    wire op_start_o;
    wire bias_load_o;
    wire mac_valid_o;
    wire mac_last_o;
    wire bias_fetch_start_o;
    wire data_read_en_o;
    wire advance_o;

    integer error_count;

    conv_mac_feed_controller dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .run_i             (run_i),
        .core_busy_i       (core_busy_i),
        .core_done_i       (core_done_i),
        .bias_ready_i      (bias_ready_i),
        .in_channel_i      (in_channel_i),
        .in_channel_count_i(in_channel_count_i),
        .kernel_y_i        (kernel_y_i),
        .kernel_x_i        (kernel_x_i),
        .kernel_size_i     (kernel_size_i),
        .op_start_o        (op_start_o),
        .bias_load_o       (bias_load_o),
        .mac_valid_o       (mac_valid_o),
        .mac_last_o        (mac_last_o),
        .bias_fetch_start_o(bias_fetch_start_o),
        .data_read_en_o    (data_read_en_o),
        .advance_o         (advance_o)
    );

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
                    "[FAIL %0d] ic=%0d kernel=(%0d,%0d) expected=%07b actual=%07b",
                    test_number,
                    in_channel_i,
                    kernel_y_i,
                    kernel_x_i,
                    expected_control,
                    actual_control
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS %0d] ic=%0d kernel=(%0d,%0d) control=%07b",
                    test_number,
                    in_channel_i,
                    kernel_y_i,
                    kernel_x_i,
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
        bias_ready_i = 1'b0;

        in_channel_i       = 6'd0;
        in_channel_count_i = 7'd1;
        kernel_y_i         = 4'd0;
        kernel_x_i         = 4'd0;
        kernel_size_i      = 4'd2;

        error_count = 0;

        // Test 1: 동기식 Reset
        #2;
        @(negedge clk);
        rst_n = 1'b0;

        @(posedge clk);
        check_outputs(7'b0000000, 32'd1);

        // Test 2: 새로운 Output Pixel 연산 시작
        @(negedge clk);
        rst_n = 1'b1;
        run_i = 1'b1;

        @(posedge clk);
        check_outputs(7'b1000100, 32'd2);

        // Test 3: Bias 준비 대기
        @(posedge clk);
        check_outputs(7'b0000000, 32'd3);

        // Test 4: Bias 준비 완료
        @(negedge clk);
        bias_ready_i = 1'b1;

        @(posedge clk);
        check_outputs(7'b0100000, 32'd4);

        // Test 5: 첫 Activation/Weight 읽기
        @(negedge clk);
        bias_ready_i = 1'b0;

        @(posedge clk);
        check_outputs(7'b0000010, 32'd5);

        // Test 6: (ic,ky,kx)=(0,0,0)은 마지막이 아닌 MAC
        @(posedge clk);
        check_outputs(
            7'b0010001,  // 일반 MAC 및 좌표 증가
            32'd6
        );

        // 현재 MAC 좌표가 처리된 뒤 READ 상태로 복귀
        //
        // 주의:
        // MAC 상태 도중 좌표를 변경하면 inner_last 판정도 즉시
        // 바뀌므로, READ 상태에 들어온 뒤 좌표를 변경한다.
        @(posedge clk);
        check_outputs(7'b0000010, 32'd7);

        // 다음 좌표를 2×2 Kernel의 마지막 좌표로 설정
        @(negedge clk);
        kernel_y_i = 4'd1;
        kernel_x_i = 4'd1;

        // Test 8: 마지막 좌표의 MAC
        @(posedge clk);
        check_outputs(
            7'b0011001,  // 2×2 Kernel의 마지막 MAC
            32'd8
        );

        // Test 9: 마지막 MAC 후 Core 완료 대기
        @(posedge clk);
        check_outputs(7'b0000000, 32'd9);

        // Test 10: run=0이고 Core가 완료되면 IDLE
        @(negedge clk);
        run_i       = 1'b0;
        core_done_i = 1'b1;

        @(posedge clk);
        check_outputs(7'b0000000, 32'd10);

        // Conv2 설정의 마지막 내부 좌표 검증
        @(negedge clk);
        run_i              = 1'b1;
        core_done_i        = 1'b0;
        in_channel_i       = 6'd63;
        in_channel_count_i = 7'd64;
        kernel_y_i         = 4'd4;
        kernel_x_i         = 4'd4;
        kernel_size_i      = 4'd5;

        // Test 11: Conv2 연산 시작
        @(posedge clk);
        check_outputs(7'b1000100, 32'd11);

        // WAIT_BIAS
        @(posedge clk);
        check_outputs(7'b0000000, 32'd12);

        @(negedge clk);
        bias_ready_i = 1'b1;

        // BIAS
        @(posedge clk);
        check_outputs(7'b0100000, 32'd13);

        @(negedge clk);
        bias_ready_i = 1'b0;

        // READ
        @(posedge clk);
        check_outputs(7'b0000010, 32'd14);

        // Test 15: Conv2의 마지막 내부 좌표이므로 마지막 MAC
        @(posedge clk);
        check_outputs(
            7'b0011001,  // Conv2의 마지막 내부 MAC
            32'd15
        );

        // WAIT_DONE
        @(posedge clk);
        check_outputs(7'b0000000, 32'd16);

        // Test 17: 실행 중 동기식 Reset
        @(negedge clk);
        rst_n = 1'b0;

        @(posedge clk);
        check_outputs(7'b0000000, 32'd17);

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL MAC FEED CONTROLLER TESTS PASSED");
            $display("========================================");
        end
        else begin
            $display("========================================");
            $display(
                "MAC FEED CONTROLLER TEST FAILED: %0d error(s)",
                error_count
            );
            $display("========================================");
        end

        $finish;
    end

endmodule
