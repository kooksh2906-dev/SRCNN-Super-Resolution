`timescale 1ns / 1ps

module tb_activation_addr_gen;

    reg  [5:0] channel_i;
    reg  [4:0] out_y_i;
    reg  [4:0] out_x_i;
    reg  [3:0] kernel_y_i;
    reg  [3:0] kernel_x_i;
    reg  [3:0] pad_i;

    wire        padding_o;
    wire [15:0] activation_addr_o;

    integer error_count;

    activation_addr_gen dut (
        .channel_i        (channel_i),
        .out_y_i          (out_y_i),
        .out_x_i          (out_x_i),
        .kernel_y_i       (kernel_y_i),
        .kernel_x_i       (kernel_x_i),
        .pad_i            (pad_i),
        .padding_o        (padding_o),
        .activation_addr_o(activation_addr_o)
    );

    task check_case;
        input [5:0]  test_channel;		// 채널 번호
        input [4:0]  test_out_y;		// 출력 Y 좌표
        input [4:0]  test_out_x;		// 출력 X 좌표
        input [3:0]  test_kernel_y;		// 커널 Y 좌표
        input [3:0]  test_kernel_x;		// 커널 X 좌표
        input [3:0]  test_pad;			// Padding 크기
        input        expected_padding;	// 예상 Padding 여부
        input [15:0] expected_addr;		// 예상 BRAM 주소

		// expected_padding = 1 → 이미지 바깥이므로 Padding
		// expected_padding = 0 → 이미지 안쪽이므로 정상 주소

        begin
            channel_i  = test_channel;
            out_y_i    = test_out_y;
            out_x_i    = test_out_x;
            kernel_y_i = test_kernel_y;
            kernel_x_i = test_kernel_x;
            pad_i      = test_pad;

            #10;

            if ((padding_o !== expected_padding) ||
                (activation_addr_o !== expected_addr)) begin

                $display(
                    "[FAIL] ch=%0d out=(%0d,%0d) kernel=(%0d,%0d) pad=%0d expected=(%0d,%0d) actual=(%0d,%0d)",
                    test_channel,
                    test_out_y,
                    test_out_x,
                    test_kernel_y,
                    test_kernel_x,
                    test_pad,
                    expected_padding,
                    expected_addr,
                    padding_o,
                    activation_addr_o
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "[PASS] ch=%0d out=(%0d,%0d) kernel=(%0d,%0d) padding=%0d addr=%0d",
                    test_channel,
                    test_out_y,
                    test_out_x,
                    test_kernel_y,
                    test_kernel_x,
                    padding_o,
                    activation_addr_o
                );
            end
        end
    endtask

    initial begin
        channel_i  = 6'd0;
        out_y_i    = 5'd0;
        out_x_i    = 5'd0;
        kernel_y_i = 4'd0;
        kernel_x_i = 4'd0;
        pad_i      = 4'd0;
        error_count = 0;

        #10;

        // 작성 예시:
        // Conv1 좌측 위에서 커널 (0,0)은 실제 좌표 (-4,-4)
        check_case(6'd0, 5'd0, 5'd0, 4'd0, 4'd0, 4'd4,
                   1'b1, 16'd0);

        // TODO 1:
        // Conv1 좌측 위에서 커널 (4,4)
        // 실제 좌표 = (0+4-4, 0+4-4) = (0,0)
        // 정상 좌표이므로 padding=0, address=0
        check_case(6'd0, 5'd0, 5'd0, 4'd4, 4'd4, 4'd4,
                   1'b0, 16'd0);

        // TODO 2:
        // channel=2, 출력=(10,20), 커널=(4,4), pad=4
        // 실제 좌표 = (10+4-4, 20+4-4) = (10,20)
        // address = 2*1024 + 10*32 + 20 = 2388
        check_case(6'd2, 5'd10, 5'd20, 4'd4, 4'd4, 4'd4,
                   1'b0, 16'd2388);


        // TODO 3:
        // Conv1 우측 아래 출력=(31,31), 커널=(8,8), pad=4
        // 실제 좌표=(35,35), Padding
		check_case(6'd0, 5'd31, 5'd31, 4'd8, 4'd8, 4'd4,
                   1'b1, 16'd0);

        // TODO 4:
        // channel=1, 출력=(31,31), 커널=(4,4), pad=4
        // 실제 좌표=(31,31), 정상 주소 2047
		check_case(6'd1, 5'd31, 5'd31, 4'd4, 4'd4, 4'd4,
                   1'b0, 16'd2047);

        // TODO 5:
        // channel=63, 출력=(31,31), 커널=(2,2), pad=2
        // 최대 정상 주소 65535
		check_case(6'd63, 5'd31, 5'd31, 4'd2, 4'd2, 4'd2,
                   1'b0, 16'd65535);

        // TODO 6:
        // 출력=(0,0), 커널=(0,2), pad=2
        // Y 좌표가 -2이므로 Padding
		check_case(6'd0, 5'd0, 5'd0, 4'd0, 4'd2, 4'd2,
                   1'b1, 16'd0);


        // TODO 7:
        // 출력=(0,0), 커널=(2,0), pad=2
        // X 좌표가 -2이므로 Padding
		check_case(6'd0, 5'd0, 5'd0, 4'd2, 4'd0, 4'd2,
                   1'b1, 16'd0);

        if (error_count == 0) begin
            $display("========================================");
            $display("ALL ACTIVATION ADDRESS TESTS PASSED");
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
