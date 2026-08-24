`timescale 1ns / 1ps

module tb_conv_group_loop_controller;

    reg clk;
    reg rst_n;

    reg start_i;
    reg advance_i;

    reg [6:0] out_channel_count_i;
    reg [6:0] in_channel_count_i;
    reg [5:0] output_size_i;
    reg [3:0] kernel_size_i;

    wire       run_o;
    wire       done_o;
    wire       last_index_o;

    wire [6:0] out_channel_group_count_o;
    wire [5:0] out_channel_group_o;

    wire [5:0] in_channel_o;
    wire [4:0] out_y_o;
    wire [4:0] out_x_o;
    wire [3:0] kernel_y_o;
    wire [3:0] kernel_x_o;

    integer error_count;

    conv_group_loop_controller dut (
        .clk                      (clk),
        .rst_n                    (rst_n),
        .start_i                  (start_i),
        .advance_i                (advance_i),
        .out_channel_count_i      (out_channel_count_i),
        .in_channel_count_i       (in_channel_count_i),
        .output_size_i            (output_size_i),
        .kernel_size_i            (kernel_size_i),
        .run_o                    (run_o),
        .done_o                   (done_o),
        .last_index_o             (last_index_o),
        .out_channel_group_count_o(out_channel_group_count_o),
        .out_channel_group_o      (out_channel_group_o),
        .in_channel_o             (in_channel_o),
        .out_y_o                  (out_y_o),
        .out_x_o                  (out_x_o),
        .kernel_y_o               (kernel_y_o),
        .kernel_x_o               (kernel_x_o)
    );

    always #5 clk = ~clk;

    // 상태 출력 순서:
    // {run, done, last_index, group_count[6:0], group[5:0]}
    task check_status;
        input [15:0] expected_status;
        input [31:0] test_number;

        reg [15:0] actual_status;

        begin
            #1;

            actual_status = {
                run_o,
                done_o,
                last_index_o,
                out_channel_group_count_o,
                out_channel_group_o
            };

            if ((actual_status !== expected_status) ||
                ({in_channel_o, out_y_o, out_x_o,
                  kernel_y_o, kernel_x_o} !== 24'd0)) begin

                $display(
                    "[FAIL %0d] expected=%016b actual=%016b group=%0d/%0d",
                    test_number,
                    expected_status,
                    actual_status,
                    out_channel_group_o,
                    out_channel_group_count_o
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS %0d] run=%0d done=%0d last=%0d group=%0d/%0d",
                    test_number,
                    run_o,
                    done_o,
                    last_index_o,
                    out_channel_group_o,
                    out_channel_group_count_o
                );
            end
        end
    endtask

    initial begin
        clk       = 1'b0;
        rst_n     = 1'b1;
        start_i   = 1'b0;
        advance_i = 1'b0;

        // 실제 Output Channel 5개 → Group 2개
        // 나머지 반복 크기는 모두 1
        out_channel_count_i = 7'd5;
        in_channel_count_i  = 7'd1;
        output_size_i       = 6'd1;
        kernel_size_i       = 4'd1;

        error_count = 0;

        // Test 1: 동기식 Reset
        @(negedge clk);
        rst_n = 1'b0;

        @(posedge clk);
        check_status(
            {3'b000, 7'd2, 6'd0},  // Reset 후 Group 0
            32'd1
        );

        // Test 2: 연산 시작, Group 0
        @(negedge clk);
        rst_n   = 1'b1;
        start_i = 1'b1;

        @(posedge clk);
        check_status(
            {3'b100, 7'd2, 6'd0},  // Group 0 연산 시작
            32'd2
        );

        // Test 3: 한 번 증가하여 마지막 Group 1
        @(negedge clk);
        start_i   = 1'b0;
        advance_i = 1'b1;

        @(posedge clk);
        check_status(
            {3'b101, 7'd2, 6'd1},  // 마지막 Group 1
            32'd3
        );

        // Test 4: advance=0이면 마지막 좌표 유지
        @(negedge clk);
        advance_i = 1'b0;

        @(posedge clk);
        check_status(
            {3'b101, 7'd2, 6'd1},  // advance 없이 좌표 유지
            32'd4
        );

        // Test 5: 마지막 Group에서 advance하면 DONE
        @(negedge clk);
        advance_i = 1'b1;

        @(posedge clk);
        check_status(
            {3'b011, 7'd2, 6'd1},  // 마지막 Group 처리 완료
            32'd5
        );

        // Test 6: DONE은 1클럭 후 IDLE
        @(negedge clk);
        advance_i = 1'b0;

        @(posedge clk);
        check_status(
            {3'b001, 7'd2, 6'd1},  // DONE 이후 IDLE
            32'd6
        );

        // Conv3: 실제 Output Channel 1개 → Group 1개
        @(negedge clk);
        out_channel_count_i = 7'd1;
        start_i             = 1'b1;

        // Test 7: 첫 Group이면서 동시에 마지막 Group
        @(posedge clk);
        check_status(
            {3'b101, 7'd1, 6'd0},  // Conv3의 유일한 Group
            32'd7
        );

        // Test 8: 유일한 Group 처리 완료
        @(negedge clk);
        start_i   = 1'b0;
        advance_i = 1'b1;

        @(posedge clk);
        check_status(
            {3'b011, 7'd1, 6'd0},  // Conv3 Group 처리 완료
            32'd8
        );

        // Test 9: Reset 후 Group 좌표 0
        @(negedge clk);
        advance_i = 1'b0;
        rst_n     = 1'b0;

        @(posedge clk);
        check_status(
            {3'b001, 7'd1, 6'd0},  // Reset 후 Conv3 Group 0
            32'd9
        );

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL GROUP LOOP CONTROLLER TESTS PASSED");
            $display("========================================");
        end
        else begin
            $display("========================================");
            $display(
                "GROUP LOOP TEST FAILED: %0d error(s)",
                error_count
            );
            $display("========================================");
        end

        $finish;
    end

endmodule
