`timescale 1ns / 1ps

module tb_srcnn_layer_controller;

    reg clk;
    reg rst_n;
    reg start_i;
    reg layer_done_i;

    wire       layer_start_o;
    wire       run_o;
    wire       done_o;
    wire [1:0] layer_index_o;

    wire [6:0]  out_channel_count_o;
    wire [6:0]  in_channel_count_o;
    wire [5:0]  output_size_o;
    wire [3:0]  kernel_size_o;
    wire [3:0]  pad_o;
    wire [5:0]  requant_shift_o;
    wire [15:0] weight_word_base_addr_o;
    wire [15:0] bias_base_addr_o;

    wire [1:0] activation_source_o;
    wire       feature_write_bank_o;

    integer error_count;

    srcnn_layer_controller dut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .start_i                (start_i),
        .layer_done_i           (layer_done_i),

        .layer_start_o          (layer_start_o),
        .run_o                  (run_o),
        .done_o                 (done_o),
        .layer_index_o          (layer_index_o),

        .out_channel_count_o    (out_channel_count_o),
        .in_channel_count_o     (in_channel_count_o),
        .output_size_o          (output_size_o),
        .kernel_size_o          (kernel_size_o),
        .pad_o                  (pad_o),
        .requant_shift_o        (requant_shift_o),
        .weight_word_base_addr_o(weight_word_base_addr_o),
        .bias_base_addr_o       (bias_base_addr_o),

        .activation_source_o    (activation_source_o),
        .feature_write_bank_o   (feature_write_bank_o)
    );

    // 10ns Clock
    always #5 clk = ~clk;

    // 현재 Layer의 고정 설정값 검사
    task check_layer_config;
        input [1:0] expected_layer;
        begin
            case (expected_layer)
                2'd0: begin
                    if ((layer_index_o            !== 2'd0)  ||
                        (out_channel_count_o      !== 7'd64) ||
                        (in_channel_count_o       !== 7'd1)  ||
                        (output_size_o            !== 6'd32) ||
                        (kernel_size_o            !== 4'd9)  ||
                        (pad_o                    !== 4'd4)  ||
                        (requant_shift_o          !== 6'd14) ||
                        (weight_word_base_addr_o  !== 16'd0) ||
                        (bias_base_addr_o         !== 16'd0) ||
                        (activation_source_o      !== 2'd0)  ||
                        (feature_write_bank_o     !== 1'b0)) begin

                        error_count = error_count + 1;
                        $display("[FAIL] Conv1 configuration mismatch");
                    end
                    else
                        $display("[PASS] Conv1 configuration");
                end

                2'd1: begin
                    if ((layer_index_o            !== 2'd1)    ||
                        (out_channel_count_o      !== 7'd32)   ||
                        (in_channel_count_o       !== 7'd64)   ||
                        (output_size_o            !== 6'd32)   ||
                        (kernel_size_o            !== 4'd5)    ||
                        (pad_o                    !== 4'd2)    ||
                        (requant_shift_o          !== 6'd16)   ||
                        (weight_word_base_addr_o  !== 16'd1296)||
                        (bias_base_addr_o         !== 16'd64)  ||
                        (activation_source_o      !== 2'd1)    ||
                        (feature_write_bank_o     !== 1'b1)) begin

                        error_count = error_count + 1;
                        $display("[FAIL] Conv2 configuration mismatch");
                    end
                    else
                        $display("[PASS] Conv2 configuration");
                end

                2'd2: begin
                    if ((layer_index_o            !== 2'd2)     ||
                        (out_channel_count_o      !== 7'd1)     ||
                        (in_channel_count_o       !== 7'd32)    ||
                        (output_size_o            !== 6'd32)    ||
                        (kernel_size_o            !== 4'd5)     ||
                        (pad_o                    !== 4'd2)     ||
                        (requant_shift_o          !== 6'd14)    ||
                        (weight_word_base_addr_o  !== 16'd14096)||
                        (bias_base_addr_o         !== 16'd96)   ||
                        (activation_source_o      !== 2'd2)     ||
                        (feature_write_bank_o     !== 1'b0)) begin

                        error_count = error_count + 1;
                        $display("[FAIL] Conv3 configuration mismatch");
                    end
                    else
                        $display("[PASS] Conv3 configuration");
                end

                default: begin
                    error_count = error_count + 1;
                    $display("[FAIL] Invalid expected layer");
                end
            endcase
        end
    endtask

    // START_LAYER 상태 출력 검사
    task check_layer_start;
        input [1:0] expected_layer;
        begin
            if ((layer_start_o !== 1'b1) ||
                (run_o         !== 1'b1) ||
                (done_o        !== 1'b0)) begin

                error_count = error_count + 1;
                $display(
                    "[FAIL] Layer %0d start signals: start=%b run=%b done=%b",
                    expected_layer,
                    layer_start_o,
                    run_o,
                    done_o
                );
            end
            else
                $display(
                    "[PASS] Layer %0d start pulse",
                    expected_layer
                );

            check_layer_config(expected_layer);
        end
    endtask

    // WAIT_LAYER 상태 출력 검사
    task check_layer_wait;
        input [1:0] expected_layer;
        begin
            if ((layer_start_o !== 1'b0) ||
                (run_o         !== 1'b1) ||
                (done_o        !== 1'b0) ||
                (layer_index_o !== expected_layer)) begin

                error_count = error_count + 1;
                $display(
                    "[FAIL] Layer %0d wait signals",
                    expected_layer
                );
            end
            else
                $display(
                    "[PASS] Layer %0d wait state held",
                    expected_layer
                );
        end
    endtask

    initial begin
        clk          = 1'b0;
        rst_n        = 1'b0;
        start_i      = 1'b0;
        layer_done_i = 1'b0;
        error_count  = 0;

        // Reset 유지
        repeat (3) @(negedge clk);

        if ((layer_start_o !== 1'b0) ||
            (run_o         !== 1'b0) ||
            (done_o        !== 1'b0) ||
            (layer_index_o !== 2'd0)) begin

            error_count = error_count + 1;
            $display("[FAIL] Reset state");
        end
        else
            $display("[PASS] Reset state");

        rst_n = 1'b1;

        // 전체 SRCNN 시작
        @(negedge clk);
        start_i = 1'b1;

        @(negedge clk);
        #1;
        check_layer_start(2'd0);
        start_i = 1'b0;

        // Conv1 WAIT 상태
        @(negedge clk);
        #1;
        check_layer_wait(2'd0);

        // 완료 신호가 없으면 WAIT 상태 유지
        repeat (2) begin
            @(negedge clk);
            #1;
            check_layer_wait(2'd0);
        end

        // Conv1 완료 → Conv2 시작
        layer_done_i = 1'b1;

        @(negedge clk);
        #1;
        check_layer_start(2'd1);
        layer_done_i = 1'b0;

        @(negedge clk);
        #1;
        check_layer_wait(2'd1);

        // Conv2 완료 → Conv3 시작
        layer_done_i = 1'b1;

        @(negedge clk);
        #1;
        check_layer_start(2'd2);
        layer_done_i = 1'b0;

        @(negedge clk);
        #1;
        check_layer_wait(2'd2);

        // Conv3 완료 → 전체 DONE
        layer_done_i = 1'b1;

        @(negedge clk);
        #1;
        layer_done_i = 1'b0;

        if ((layer_start_o !== 1'b0) ||
            (run_o         !== 1'b0) ||
            (done_o        !== 1'b1) ||
            (layer_index_o !== 2'd2)) begin

            error_count = error_count + 1;
            $display("[FAIL] Network done pulse");
        end
        else
            $display("[PASS] Network done pulse");

        // DONE은 한 Clock 뒤 IDLE로 복귀
        @(negedge clk);
        #1;

        if ((layer_start_o !== 1'b0) ||
            (run_o         !== 1'b0) ||
            (done_o        !== 1'b0)) begin

            error_count = error_count + 1;
            $display("[FAIL] Return to IDLE");
        end
        else
            $display("[PASS] Return to IDLE");

        // 다시 시작하면 Conv1부터 실행
        start_i = 1'b1;

        @(negedge clk);
        #1;
        check_layer_start(2'd0);
        start_i = 1'b0;

        $display("========================================");
        $display("SRCNN Layer Controller Test Completed");
        $display("error_count = %0d", error_count);

        if (error_count == 0)
            $display("[PASS] All layer controller checks passed");
        else
            $display("[FAIL] Layer controller test failed");

        $display("========================================");

        $finish;
    end

    // 무한 Simulation 방지
    initial begin
        #2000;
        $display("[FAIL] Layer controller simulation timeout");
        $finish;
    end

endmodule
