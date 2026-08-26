`timescale 1ns / 1ps

module tb_srcnn_fixed_parameter_rom;

    localparam WEIGHT_WORD_COUNT = 14896;
    localparam BIAS_WORD_COUNT   = 97;

    reg clk;
    reg rst_n;

    reg         weight_read_en_i;
    reg  [15:0] weight_read_addr_i;
    wire [63:0] weight_read_data_o;

    reg                bias_read_en_i;
    reg         [15:0] bias_read_addr_i;
    wire signed [31:0] bias_read_data_o;

    reg        [63:0] weight_expected_mem
                        [0:WEIGHT_WORD_COUNT-1];

    reg signed [31:0] bias_expected_mem
                        [0:BIAS_WORD_COUNT-1];

    reg        [63:0] held_weight_data;
    reg signed [31:0] held_bias_data;

    integer weight_index;
    integer bias_index;
    integer weight_check_count;
    integer bias_check_count;
    integer error_count;

    srcnn_weight_rom #(
        .INIT_FILE("mem_init/srcnn_weights_all.hex")
    ) u_srcnn_weight_rom (
        .clk        (clk),
        .rst_n      (rst_n),
        .read_en_i  (weight_read_en_i),
        .read_addr_i(weight_read_addr_i),
        .read_data_o(weight_read_data_o)
    );

    srcnn_bias_rom #(
        .INIT_FILE("mem_init/srcnn_biases_all.hex")
    ) u_srcnn_bias_rom (
        .clk        (clk),
        .rst_n      (rst_n),
        .read_en_i  (bias_read_en_i),
        .read_addr_i(bias_read_addr_i),
        .read_data_o(bias_read_data_o)
    );

    // 100MHz Clock
    always #5 clk = ~clk;

    // Weight ROM의 한 주소를 1-Clock Latency로 읽어 비교
    task check_weight_address;
        input integer address;
        begin
            @(negedge clk);
            weight_read_en_i   = 1'b1;
            weight_read_addr_i = address[15:0];

            @(posedge clk);
            #1;

            weight_check_count = weight_check_count + 1;

            if (weight_read_data_o !==
                weight_expected_mem[address]) begin

                error_count = error_count + 1;

                if (error_count <= 10) begin
                    $display(
                        "[FAIL][WEIGHT] addr=%0d actual=%016h expected=%016h",
                        address,
                        weight_read_data_o,
                        weight_expected_mem[address]
                    );
                end
            end
        end
    endtask

    // Bias ROM의 한 주소를 1-Clock Latency로 읽어 비교
    task check_bias_address;
        input integer address;
        begin
            @(negedge clk);
            bias_read_en_i   = 1'b1;
            bias_read_addr_i = address[15:0];

            @(posedge clk);
            #1;

            bias_check_count = bias_check_count + 1;

            if (bias_read_data_o !==
                bias_expected_mem[address]) begin

                error_count = error_count + 1;

                if (error_count <= 10) begin
                    $display(
                        "[FAIL][BIAS] addr=%0d actual=%08h expected=%08h",
                        address,
                        bias_read_data_o,
                        bias_expected_mem[address]
                    );
                end
            end
        end
    endtask

    initial begin
        $readmemh(
            "mem_init/srcnn_weights_all.hex",
            weight_expected_mem
        );

        $readmemh(
            "mem_init/srcnn_biases_all.hex",
            bias_expected_mem
        );

        clk                = 1'b0;
        rst_n              = 1'b0;

        weight_read_en_i   = 1'b0;
        weight_read_addr_i = 16'd0;

        bias_read_en_i     = 1'b0;
        bias_read_addr_i   = 16'd0;

        held_weight_data   = 64'd0;
        held_bias_data     = 32'sd0;

        weight_check_count = 0;
        bias_check_count   = 0;
        error_count        = 0;

        // Reset을 세 Clock 동안 유지
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        @(posedge clk);
        #1;

        // Reset 후 ROM 출력은 0이어야 함
        if (weight_read_data_o !== 64'd0) begin
            error_count = error_count + 1;
            $display(
                "[FAIL][RESET] Weight output actual=%016h expected=0",
                weight_read_data_o
            );
        end

        if (bias_read_data_o !== 32'sd0) begin
            error_count = error_count + 1;
            $display(
                "[FAIL][RESET] Bias output actual=%08h expected=0",
                bias_read_data_o
            );
        end

        // 전체 Weight 주소를 빠짐없이 검사
        for (weight_index = 0;
             weight_index < WEIGHT_WORD_COUNT;
             weight_index = weight_index + 1) begin

            check_weight_address(weight_index);

            if (((weight_index + 1) % 2048) == 0)
                $display(
                    "[INFO] Weight words checked: %0d / %0d",
                    weight_index + 1,
                    WEIGHT_WORD_COUNT
                );
        end

        // Weight ROM Enable=0일 때 마지막 출력값 유지 검사
        held_weight_data = weight_read_data_o;

        @(negedge clk);
        weight_read_en_i   = 1'b0;
        weight_read_addr_i = 16'd0;

        @(posedge clk);
        #1;

        if (weight_read_data_o !== held_weight_data) begin
            error_count = error_count + 1;
            $display(
                "[FAIL][WEIGHT HOLD] actual=%016h expected=%016h",
                weight_read_data_o,
                held_weight_data
            );
        end

        // 전체 Bias 주소를 빠짐없이 검사
        for (bias_index = 0;
             bias_index < BIAS_WORD_COUNT;
             bias_index = bias_index + 1) begin

            check_bias_address(bias_index);
        end

        // Bias ROM Enable=0일 때 마지막 출력값 유지 검사
        held_bias_data = bias_read_data_o;

        @(negedge clk);
        bias_read_en_i   = 1'b0;
        bias_read_addr_i = 16'd0;

        @(posedge clk);
        #1;

        if (bias_read_data_o !== held_bias_data) begin
            error_count = error_count + 1;
            $display(
                "[FAIL][BIAS HOLD] actual=%08h expected=%08h",
                bias_read_data_o,
                held_bias_data
            );
        end

        $display("========================================");
        $display("SRCNN Fixed Parameter ROM Test Completed");
        $display(
            "weight_check_count = %0d / %0d",
            weight_check_count,
            WEIGHT_WORD_COUNT
        );
        $display(
            "bias_check_count   = %0d / %0d",
            bias_check_count,
            BIAS_WORD_COUNT
        );
        $display("error_count        = %0d", error_count);

        if ((weight_check_count == WEIGHT_WORD_COUNT) &&
            (bias_check_count == BIAS_WORD_COUNT) &&
            (error_count == 0))
            $display("[PASS] All fixed parameter ROM checks passed");
        else
            $display("[FAIL] Fixed parameter ROM test failed");

        $display("========================================");

        $finish;
    end

    initial begin
        #500000;
        $display("[FAIL] Fixed parameter ROM simulation timeout");
        $finish;
    end

endmodule
