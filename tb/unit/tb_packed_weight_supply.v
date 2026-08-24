`timescale 1ns / 1ps

module tb_packed_weight_supply;

    reg  [5:0]  out_channel_group_i;
    reg  [6:0]  out_channel_count_i;
    reg  [5:0]  in_channel_i;
    reg  [6:0]  in_channel_count_i;
    reg  [3:0]  kernel_y_i;
    reg  [3:0]  kernel_x_i;
    reg  [3:0]  kernel_size_i;
    reg  [15:0] weight_word_base_addr_i;
    reg  [63:0] weight_word_i;

    wire [15:0] weight_word_addr_o;
    wire [3:0]  pe_enable_o;
    wire signed [15:0] weight_pe0_o;
    wire signed [15:0] weight_pe1_o;
    wire signed [15:0] weight_pe2_o;
    wire signed [15:0] weight_pe3_o;

    integer error_count;

    packed_weight_supply dut (
        .out_channel_group_i   (out_channel_group_i),
        .out_channel_count_i   (out_channel_count_i),
        .in_channel_i          (in_channel_i),
        .in_channel_count_i    (in_channel_count_i),
        .kernel_y_i            (kernel_y_i),
        .kernel_x_i            (kernel_x_i),
        .kernel_size_i         (kernel_size_i),
        .weight_word_base_addr_i(weight_word_base_addr_i),
        .weight_word_i         (weight_word_i),
        .weight_word_addr_o    (weight_word_addr_o),
        .pe_enable_o           (pe_enable_o),
        .weight_pe0_o          (weight_pe0_o),
        .weight_pe1_o          (weight_pe1_o),
        .weight_pe2_o          (weight_pe2_o),
        .weight_pe3_o          (weight_pe3_o)
    );

    task check_case;
        input [5:0]  test_group;
        input [6:0]  test_out_count;
        input [5:0]  test_in_channel;
        input [6:0]  test_in_count;
        input [3:0]  test_kernel_y;
        input [3:0]  test_kernel_x;
        input [3:0]  test_kernel_size;
        input [15:0] test_base_addr;
        input [63:0] test_word;

        input [15:0] expected_addr;
        input [3:0]  expected_enable;
        input [15:0] expected_pe0;
        input [15:0] expected_pe1;
        input [15:0] expected_pe2;
        input [15:0] expected_pe3;

        begin
            out_channel_group_i    = test_group;
            out_channel_count_i    = test_out_count;
            in_channel_i           = test_in_channel;
            in_channel_count_i     = test_in_count;
            kernel_y_i             = test_kernel_y;
            kernel_x_i             = test_kernel_x;
            kernel_size_i          = test_kernel_size;
            weight_word_base_addr_i = test_base_addr;
            weight_word_i          = test_word;

            #10;

            if ((weight_word_addr_o !== expected_addr) ||
                (pe_enable_o        !== expected_enable) ||
                (weight_pe0_o       !== expected_pe0) ||
                (weight_pe1_o       !== expected_pe1) ||
                (weight_pe2_o       !== expected_pe2) ||
                (weight_pe3_o       !== expected_pe3)) begin

                $display(
                    "[FAIL] group=%0d addr=%0d pe=%b weights=(%0d,%0d,%0d,%0d)",
                    test_group,
                    weight_word_addr_o,
                    pe_enable_o,
                    weight_pe0_o,
                    weight_pe1_o,
                    weight_pe2_o,
                    weight_pe3_o
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS] group=%0d addr=%0d pe=%b weights=(%0d,%0d,%0d,%0d)",
                    test_group,
                    weight_word_addr_o,
                    pe_enable_o,
                    weight_pe0_o,
                    weight_pe1_o,
                    weight_pe2_o,
                    weight_pe3_o
                );
            end
        end
    endtask

    initial begin
        out_channel_group_i    = 6'd0;
        out_channel_count_i    = 7'd0;
        in_channel_i           = 6'd0;
        in_channel_count_i     = 7'd0;
        kernel_y_i             = 4'd0;
        kernel_x_i             = 4'd0;
        kernel_size_i          = 4'd0;
        weight_word_base_addr_i = 16'd0;
        weight_word_i          = 64'd0;
        error_count            = 0;

        #10;

        // Conv1: PE 4개 모두 사용, 양수와 음수 분리 확인
        check_case(
            6'd0, 7'd64, 6'd0, 7'd1,
            4'd0, 4'd0, 4'd9, 16'd0,
            64'hFFFC_0003_FFFE_0001,
            16'd0, 4'b1111,
            16'h0001, 16'hFFFE, 16'h0003, 16'hFFFC
        );

        // Conv2 마지막 Packed Weight
        check_case(
            6'd7, 7'd32, 6'd63, 7'd64,
            4'd4, 4'd4, 4'd5, 16'd1296,
            64'h7FFF_8000_FFFF_0000,
            16'd14095, 4'b1111,
            16'h0000, 16'hFFFF, 16'h8000, 16'h7FFF
        );

        // Conv3: PE0만 사용, PE1~PE3은 0으로 Mask
        check_case(
            6'd0, 7'd1, 6'd31, 7'd32,
            4'd4, 4'd4, 4'd5, 16'd14096,
            64'h1111_2222_3333_007B,
            16'd14895, 4'b0001,
            16'h007B, 16'h0000, 16'h0000, 16'h0000
        );

        // Output Channel이 6개일 때 마지막 Group은 PE0~PE1만 사용
        check_case(
            6'd1, 7'd6, 6'd0, 7'd1,
            4'd0, 4'd0, 4'd1, 16'd0,
            64'h4444_3333_FFFE_0005,
            16'd1, 4'b0011,
            16'h0005, 16'hFFFE, 16'h0000, 16'h0000
        );

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL PACKED WEIGHT SUPPLY TESTS PASSED");
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
