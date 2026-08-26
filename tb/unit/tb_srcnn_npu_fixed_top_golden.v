`timescale 1ns / 1ps

module tb_srcnn_npu_fixed_top_golden;

    localparam CONV1_VALUE_COUNT = 65536;
    localparam CONV2_VALUE_COUNT = 32768;
    localparam CONV3_VALUE_COUNT = 1024;
    localparam FINAL_VALUE_COUNT = 1024;

    reg clk;
    reg rst_n;
    reg start_i;

    reg signed [15:0] input_tile_data_i;

    wire        input_tile_bram_en_o;
    wire [15:0] input_tile_bram_addr_o;

    reg               final_read_en_i;
    reg        [15:0] final_read_addr_i;
    wire signed [15:0] final_read_data_o;

    wire       run_o;
    wire       done_o;
    wire [1:0] layer_index_o;
    wire [1:0] activation_source_o;
    wire       feature_write_bank_o;

    // 전체 32×32 Input Tile
    reg signed [15:0] input_mem [0:1023];

    // 각 Layer의 Requant Golden
    reg signed [15:0] relu1_expected_mem [0:65535];
    reg signed [15:0] relu2_expected_mem [0:32767];
    reg signed [15:0] output_expected_mem [0:1023];

    integer mismatch_count;
    integer conv1_value_count;
    integer conv2_value_count;
    integer conv3_value_count;
    integer final_read_count;

    integer pe_index;
    integer output_channel;
    integer expected_addr;
    integer read_index;

    reg signed [15:0] actual_value;
    reg signed [15:0] expected_value;

    srcnn_npu_fixed_top #(
        .WEIGHT_INIT_FILE(
            "mem_init/srcnn_weights_all.hex"
        ),
        .BIAS_INIT_FILE(
            "mem_init/srcnn_biases_all.hex"
        )
    ) dut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .start_i                (start_i),

        .input_tile_data_i      (input_tile_data_i),

        .input_tile_bram_en_o   (input_tile_bram_en_o),
        .input_tile_bram_addr_o (input_tile_bram_addr_o),

        .final_read_en_i        (final_read_en_i),
        .final_read_addr_i      (final_read_addr_i),
        .final_read_data_o      (final_read_data_o),

        .run_o                  (run_o),
        .done_o                 (done_o),
        .layer_index_o          (layer_index_o),

        .activation_source_o    (activation_source_o),
        .feature_write_bank_o   (feature_write_bank_o)
    );

    // 100MHz Clock
    always #5 clk = ~clk;

    // 실제 FPGA에서도 AXI BRAM으로 구현할 Input Tile의 1-Clock Read 모델
    always @(posedge clk) begin
        if (!rst_n)
            input_tile_data_i <= 16'sd0;
        else if (input_tile_bram_en_o) begin
            if (input_tile_bram_addr_o < 16'd1024)
                input_tile_data_i <=
                    input_mem[input_tile_bram_addr_o];
            else
                input_tile_data_i <= 16'sd0;
        end
    end

    // PE 번호에 따라 내부 NPU의 실제 Requant 결과 선택
    task select_actual_value;
        input integer selected_pe;
        begin
            case (selected_pe)
                0:
                    actual_value =
                        dut.u_srcnn_npu_top.requant_pe0_int;

                1:
                    actual_value =
                        dut.u_srcnn_npu_top.requant_pe1_int;

                2:
                    actual_value =
                        dut.u_srcnn_npu_top.requant_pe2_int;

                3:
                    actual_value =
                        dut.u_srcnn_npu_top.requant_pe3_int;

                default:
                    actual_value = 16'sd0;
            endcase
        end
    endtask

    // 각 Layer의 Requant 출력 Stream을 Golden 데이터와 비교
    always @(posedge clk) begin
        if (!rst_n) begin
            mismatch_count    = 0;
            conv1_value_count = 0;
            conv2_value_count = 0;
            conv3_value_count = 0;
        end
        else begin
            // NPU가 유효 범위를 벗어난 ROM 주소를 생성하지 않는지 확인
            if (dut.weight_read_en_int &&
                (dut.weight_read_addr_int >= 16'd14896)) begin

                mismatch_count = mismatch_count + 1;

                if (mismatch_count <= 10)
                    $display(
                        "[FAIL][WEIGHT ADDR] address=%0d",
                        dut.weight_read_addr_int
                    );
            end

            if (dut.bias_read_en_int &&
                (dut.bias_read_addr_int >= 16'd97)) begin

                mismatch_count = mismatch_count + 1;

                if (mismatch_count <= 10)
                    $display(
                        "[FAIL][BIAS ADDR] address=%0d",
                        dut.bias_read_addr_int
                    );
            end

            if (dut.u_srcnn_npu_top.requant_valid_int) begin
                for (pe_index = 0;
                     pe_index < 4;
                     pe_index = pe_index + 1) begin

                    if (dut.u_srcnn_npu_top
                           .result_pe_enable_int[pe_index]) begin

                        select_actual_value(pe_index);

                        output_channel =
                            (dut.u_srcnn_npu_top
                                .result_group_int * 4) +
                            pe_index;

                        expected_addr =
                            (output_channel * 1024) +
                            (dut.u_srcnn_npu_top
                                .result_y_int * 32) +
                            dut.u_srcnn_npu_top.result_x_int;

                        case (layer_index_o)
                            2'd0: begin
                                expected_value =
                                    relu1_expected_mem[
                                        expected_addr
                                    ];

                                conv1_value_count =
                                    conv1_value_count + 1;
                            end

                            2'd1: begin
                                expected_value =
                                    relu2_expected_mem[
                                        expected_addr
                                    ];

                                conv2_value_count =
                                    conv2_value_count + 1;
                            end

                            2'd2: begin
                                expected_value =
                                    output_expected_mem[
                                        expected_addr
                                    ];

                                conv3_value_count =
                                    conv3_value_count + 1;
                            end

                            default: begin
                                expected_value = 16'sd0;
                                mismatch_count =
                                    mismatch_count + 1;
                            end
                        endcase

                        if (actual_value !== expected_value) begin
                            mismatch_count =
                                mismatch_count + 1;

                            if (mismatch_count <= 10) begin
                                $display(
                                    "[FAIL] layer=%0d oc=%0d y=%0d x=%0d actual=%0d expected=%0d",
                                    layer_index_o,
                                    output_channel,
                                    dut.u_srcnn_npu_top
                                       .result_y_int,
                                    dut.u_srcnn_npu_top
                                       .result_x_int,
                                    actual_value,
                                    expected_value
                                );
                            end
                        end
                    end
                end

                if ((layer_index_o == 2'd0) &&
                    (conv1_value_count != 0) &&
                    ((conv1_value_count % 8192) == 0))
                    $display(
                        "[INFO] Conv1 values: %0d / %0d",
                        conv1_value_count,
                        CONV1_VALUE_COUNT
                    );

                if ((layer_index_o == 2'd1) &&
                    (conv2_value_count != 0) &&
                    ((conv2_value_count % 4096) == 0))
                    $display(
                        "[INFO] Conv2 values: %0d / %0d",
                        conv2_value_count,
                        CONV2_VALUE_COUNT
                    );

                if ((layer_index_o == 2'd2) &&
                    (conv3_value_count != 0) &&
                    ((conv3_value_count % 256) == 0))
                    $display(
                        "[INFO] Conv3 values: %0d / %0d",
                        conv3_value_count,
                        CONV3_VALUE_COUNT
                    );
            end
        end
    end

    initial begin
        // Input과 Golden만 테스트벤치에서 읽음
        // 실제 Weight/Bias는 DUT 내부 ROM이 직접 초기화
        $readmemh(
            "data/single_tile/input_y.hex",
            input_mem
        );

        $readmemh(
            "data/single_tile/relu1_expected.hex",
            relu1_expected_mem
        );

        $readmemh(
            "data/single_tile/relu2_expected.hex",
            relu2_expected_mem
        );

        $readmemh(
            "data/single_tile/output_expected.hex",
            output_expected_mem
        );

        clk               = 1'b0;
        rst_n             = 1'b0;
        start_i           = 1'b0;

        input_tile_data_i = 16'sd0;

        final_read_en_i   = 1'b0;
        final_read_addr_i = 16'd0;
        final_read_count  = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // 전체 Conv1→Conv2→Conv3 실행 시작
        @(negedge clk);
        start_i = 1'b1;

        @(negedge clk);
        start_i = 1'b0;

        wait (done_o == 1'b1);

        // 마지막 Feature Bank Write 완료 대기
        repeat (2) @(posedge clk);
        #1;

        if (conv1_value_count !== CONV1_VALUE_COUNT) begin
            mismatch_count = mismatch_count + 1;

            $display(
                "[FAIL] Conv1 count=%0d expected=%0d",
                conv1_value_count,
                CONV1_VALUE_COUNT
            );
        end

        if (conv2_value_count !== CONV2_VALUE_COUNT) begin
            mismatch_count = mismatch_count + 1;

            $display(
                "[FAIL] Conv2 count=%0d expected=%0d",
                conv2_value_count,
                CONV2_VALUE_COUNT
            );
        end

        if (conv3_value_count !== CONV3_VALUE_COUNT) begin
            mismatch_count = mismatch_count + 1;

            $display(
                "[FAIL] Conv3 count=%0d expected=%0d",
                conv3_value_count,
                CONV3_VALUE_COUNT
            );
        end

        // Conv3 결과가 저장된 Feature Bank A 전체를 다시 읽어 검증
        for (read_index = 0;
             read_index < FINAL_VALUE_COUNT;
             read_index = read_index + 1) begin

            @(negedge clk);
            final_read_en_i   = 1'b1;
            final_read_addr_i = read_index[15:0];

            @(posedge clk);
            #1;

            if (final_read_data_o !==
                output_expected_mem[read_index]) begin

                mismatch_count = mismatch_count + 1;

                if (mismatch_count <= 10) begin
                    $display(
                        "[FAIL][BANK] addr=%0d actual=%0d expected=%0d",
                        read_index,
                        final_read_data_o,
                        output_expected_mem[read_index]
                    );
                end
            end

            final_read_count = final_read_count + 1;

            if ((final_read_count % 256) == 0)
                $display(
                    "[INFO] Final Bank reads: %0d / %0d",
                    final_read_count,
                    FINAL_VALUE_COUNT
                );
        end

        @(negedge clk);
        final_read_en_i = 1'b0;

        $display("========================================");
        $display("SRCNN Fixed-ROM 3-Layer Golden Test Completed");

        $display(
            "Conv1 values = %0d / %0d",
            conv1_value_count,
            CONV1_VALUE_COUNT
        );

        $display(
            "Conv2 values = %0d / %0d",
            conv2_value_count,
            CONV2_VALUE_COUNT
        );

        $display(
            "Conv3 values = %0d / %0d",
            conv3_value_count,
            CONV3_VALUE_COUNT
        );

        $display(
            "Final reads  = %0d / %0d",
            final_read_count,
            FINAL_VALUE_COUNT
        );

        $display("mismatch_count = %0d", mismatch_count);

        if ((conv1_value_count == CONV1_VALUE_COUNT) &&
            (conv2_value_count == CONV2_VALUE_COUNT) &&
            (conv3_value_count == CONV3_VALUE_COUNT) &&
            (final_read_count == FINAL_VALUE_COUNT) &&
            (mismatch_count == 0))
            $display("[PASS] Fixed-ROM SRCNN Golden mismatch = 0");
        else
            $display("[FAIL] Fixed-ROM SRCNN Golden test failed");

        $display("========================================");

        $finish;
    end

    // 전체 3-Layer 연산보다 충분히 긴 Timeout
    initial begin
        #1000000000;
        $display("[FAIL] Fixed-ROM SRCNN simulation timeout");
        $finish;
    end

endmodule
