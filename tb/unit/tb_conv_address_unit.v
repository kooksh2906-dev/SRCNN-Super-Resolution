`timescale 1ns / 1ps

module tb_conv_address_unit;

    reg  [5:0]  out_channel_i;
    reg  [5:0]  in_channel_i;
    reg  [4:0]  out_y_i;
    reg  [4:0]  out_x_i;
    reg  [3:0]  kernel_y_i;
    reg  [3:0]  kernel_x_i;
    reg  [6:0]  in_channel_count_i;
    reg  [3:0]  kernel_size_i;
    reg  [3:0]  pad_i;
    reg  [15:0] weight_base_addr_i;

    wire        padding_o;
    wire [15:0] activation_addr_o;
    wire [15:0] weight_addr_o;

    integer error_count;

    conv_address_unit dut (
        .out_channel_i      (out_channel_i),
        .in_channel_i       (in_channel_i),
        .out_y_i            (out_y_i),
        .out_x_i            (out_x_i),
        .kernel_y_i         (kernel_y_i),
        .kernel_x_i         (kernel_x_i),
        .in_channel_count_i (in_channel_count_i),
        .kernel_size_i      (kernel_size_i),
        .pad_i              (pad_i),
        .weight_base_addr_i (weight_base_addr_i),
        .padding_o          (padding_o),
        .activation_addr_o  (activation_addr_o),
        .weight_addr_o      (weight_addr_o)
    );

    task check_case;
        input [5:0]  test_oc;
        input [5:0]  test_ic;
        input [4:0]  test_out_y;
        input [4:0]  test_out_x;
        input [3:0]  test_ky;
        input [3:0]  test_kx;
        input [6:0]  test_ic_count;
        input [3:0]  test_kernel_size;
        input [3:0]  test_pad;
        input [15:0] test_weight_base;
        input        expected_padding;
        input [15:0] expected_activation_addr;
        input [15:0] expected_weight_addr;

        begin
            out_channel_i      = test_oc;
            in_channel_i       = test_ic;
            out_y_i            = test_out_y;
            out_x_i            = test_out_x;
            kernel_y_i         = test_ky;
            kernel_x_i         = test_kx;
            in_channel_count_i = test_ic_count;
            kernel_size_i      = test_kernel_size;
            pad_i              = test_pad;
            weight_base_addr_i = test_weight_base;

            #10;

            if ((padding_o         !== expected_padding) ||
                (activation_addr_o !== expected_activation_addr) ||
                (weight_addr_o     !== expected_weight_addr)) begin

                $display(
                    "[FAIL] pad=%0d/%0d act=%0d/%0d weight=%0d/%0d",
                    padding_o,
                    expected_padding,
                    activation_addr_o,
                    expected_activation_addr,
                    weight_addr_o,
                    expected_weight_addr
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS] pad=%0d act_addr=%0d weight_addr=%0d",
                    padding_o,
                    activation_addr_o,
                    weight_addr_o
                );
            end
        end
    endtask

    initial begin
        out_channel_i      = 6'd0;
        in_channel_i       = 6'd0;
        out_y_i            = 5'd0;
        out_x_i            = 5'd0;
        kernel_y_i         = 4'd0;
        kernel_x_i         = 4'd0;
        in_channel_count_i = 7'd0;
        kernel_size_i      = 4'd0;
        pad_i              = 4'd0;
        weight_base_addr_i = 16'd0;
        error_count        = 0;

        #10;

        // Conv1 좌측 위 Padding, 첫 Weight
        check_case(6'd0, 6'd0, 5'd0, 5'd0, 4'd0, 4'd0,
                   7'd1, 4'd9, 4'd4, 16'd0,
                   1'b1, 16'd0, 16'd0);

        // Conv1 좌측 위에서 커널 중앙: 실제 입력 (0,0)
        check_case(6'd0, 6'd0, 5'd0, 5'd0, 4'd4, 4'd4,
                   7'd1, 4'd9, 4'd4, 16'd0,
                   1'b0, 16'd0, 16'd40);

        // Conv2 내부 좌표
        check_case(6'd1, 6'd2, 5'd10, 5'd20, 4'd2, 4'd2,
                   7'd64, 4'd5, 4'd2, 16'd5184,
                   1'b0, 16'd2388, 16'd6846);

        // Conv2 최대 Activation 주소, 정상 좌표
        check_case(6'd31, 6'd63, 5'd31, 5'd31, 4'd2, 4'd2,
                   7'd64, 4'd5, 4'd2, 16'd5184,
                   1'b0, 16'd65535, 16'd56371);

        // Activation은 Padding이지만 Weight 주소는 정상적으로 계산
        check_case(6'd31, 6'd63, 5'd31, 5'd31, 4'd4, 4'd4,
                   7'd64, 4'd5, 4'd2, 16'd5184,
                   1'b1, 16'd0, 16'd56383);

        // Conv3의 마지막 Input Channel, 정상 중앙 좌표
        check_case(6'd0, 6'd31, 5'd31, 5'd31, 4'd2, 4'd2,
                   7'd32, 4'd5, 4'd2, 16'd56384,
                   1'b0, 16'd32767, 16'd57171);

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL CONV ADDRESS UNIT TESTS PASSED");
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
