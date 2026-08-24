`timescale 1ns / 1ps

module tb_bias_group_loader;

    reg clk;
    reg rst_n;
    reg start_i;

    reg  [5:0]  out_channel_group_i;
    reg  [15:0] bias_base_addr_i;
    reg  [3:0]  pe_enable_i;

    reg signed [31:0] bias_bram_data_i;

    wire        bias_bram_en_o;
    wire [15:0] bias_bram_addr_o;

    wire signed [31:0] bias_pe0_o;
    wire signed [31:0] bias_pe1_o;
    wire signed [31:0] bias_pe2_o;
    wire signed [31:0] bias_pe3_o;

    wire busy_o;
    wire bias_ready_o;

    // 32-bit Bias BRAM 모델
    reg signed [31:0] bias_memory [0:127];

    integer memory_index;
    integer read_count;
    integer error_count;

    bias_group_loader dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .start_i            (start_i),
        .out_channel_group_i(out_channel_group_i),
        .bias_base_addr_i   (bias_base_addr_i),
        .pe_enable_i        (pe_enable_i),
        .bias_bram_data_i   (bias_bram_data_i),
        .bias_bram_en_o     (bias_bram_en_o),
        .bias_bram_addr_o   (bias_bram_addr_o),
        .bias_pe0_o         (bias_pe0_o),
        .bias_pe1_o         (bias_pe1_o),
        .bias_pe2_o         (bias_pe2_o),
        .bias_pe3_o         (bias_pe3_o),
        .busy_o             (busy_o),
        .bias_ready_o       (bias_ready_o)
    );

    // 100 MHz Clock
    always #5 clk = ~clk;

    // 1-Clock Latency를 갖는 동기식 Bias BRAM
    always @(posedge clk) begin
        if (bias_bram_en_o) begin
            bias_bram_data_i <= bias_memory[bias_bram_addr_o];
            read_count = read_count + 1;
        end
    end

    task run_case;
        input integer test_id;

        input [5:0]  test_group;
        input [15:0] test_base_addr;
        input [3:0]  test_pe_enable;

        input [31:0] expected_pe0;
        input [31:0] expected_pe1;
        input [31:0] expected_pe2;
        input [31:0] expected_pe3;

        input integer expected_read_count;

        integer timeout_count;

        begin
            read_count = 0;

            // Loader Start Pulse 입력
            @(negedge clk);
            out_channel_group_i = test_group;
            bias_base_addr_i    = test_base_addr;
            pe_enable_i         = test_pe_enable;
            start_i             = 1'b1;

            @(negedge clk);
            start_i = 1'b0;

            // Start가 처리되면 Loader가 Busy여야 함
            #1;
            if (busy_o !== 1'b1) begin
                $display(
                    "[FAIL %0d] Loader did not enter Busy state",
                    test_id
                );
                error_count = error_count + 1;
            end

            // Bias Ready 대기
            timeout_count = 0;

            while ((bias_ready_o !== 1'b1) &&
                   (timeout_count < 20)) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end

            if (timeout_count >= 20) begin
                $display(
                    "[FAIL %0d] Bias Loader timeout",
                    test_id
                );
                error_count = error_count + 1;
            end
            else if ((bias_pe0_o !== expected_pe0) ||
                     (bias_pe1_o !== expected_pe1) ||
                     (bias_pe2_o !== expected_pe2) ||
                     (bias_pe3_o !== expected_pe3) ||
                     (read_count !== expected_read_count) ||
                     (busy_o !== 1'b0)) begin

                $display(
                    "[FAIL %0d] group=%0d pe=%b reads=%0d bias=(%0d,%0d,%0d,%0d)",
                    test_id,
                    test_group,
                    test_pe_enable,
                    read_count,
                    bias_pe0_o,
                    bias_pe1_o,
                    bias_pe2_o,
                    bias_pe3_o
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS %0d] group=%0d pe=%b reads=%0d bias=(%0d,%0d,%0d,%0d)",
                    test_id,
                    test_group,
                    test_pe_enable,
                    read_count,
                    bias_pe0_o,
                    bias_pe1_o,
                    bias_pe2_o,
                    bias_pe3_o
                );
            end

            // bias_ready_o가 1-Clock Pulse인지 확인
            @(posedge clk);
            #1;

            if (bias_ready_o !== 1'b0) begin
                $display(
                    "[FAIL %0d] bias_ready_o is not a 1-cycle pulse",
                    test_id
                );
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        clk                 = 1'b0;
        rst_n               = 1'b1;
        start_i             = 1'b0;
        out_channel_group_i = 6'd0;
        bias_base_addr_i    = 16'd0;
        pe_enable_i         = 4'b0000;
        bias_bram_data_i    = 32'sd0;

        read_count  = 0;
        error_count = 0;

        // Bias Memory 전체 초기화
        for (memory_index = 0;
             memory_index < 128;
             memory_index = memory_index + 1) begin

            bias_memory[memory_index] = 32'sd0;
        end

        // 테스트에 사용할 signed Bias
        bias_memory[0]  = 32'd10;
        bias_memory[1]  = 32'hFFFF_FFEC; // -20
        bias_memory[2]  = 32'd30;
        bias_memory[3]  = 32'hFFFF_FFD8; // -40

        bias_memory[4]  = 32'd44;
        bias_memory[5]  = 32'hFFFF_FFC9; // -55

        bias_memory[60] = 32'd60;
        bias_memory[61] = 32'hFFFF_FFC3; // -61
        bias_memory[62] = 32'd62;
        bias_memory[63] = 32'hFFFF_FFC1; // -63

        bias_memory[92] = 32'd92;
        bias_memory[93] = 32'hFFFF_FFA3; // -93
        bias_memory[94] = 32'd94;
        bias_memory[95] = 32'hFFFF_FFA1; // -95

        bias_memory[96] = 32'hFFFF_FFA0; // -96

        // Sync Active-Low Reset
        @(negedge clk);
        rst_n = 1'b0;

        @(posedge clk);
        #1;

        @(negedge clk);
        rst_n = 1'b1;

        // Conv1 Group 0: 주소 0~3
        run_case(
            1,
            6'd0, 16'd0, 4'b1111,
            32'd10, 32'hFFFF_FFEC,
            32'd30, 32'hFFFF_FFD8,
            4
        );

        // Conv1 Group 15: 주소 60~63
        run_case(
            2,
            6'd15, 16'd0, 4'b1111,
            32'd60, 32'hFFFF_FFC3,
            32'd62, 32'hFFFF_FFC1,
            4
        );

        // Conv2 Group 7: Base 64 + Group×4 = 주소 92
        run_case(
            3,
            6'd7, 16'd64, 4'b1111,
            32'd92, 32'hFFFF_FFA3,
            32'd94, 32'hFFFF_FFA1,
            4
        );

        // Conv3: 주소 96의 PE0만 사용
        run_case(
            4,
            6'd0, 16'd96, 4'b0001,
            32'hFFFF_FFA0, 32'd0,
            32'd0, 32'd0,
            1
        );

        // Output Channel 6개: 마지막 Group에서 PE0~PE1만 사용
        run_case(
            5,
            6'd1, 16'd0, 4'b0011,
            32'd44, 32'hFFFF_FFC9,
            32'd0, 32'd0,
            2
        );

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL BIAS GROUP LOADER TESTS PASSED");
            $display("========================================");
        end
        else begin
            $display("========================================");
            $display("TEST FAILED: %0d error(s)", error_count);
            $display("========================================");
        end

        $finish;
    end

endmodule
