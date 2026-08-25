`timescale 1ns / 1ps

module tb_conv_group_data_supply_top;

    reg clk;
    reg rst_n;
    reg start_i;

    reg core_busy_i;
    reg core_done_i;

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

    wire        run_o;
    wire        done_o;
    wire        last_index_o;

    wire [6:0]  out_channel_group_count_o;
    wire [5:0]  out_channel_group_o;
    wire [5:0]  in_channel_o;
    wire [4:0]  out_y_o;
    wire [4:0]  out_x_o;
    wire [3:0]  kernel_y_o;
    wire [3:0]  kernel_x_o;

    wire        activation_bram_en_o;
    wire [15:0] activation_bram_addr_o;
    wire        padding_o;

    wire        weight_bram_en_o;
    wire [15:0] weight_word_addr_o;

    wire        bias_bram_en_o;
    wire [15:0] bias_bram_addr_o;

    wire        op_start_o;
    wire        bias_load_o;
    wire        mac_valid_o;
    wire        mac_last_o;

    wire [3:0]  pe_enable_o;

    wire signed [15:0] activation_o;
    wire signed [15:0] weight_pe0_o;
    wire signed [15:0] weight_pe1_o;
    wire signed [15:0] weight_pe2_o;
    wire signed [15:0] weight_pe3_o;

    wire signed [31:0] bias_pe0_o;
    wire signed [31:0] bias_pe1_o;
    wire signed [31:0] bias_pe2_o;
    wire signed [31:0] bias_pe3_o;

    integer error_count;
    integer op_start_count;
    integer mac_count;
    integer activation_read_count;
    integer weight_read_count;
    integer bias_read_count;
    integer done_count;

    conv_group_data_supply_top dut (
        .clk                      (clk),
        .rst_n                    (rst_n),
        .start_i                  (start_i),

        .core_busy_i              (core_busy_i),
        .core_done_i              (core_done_i),

        .out_channel_count_i      (out_channel_count_i),
        .in_channel_count_i       (in_channel_count_i),
        .output_size_i            (output_size_i),
        .kernel_size_i            (kernel_size_i),
        .pad_i                    (pad_i),
        .weight_word_base_addr_i  (weight_word_base_addr_i),
        .bias_base_addr_i         (bias_base_addr_i),

        .activation_bram_data_i   (activation_bram_data_i),
        .weight_word_i            (weight_word_i),
        .bias_bram_data_i         (bias_bram_data_i),

        .run_o                    (run_o),
        .done_o                   (done_o),
        .last_index_o             (last_index_o),

        .out_channel_group_count_o(out_channel_group_count_o),
        .out_channel_group_o      (out_channel_group_o),
        .in_channel_o             (in_channel_o),
        .out_y_o                  (out_y_o),
        .out_x_o                  (out_x_o),
        .kernel_y_o               (kernel_y_o),
        .kernel_x_o               (kernel_x_o),

        .activation_bram_en_o     (activation_bram_en_o),
        .activation_bram_addr_o   (activation_bram_addr_o),
        .padding_o                (padding_o),

        .weight_bram_en_o         (weight_bram_en_o),
        .weight_word_addr_o       (weight_word_addr_o),

        .bias_bram_en_o           (bias_bram_en_o),
        .bias_bram_addr_o         (bias_bram_addr_o),

        .op_start_o               (op_start_o),
        .bias_load_o              (bias_load_o),
        .mac_valid_o              (mac_valid_o),
        .mac_last_o               (mac_last_o),

        .pe_enable_o              (pe_enable_o),

        .activation_o             (activation_o),
        .weight_pe0_o             (weight_pe0_o),
        .weight_pe1_o             (weight_pe1_o),
        .weight_pe2_o             (weight_pe2_o),
        .weight_pe3_o             (weight_pe3_o),

        .bias_pe0_o               (bias_pe0_o),
        .bias_pe1_o               (bias_pe1_o),
        .bias_pe2_o               (bias_pe2_o),
        .bias_pe3_o               (bias_pe3_o)
    );

    // 10ns 주기의 Clock 생성
    always #5 clk = ~clk;

    // 가상의 B파트 상태:
    // op_start_o를 받으면 Busy가 되고,
    // 마지막 MAC 입력을 받으면 Done Pulse를 발생
    always @(posedge clk) begin
        if (!rst_n) begin
            core_busy_i <= 1'b0;
            core_done_i <= 1'b0;
        end
        else begin
            // Done은 한 Clock만 유지
            core_done_i <= 1'b0;

            if (op_start_o)
                // 새로운 Output 연산이 시작되면 Core Busy 활성화
                core_busy_i <= 1'b1;

            if (mac_valid_o && mac_last_o) begin
                // 마지막 MAC 입력을 받으면 Busy 해제 및 Done Pulse 발생
                core_busy_i <= 1'b0;
                core_done_i <= 1'b1;
            end
        end
    end

	// 1-Clock Read Latency를 갖는 가상의 Activation BRAM
    always @(posedge clk) begin
        if (!rst_n)
            activation_bram_data_i <= 16'sd0;
        else if (activation_bram_en_o)
            // 주소를 데이터에 반영해 주소 이동 여부도 함께 확인
            activation_bram_data_i <= 16'sd77 + $signed({1'b0, activation_bram_addr_o});
    end

    // 1-Clock Read Latency를 갖는 가상의 Bias BRAM
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

	// 1-Clock Read Latency를 갖는 가상의 Packed Weight BRAM
    always @(posedge clk) begin
        if (!rst_n)
            weight_word_i <= 64'd0;
        else if (weight_bram_en_o) begin
            case (weight_word_addr_o)
                // Group 0: PE0~PE3 모두 활성화
                16'd100: weight_word_i <= 64'h0044_0033_0022_0011;
                16'd101: weight_word_i <= 64'h0088_0077_0066_0055;
                16'd102: weight_word_i <= 64'h00CC_00BB_00AA_0099;
                16'd103: weight_word_i <= 64'h0110_00FF_00EE_00DD;

                // Group 1: PE0만 활성화되며 PE1~PE3는 0으로 Mask되어야 함
                16'd104: weight_word_i <= 64'h1444_1333_1222_1111;
                16'd105: weight_word_i <= 64'h1888_1777_1666_1555;
                16'd106: weight_word_i <= 64'h1CCC_1BBB_1AAA_1999;
                16'd107: weight_word_i <= 64'h2110_1FFF_1EEE_1DDD;

                // 예상하지 않은 주소를 쉽게 발견하기 위한 값
                default: weight_word_i <= 64'hDEAD_DEAD_DEAD_DEAD;
            endcase
        end
    end

    // 주요 제어 신호와 BRAM Read 발생 횟수를 기록
    always @(posedge clk) begin
        if (!rst_n) begin
            op_start_count        <= 0;
            mac_count             <= 0;
            activation_read_count <= 0;
            weight_read_count     <= 0;
            bias_read_count       <= 0;
            done_count            <= 0;
        end
        else begin
            // 새로운 Output 연산 시작 횟수
            if (op_start_o)
                op_start_count <= op_start_count + 1;

            // B파트에 전달한 유효 MAC 입력 횟수 기록
            if (mac_valid_o)
                mac_count <= mac_count + 1;

            // Activation BRAM Read 횟수
            if (activation_bram_en_o)
                activation_read_count <= activation_read_count + 1;

            // Weight BRAM Read 횟수
            if (weight_bram_en_o)
                weight_read_count <= weight_read_count + 1;

            // 실제 활성 PE의 Bias BRAM Read 횟수
            if (bias_bram_en_o)
                bias_read_count <= bias_read_count + 1;

            // 전체 Layer 완료 횟수
            if (done_o)
                done_count <= done_count + 1;
        end
    end

	// Bias Load 시점에 Group별 PE Mask와 Bias 전달값 검사
    always @(posedge clk) begin
        if (rst_n && bias_load_o) begin
            case (out_channel_group_o)
                6'd0: begin
                    if ((pe_enable_o !== 4'b1111) ||
                        (bias_pe0_o !== 32'sd1000) ||
                        (bias_pe1_o !== 32'sd2000) ||
                        (bias_pe2_o !== 32'sd3000) ||
                        (bias_pe3_o !== 32'sd4000)) begin
                        error_count = error_count + 1;
                        $display(
                            "[FAIL] Group 0 Bias/PE: mask=%b bias=%0d,%0d,%0d,%0d",
                            pe_enable_o,
                            bias_pe0_o, bias_pe1_o,
                            bias_pe2_o, bias_pe3_o
                        );
                    end
                    else begin
                        $display(
                            "[PASS] Group 0 Bias/PE: mask=%b bias=%0d,%0d,%0d,%0d",
                            pe_enable_o,
                            bias_pe0_o, bias_pe1_o,
                            bias_pe2_o, bias_pe3_o
                        );
                    end
                end

                6'd1: begin
                    if ((pe_enable_o !== 4'b0001) ||
                        (bias_pe0_o !== 32'sd5000) ||
                        (bias_pe1_o !== 32'sd0) ||
                        (bias_pe2_o !== 32'sd0) ||
                        (bias_pe3_o !== 32'sd0)) begin
                        error_count = error_count + 1;
                        $display(
                            "[FAIL] Group 1 Bias/PE: mask=%b bias=%0d,%0d,%0d,%0d",
                            pe_enable_o,
                            bias_pe0_o, bias_pe1_o,
                            bias_pe2_o, bias_pe3_o
                        );
                    end
                    else begin
                        $display(
                            "[PASS] Group 1 Bias/PE: mask=%b bias=%0d,%0d,%0d,%0d",
                            pe_enable_o,
                            bias_pe0_o, bias_pe1_o,
                            bias_pe2_o, bias_pe3_o
                        );
                    end
                end

                default: begin
                    error_count = error_count + 1;
                    $display(
                        "[FAIL] Unexpected Output Channel Group: %0d",
                        out_channel_group_o
                    );
                end
            endcase
        end
    end

	// 한 번의 MAC 공급값을 예상 좌표 및 데이터와 비교
    task check_mac_values;
        input integer expected_mac;
        input [5:0] expected_group;
        input [3:0] expected_kernel_y;
        input [3:0] expected_kernel_x;
        input       expected_padding;
        input [3:0] expected_pe_enable;
        input signed [15:0] expected_activation;
        input signed [15:0] expected_weight_pe0;
        input signed [15:0] expected_weight_pe1;
        input signed [15:0] expected_weight_pe2;
        input signed [15:0] expected_weight_pe3;
        begin
            if ((out_channel_group_o !== expected_group) ||
                (kernel_y_o !== expected_kernel_y) ||
                (kernel_x_o !== expected_kernel_x) ||
                (padding_o !== expected_padding) ||
                (pe_enable_o !== expected_pe_enable) ||
                (activation_o !== expected_activation) ||
                (weight_pe0_o !== expected_weight_pe0) ||
                (weight_pe1_o !== expected_weight_pe1) ||
                (weight_pe2_o !== expected_weight_pe2) ||
                (weight_pe3_o !== expected_weight_pe3)) begin

                error_count = error_count + 1;

                $display(
                    "[FAIL] MAC %0d: group=%0d kernel=(%0d,%0d) pad=%b mask=%b act=%0d weights=%h,%h,%h,%h",
                    expected_mac,
                    out_channel_group_o,
                    kernel_y_o,
                    kernel_x_o,
                    padding_o,
                    pe_enable_o,
                    activation_o,
                    weight_pe0_o,
                    weight_pe1_o,
                    weight_pe2_o,
                    weight_pe3_o
                );
            end
            else begin
                $display(
                    "[PASS] MAC %0d: group=%0d kernel=(%0d,%0d) pad=%b mask=%b",
                    expected_mac,
                    out_channel_group_o,
                    kernel_y_o,
                    kernel_x_o,
                    padding_o,
                    pe_enable_o
                );
            end
        end
    endtask

	// mac_count는 증가되기 전 값이므로 첫 MAC에서 0
    always @(posedge clk) begin
        if (rst_n && mac_valid_o) begin
            case (mac_count)
                0: check_mac_values(
                    1, 6'd0, 4'd0, 4'd0, 1'b1, 4'b1111,
                    16'sd0, 16'h0011, 16'h0022, 16'h0033, 16'h0044
                );

                1: check_mac_values(
                    2, 6'd0, 4'd0, 4'd1, 1'b1, 4'b1111,
                    16'sd0, 16'h0055, 16'h0066, 16'h0077, 16'h0088
                );

                2: check_mac_values(
                    3, 6'd0, 4'd1, 4'd0, 1'b1, 4'b1111,
                    16'sd0, 16'h0099, 16'h00AA, 16'h00BB, 16'h00CC
                );

                3: check_mac_values(
                    4, 6'd0, 4'd1, 4'd1, 1'b0, 4'b1111,
                    16'sd77, 16'h00DD, 16'h00EE, 16'h00FF, 16'h0110
                );

                4: check_mac_values(
                    5, 6'd1, 4'd0, 4'd0, 1'b1, 4'b0001,
                    16'sd0, 16'h1111, 16'h0000, 16'h0000, 16'h0000
                );

                5: check_mac_values(
                    6, 6'd1, 4'd0, 4'd1, 1'b1, 4'b0001,
                    16'sd0, 16'h1555, 16'h0000, 16'h0000, 16'h0000
                );

                6: check_mac_values(
                    7, 6'd1, 4'd1, 4'd0, 1'b1, 4'b0001,
                    16'sd0, 16'h1999, 16'h0000, 16'h0000, 16'h0000
                );

                7: check_mac_values(
                    8, 6'd1, 4'd1, 4'd1, 1'b0, 4'b0001,
                    16'sd77, 16'h1DDD, 16'h0000, 16'h0000, 16'h0000
                );

                default: begin
                    error_count = error_count + 1;
                    $display("[FAIL] Unexpected extra MAC");
                end
            endcase
        end
    end

    // 테스트 입력 초기화, Reset 및 Layer Start Pulse 발생
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start_i = 1'b0;

        error_count = 0;

        // 작은 2-Group 합성곱 시험 설정
        // Output Channel 5개
        out_channel_count_i = 7'd5;

        // Input Channel 1개
        in_channel_count_i = 7'd1;

        // Output Feature Map 크기 1×1
        output_size_i = 6'd1;

        // Kernel 크기 2×2, 커널의 한 변의 크기를 의미
        kernel_size_i = 4'd2;

        // Padding 크기 1
        pad_i = 4'd1;

        // Packed Weight BRAM 시작 주소 100
        weight_word_base_addr_i = 16'd100;

        // Bias BRAM 시작 주소 200
        bias_base_addr_i = 16'd200;

        // Reset을 충분히 유지한 후 Clock 하강 Edge에서 해제
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // 전체 Layer를 시작하는 1-Clock Pulse
        @(negedge clk);
        start_i = 1'b1;

        @(negedge clk);
        start_i = 1'b0;

        // 전체 Layer 완료를 기다림
        wait (done_o == 1'b1);

        // Monitor의 done_count 갱신까지 기다림
        @(posedge clk);
        #1;

		// 전체 제어 신호 및 BRAM Read 발생 횟수 검사
        if ((out_channel_group_count_o !== 7'd2) ||
            (op_start_count !== 2) ||
            (mac_count !== 8) ||
            (activation_read_count !== 8) ||
            (weight_read_count !== 8) ||
            (bias_read_count !== 5) ||
            (done_count !== 1)) begin

            error_count = error_count + 1;

            $display(
                "[FAIL] Count check: groups=%0d op=%0d mac=%0d act=%0d weight=%0d bias=%0d done=%0d",
                out_channel_group_count_o,
                op_start_count,
                mac_count,
                activation_read_count,
                weight_read_count,
                bias_read_count,
                done_count
            );
        end
        else begin
            $display("[PASS] Control and BRAM Read counts passed");
        end

        $display("========================================");
        $display("Top Module Test Completed");
        $display("op_start_count        = %0d", op_start_count);
        $display("mac_count             = %0d", mac_count);
        $display("activation_read_count = %0d", activation_read_count);
        $display("weight_read_count     = %0d", weight_read_count);
        $display("bias_read_count       = %0d", bias_read_count);
        $display("done_count            = %0d", done_count);
        $display("========================================");
		$display("error_count           = %0d", error_count);
        if (error_count == 0)
            $display("[PASS] All Top Module checks passed");
        else
            $display("[FAIL] Total errors = %0d", error_count);

        $finish;
    end

	// DUT가 완료되지 않을 경우 무한 Simulation을 방지
    initial begin
        #10000;
        $display("[FAIL] Simulation timeout: done_o was not asserted");
        $finish;
    end

endmodule
