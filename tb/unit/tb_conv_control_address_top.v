`timescale 1ns / 1ps

module tb_conv_control_address_top;

    reg clk;
    reg rst_n;
    reg start_i;
    reg advance_i;

    reg [6:0]  out_channel_count_i;
    reg [6:0]  in_channel_count_i;
    reg [5:0]  output_size_i;
    reg [3:0]  kernel_size_i;
    reg [3:0]  pad_i;
    reg [15:0] weight_base_addr_i;

    wire       run_o;
    wire       done_o;
    wire       last_index_o;

    wire [5:0] out_channel_o;
    wire [5:0] in_channel_o;
    wire [4:0] out_y_o;
    wire [4:0] out_x_o;
    wire [3:0] kernel_y_o;
    wire [3:0] kernel_x_o;

    wire        padding_o;
    wire [15:0] activation_addr_o;
    wire [15:0] weight_addr_o;

    integer error_count;

    conv_control_address_top dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .start_i            (start_i),
        .advance_i          (advance_i),

        .out_channel_count_i(out_channel_count_i),
        .in_channel_count_i (in_channel_count_i),
        .output_size_i      (output_size_i),
        .kernel_size_i      (kernel_size_i),
        .pad_i              (pad_i),
        .weight_base_addr_i (weight_base_addr_i),

        .run_o              (run_o),
        .done_o             (done_o),
        .last_index_o       (last_index_o),

        .out_channel_o      (out_channel_o),
        .in_channel_o       (in_channel_o),
        .out_y_o            (out_y_o),
        .out_x_o            (out_x_o),
        .kernel_y_o         (kernel_y_o),
        .kernel_x_o         (kernel_x_o),

        .padding_o          (padding_o),
        .activation_addr_o  (activation_addr_o),
        .weight_addr_o      (weight_addr_o)
    );

    // 10ns 주기의 Clock
    always #5 clk = ~clk;

    task check_case;
        input [31:0] test_number;
        input        expected_run;
        input        expected_done;
        input        expected_last;
        input [3:0]  expected_ky;
        input [3:0]  expected_kx;
        input        expected_padding;
        input [15:0] expected_activation_addr;
        input [15:0] expected_weight_addr;

        begin
            #1;

            if ((run_o             !== expected_run)             ||
                (done_o            !== expected_done)            ||
                (last_index_o      !== expected_last)            ||
                (kernel_y_o        !== expected_ky)              ||
                (kernel_x_o        !== expected_kx)              ||
                (padding_o         !== expected_padding)         ||
                (activation_addr_o !== expected_activation_addr) ||
                (weight_addr_o     !== expected_weight_addr)     ||
                (out_channel_o     !== 6'd0)                     ||
                (in_channel_o      !== 6'd0)                     ||
                (out_y_o           !== 5'd0)                     ||
                (out_x_o           !== 5'd0)) begin

                $display(
                    "[FAIL %0d] run=%0d done=%0d last=%0d kernel=(%0d,%0d) pad=%0d act=%0d weight=%0d",
                    test_number, run_o, done_o, last_index_o,
                    kernel_y_o, kernel_x_o, padding_o,
                    activation_addr_o, weight_addr_o
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS %0d] kernel=(%0d,%0d) pad=%0d act=%0d weight=%0d",
                    test_number, kernel_y_o, kernel_x_o,
                    padding_o, activation_addr_o, weight_addr_o
                );
            end
        end
    endtask

    task pulse_start;
        begin
            @(negedge clk);
            start_i = 1'b1;

            @(posedge clk);
            #1;
            start_i = 1'b0;
        end
    endtask

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
        rst_n     = 1'b1;
        start_i   = 1'b0;
        advance_i = 1'b0;

        // 1×1 출력, 2×2 Kernel, Padding=1
        out_channel_count_i = 7'd1;
        in_channel_count_i  = 7'd1;
        output_size_i       = 6'd1;
        kernel_size_i       = 4'd2;
        pad_i               = 4'd1;
        weight_base_addr_i  = 16'd100;

        error_count = 0;

        // Test 1: Sync Active-Low Reset
        @(negedge clk);
        rst_n = 1'b0;

        @(posedge clk);
        #1;

        check_case(
            32'd1, 1'b0, 1'b0, 1'b0,
            4'd0, 4'd0, 1'b1, 16'd0, 16'd100
        );

        @(negedge clk);
        rst_n = 1'b1;

        // Test 2: Start 후 첫 번째 좌표
        pulse_start;

        check_case(
            32'd2, 1'b1, 1'b0, 1'b0,
            4'd0, 4'd0, 1'b1, 16'd0, 16'd100
        );

        // Test 3: kernel=(0,1)
        pulse_advance;

        check_case(
            32'd3, 1'b1, 1'b0, 1'b0,
            4'd0, 4'd1, 1'b1, 16'd0, 16'd101
        );

        // Test 4: kernel=(1,0)
        pulse_advance;

        check_case(
            32'd4, 1'b1, 1'b0, 1'b0,
            4'd1, 4'd0, 1'b1, 16'd0, 16'd102
        );

        // Test 5: kernel=(1,1), 실제 입력 좌표=(0,0)
        pulse_advance;

        check_case(
            32'd5, 1'b1, 1'b0, 1'b1,
            4'd1, 4'd1, 1'b0, 16'd0, 16'd103
        );

        // Test 6: 마지막 좌표 처리 후 DONE
        pulse_advance;

        check_case(
            32'd6, 1'b0, 1'b1, 1'b1,
            4'd1, 4'd1, 1'b0, 16'd0, 16'd103
        );

        // Test 7: DONE에서 IDLE 복귀
        @(posedge clk);

        check_case(
            32'd7, 1'b0, 1'b0, 1'b1,
            4'd1, 4'd1, 1'b0, 16'd0, 16'd103
        );

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL CONTROL-ADDRESS TOP TESTS PASSED");
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
