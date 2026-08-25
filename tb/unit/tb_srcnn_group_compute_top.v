`timescale 1ns / 1ps

module tb_srcnn_group_compute_top;

    reg clk;
    reg rst_n;
    reg start_i;

    reg [6:0]  out_channel_count_i;
    reg [6:0]  in_channel_count_i;
    reg [5:0]  output_size_i;
    reg [3:0]  kernel_size_i;
    reg [3:0]  pad_i;
    reg [15:0] weight_word_base_addr_i;
    reg [15:0] bias_base_addr_i;

    reg signed [15:0] activation_bram_data_i;
    reg        [63:0] weight_word_i;
    reg signed [31:0] bias_bram_data_i;

    wire        activation_bram_en_o;
    wire [15:0] activation_bram_addr_o;

    wire        weight_bram_en_o;
    wire [15:0] weight_word_addr_o;

    wire        bias_bram_en_o;
    wire [15:0] bias_bram_addr_o;

    wire run_o;
    wire done_o;

    wire signed [47:0] accumulator0_o;
    wire signed [47:0] accumulator1_o;
    wire signed [47:0] accumulator2_o;
    wire signed [47:0] accumulator3_o;
    wire               acc_valid_o;

    wire [5:0] result_out_channel_group_o;
    wire [4:0] result_y_o;
    wire [4:0] result_x_o;
    wire [3:0] result_pe_enable_o;

    integer result_count;
    integer error_count;

    srcnn_group_compute_top dut (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .start_i                   (start_i),

        .out_channel_count_i       (out_channel_count_i),
        .in_channel_count_i        (in_channel_count_i),
        .output_size_i             (output_size_i),
        .kernel_size_i             (kernel_size_i),
        .pad_i                     (pad_i),
        .weight_word_base_addr_i   (weight_word_base_addr_i),
        .bias_base_addr_i          (bias_base_addr_i),

        .activation_bram_data_i    (activation_bram_data_i),
        .weight_word_i             (weight_word_i),
        .bias_bram_data_i          (bias_bram_data_i),

        .activation_bram_en_o      (activation_bram_en_o),
        .activation_bram_addr_o    (activation_bram_addr_o),

        .weight_bram_en_o          (weight_bram_en_o),
        .weight_word_addr_o        (weight_word_addr_o),

        .bias_bram_en_o            (bias_bram_en_o),
        .bias_bram_addr_o          (bias_bram_addr_o),

        .run_o                     (run_o),
        .done_o                    (done_o),

        .accumulator0_o            (accumulator0_o),
        .accumulator1_o            (accumulator1_o),
        .accumulator2_o            (accumulator2_o),
        .accumulator3_o            (accumulator3_o),
        .acc_valid_o               (acc_valid_o),

        .result_out_channel_group_o(result_out_channel_group_o),
        .result_y_o                (result_y_o),
        .result_x_o                (result_x_o),
        .result_pe_enable_o        (result_pe_enable_o)
    );

    // 100MHz Clock
    always #5 clk = ~clk;

    // 1-Clock Read Latency Activation BRAM
    always @(posedge clk) begin
        if (!rst_n)
            activation_bram_data_i <= 16'sd0;
        else if (activation_bram_en_o)
            activation_bram_data_i <=
                16'sd77 + $signed({1'b0, activation_bram_addr_o});
    end

    // 1-Clock Read Latency Bias BRAM
    always @(posedge clk) begin
        if (!rst_n)
            bias_bram_data_i <= 32'sd0;
        else if (bias_bram_en_o) begin
            case (bias_bram_addr_o)
                16'd200: bias_bram_data_i <= 32'sd1000;
                16'd201: bias_bram_data_i <= 32'sd2000;
                16'd202: bias_bram_data_i <= 32'sd3000;
                16'd203: bias_bram_data_i <= 32'sd4000;
                16'd204: bias_bram_data_i <= 32'sd5000;
                default: bias_bram_data_i <= -32'sd1;
            endcase
        end
    end

    // 1-Clock Read Latency Packed Weight BRAM
    always @(posedge clk) begin
        if (!rst_n)
            weight_word_i <= 64'd0;
        else if (weight_bram_en_o) begin
            case (weight_word_addr_o)
                // Group 0
                16'd100: weight_word_i <= 64'h0044_0033_0022_0011;
                16'd101: weight_word_i <= 64'h0088_0077_0066_0055;
                16'd102: weight_word_i <= 64'h00CC_00BB_00AA_0099;
                16'd103: weight_word_i <= 64'h0110_00FF_00EE_00DD;

                // Group 1: PE0만 활성
                16'd104: weight_word_i <= 64'h1444_1333_1222_1111;
                16'd105: weight_word_i <= 64'h1888_1777_1666_1555;
                16'd106: weight_word_i <= 64'h1CCC_1BBB_1AAA_1999;
                16'd107: weight_word_i <= 64'h2110_1FFF_1EEE_1DDD;

                default: weight_word_i <=
                    64'hDEAD_DEAD_DEAD_DEAD;
            endcase
        end
    end

    // 실제 B파트의 Group별 INT48 결과 검사
    always @(posedge clk) begin
        if (!rst_n) begin
            result_count <= 0;
        end
        else if (acc_valid_o) begin
            case (result_count)
                0: begin
                    if ((result_out_channel_group_o !== 6'd0) ||
                        (result_y_o !== 5'd0) ||
                        (result_x_o !== 5'd0) ||
                        (result_pe_enable_o !== 4'b1111) ||
                        (accumulator0_o !== 48'sd18017) ||
                        (accumulator1_o !== 48'sd20326) ||
                        (accumulator2_o !== 48'sd22635) ||
                        (accumulator3_o !== 48'sd24944)) begin

                        error_count = error_count + 1;

                        $display(
                            "[FAIL] Group 0: pos=(%0d,%0d) mask=%b acc=%0d,%0d,%0d,%0d",
                            result_y_o,
                            result_x_o,
                            result_pe_enable_o,
                            accumulator0_o,
                            accumulator1_o,
                            accumulator2_o,
                            accumulator3_o
                        );
                    end
                    else begin
                        $display(
                            "[PASS] Group 0: mask=%b acc=%0d,%0d,%0d,%0d",
                            result_pe_enable_o,
                            accumulator0_o,
                            accumulator1_o,
                            accumulator2_o,
                            accumulator3_o
                        );
                    end
                end

                1: begin
                    // Group 1에서는 PE0만 유효하므로 PE1~PE3는 채점 제외
                    if ((result_out_channel_group_o !== 6'd1) ||
                        (result_y_o !== 5'd0) ||
                        (result_x_o !== 5'd0) ||
                        (result_pe_enable_o !== 4'b0001) ||
                        (accumulator0_o !== 48'sd593665)) begin

                        error_count = error_count + 1;

                        $display(
                            "[FAIL] Group 1: pos=(%0d,%0d) mask=%b acc0=%0d",
                            result_y_o,
                            result_x_o,
                            result_pe_enable_o,
                            accumulator0_o
                        );
                    end
                    else begin
                        $display(
                            "[PASS] Group 1: mask=%b acc0=%0d",
                            result_pe_enable_o,
                            accumulator0_o
                        );
                    end
                end

                default: begin
                    error_count = error_count + 1;
                    $display("[FAIL] Unexpected extra accumulator result");
                end
            endcase

            result_count <= result_count + 1;
        end
    end

    // Test Sequence
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start_i = 1'b0;

        error_count = 0;

        out_channel_count_i = 7'd5;
        in_channel_count_i = 7'd1;
        output_size_i = 6'd1;
        kernel_size_i = 4'd2;
        pad_i = 4'd1;

        weight_word_base_addr_i = 16'd100;
        bias_base_addr_i = 16'd200;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        start_i = 1'b1;

        @(negedge clk);
        start_i = 1'b0;

        wait (done_o == 1'b1);

        // 마지막 acc_valid Monitor 갱신 대기
        @(posedge clk);
        #1;

        if (result_count !== 2) begin
            error_count = error_count + 1;
            $display(
                "[FAIL] Result count: expected=2 actual=%0d",
                result_count
            );
        end
        else begin
            $display("[PASS] Result count = 2");
        end

        $display("========================================");
        $display("A+B Integrated Compute Test Completed");
        $display("result_count = %0d", result_count);
        $display("error_count  = %0d", error_count);

        if (error_count == 0)
            $display("[PASS] All A+B integration checks passed");
        else
            $display("[FAIL] Total errors = %0d", error_count);

        $display("========================================");

        $finish;
    end

    // Timeout
    initial begin
        #10000;
        $display("[FAIL] Simulation timeout");
        $finish;
    end

endmodule
