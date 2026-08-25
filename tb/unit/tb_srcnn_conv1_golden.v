`timescale 1ns / 1ps

module tb_srcnn_conv1_golden;

    localparam ACTIVATION_COUNT = 1024;
    localparam WEIGHT_COUNT     = 1296;
    localparam BIAS_COUNT       = 64;
    localparam EXPECTED_COUNT   = 65536;
    localparam RESULT_GROUPS    = 16384;

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
    reg [5:0] requant_shift_i;

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

    wire signed [15:0] requant_pe0_o;
    wire signed [15:0] requant_pe1_o;
    wire signed [15:0] requant_pe2_o;
    wire signed [15:0] requant_pe3_o;
    wire               requant_valid_o;

    wire [5:0] result_out_channel_group_o;
    wire [4:0] result_y_o;
    wire [4:0] result_x_o;
    wire [3:0] result_pe_enable_o;

    reg signed [15:0] activation_mem [0:ACTIVATION_COUNT-1];
    reg        [63:0] weight_mem     [0:WEIGHT_COUNT-1];
    reg signed [31:0] bias_mem       [0:BIAS_COUNT-1];
    reg signed [47:0] expected_mem   [0:EXPECTED_COUNT-1];
    reg signed [15:0] relu_expected_mem [0:EXPECTED_COUNT-1];

    integer result_group_count;
    integer compared_value_count;
    integer mismatch_count;
    integer lane;
    integer output_channel;
    integer expected_addr;

    reg signed [47:0] actual_accumulator;
    reg signed [15:0] actual_requant;

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
        .requant_shift_i           (requant_shift_i),

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

        .requant_pe0_o             (requant_pe0_o),
        .requant_pe1_o             (requant_pe1_o),
        .requant_pe2_o             (requant_pe2_o),
        .requant_pe3_o             (requant_pe3_o),
        .requant_valid_o           (requant_valid_o),

        .result_out_channel_group_o(result_out_channel_group_o),
        .result_y_o                (result_y_o),
        .result_x_o                (result_x_o),
        .result_pe_enable_o        (result_pe_enable_o)
    );

    always #5 clk = ~clk;

    // 실제 Conv1 HEX 파일 적재
    initial begin
        $readmemh(
            "data/single_tile/input_y.hex",
            activation_mem
        );

        $readmemh(
            "data/pe4_weights/conv1_weight_pe4.hex",
            weight_mem
        );

        $readmemh(
            "data/single_tile/conv1_bias.hex",
            bias_mem
        );

        $readmemh(
            "data/single_tile/conv1_acc_expected.hex",
            expected_mem
        );

        $readmemh(
            "data/single_tile/relu1_expected.hex",
            relu_expected_mem
        );

    end

    // 1-Clock Activation BRAM
    always @(posedge clk) begin
        if (!rst_n)
            activation_bram_data_i <= 16'sd0;
        else if (activation_bram_en_o)
            activation_bram_data_i <=
                activation_mem[activation_bram_addr_o];
    end

    // 1-Clock Packed Weight BRAM
    always @(posedge clk) begin
        if (!rst_n)
            weight_word_i <= 64'd0;
        else if (weight_bram_en_o)
            weight_word_i <= weight_mem[weight_word_addr_o];
    end

    // 1-Clock Bias BRAM
    always @(posedge clk) begin
        if (!rst_n)
            bias_bram_data_i <= 32'sd0;
        else if (bias_bram_en_o)
            bias_bram_data_i <= bias_mem[bias_bram_addr_o];
    end

    // 지정된 PE Lane의 INT48 accumulator를 즉시 선택
    function signed [47:0] select_accumulator;
        input integer lane_i;
        begin
            case (lane_i)
                0: select_accumulator = accumulator0_o;
                1: select_accumulator = accumulator1_o;
                2: select_accumulator = accumulator2_o;
                3: select_accumulator = accumulator3_o;
                default: select_accumulator = 48'sd0;
            endcase
        end
    endfunction

    // 실제 Conv1 INT48 결과와 Golden 비교
    always @(posedge clk) begin
        if (!rst_n) begin
            result_group_count   <= 0;
            compared_value_count = 0;
        end
        else if (acc_valid_o) begin
            if (requant_valid_o !== 1'b1) begin
                mismatch_count = mismatch_count + 1;
                $display("[FAIL] Requant Valid is not aligned with Acc Valid");
            end
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if (result_pe_enable_o[lane]) begin
                    output_channel =
                        result_out_channel_group_o * 4 + lane;

                    expected_addr =
                        output_channel * 1024 +
                        result_y_o * 32 +
                        result_x_o;
					
					// 현재 Lane의 실제 accumulator를 즉시 선택
                    actual_accumulator =
                        select_accumulator(lane);

                    // 현재 PE Lane의 INT16 Requant 결과 선택
                    case (lane)
                        0: actual_requant = requant_pe0_o;
                        1: actual_requant = requant_pe1_o;
                        2: actual_requant = requant_pe2_o;
                        3: actual_requant = requant_pe3_o;
                        default: actual_requant = 16'sd0;
                    endcase

                    if (actual_accumulator !==
                        expected_mem[expected_addr]) begin

                        mismatch_count = mismatch_count + 1;

                        if (mismatch_count <= 10) begin
                            $display(
                                "[FAIL] oc=%0d y=%0d x=%0d actual=%0d expected=%0d",
                                output_channel,
                                result_y_o,
                                result_x_o,
                                actual_accumulator,
                                expected_mem[expected_addr]
                            );
                        end
                    end

                    // 실제 Requant 결과와 Conv1 ReLU Golden 비교
                    if (actual_requant !==
                        relu_expected_mem[expected_addr]) begin

                        mismatch_count = mismatch_count + 1;

                        if (mismatch_count <= 10) begin
                            $display(
                                "[FAIL][REQUANT] oc=%0d y=%0d x=%0d actual=%0d expected=%0d",
                                output_channel,
                                result_y_o,
                                result_x_o,
                                actual_requant,
                                relu_expected_mem[expected_addr]
                            );
                        end
                    end

                    compared_value_count = compared_value_count + 1;
                end
            end

            result_group_count <= result_group_count + 1;

            if ((result_group_count != 0) &&
                ((result_group_count % 2048) == 0)) begin
                $display(
                    "[INFO] Result groups checked: %0d / %0d",
                    result_group_count,
                    RESULT_GROUPS
                );
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start_i = 1'b0;

        mismatch_count = 0;

        // Conv1: 1→64 Channel, 9×9, Same Padding
        out_channel_count_i = 7'd64;
        in_channel_count_i  = 7'd1;
        output_size_i       = 6'd32;
        kernel_size_i       = 4'd9;
        pad_i               = 4'd4;

        weight_word_base_addr_i = 16'd0;
        bias_base_addr_i        = 16'd0;

        // Conv1 Acc F29를 Output F15로 변환
        requant_shift_i = 6'd14;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        start_i = 1'b1;

        @(negedge clk);
        start_i = 1'b0;

        wait (done_o == 1'b1);

        // 마지막 acc_valid 및 Monitor 갱신 대기
        repeat (2) @(posedge clk);
        #1;

        $display("========================================");
        $display("Conv1 Full Golden Test Completed");
        $display(
            "result_group_count   = %0d / %0d",
            result_group_count,
            RESULT_GROUPS
        );
        $display(
            "compared_value_count = %0d / %0d",
            compared_value_count,
            EXPECTED_COUNT
        );
        $display("mismatch_count       = %0d", mismatch_count);

        if ((result_group_count == RESULT_GROUPS) &&
            (compared_value_count == EXPECTED_COUNT) &&
            (mismatch_count == 0))
            $display("[PASS] Conv1 INT48 and Requant Golden mismatch = 0");
        else
            $display("[FAIL] Conv1 INT48/Requant Golden test failed");

        $display("========================================");

        $finish;
    end

    // 예상 Simulation 시간보다 충분히 긴 Timeout
    initial begin
        #100000000;
        $display("[FAIL] Conv1 Golden simulation timeout");
        $finish;
    end

endmodule