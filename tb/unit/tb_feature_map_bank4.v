`timescale 1ns / 1ps

module tb_feature_map_bank4;

    reg clk;
    reg rst_n;

    reg               write_valid_i;
    reg        [3:0]  write_pe_enable_i;
    reg        [5:0]  write_group_i;
    reg        [4:0]  write_y_i;
    reg        [4:0]  write_x_i;

    reg signed [15:0] write_data0_i;
    reg signed [15:0] write_data1_i;
    reg signed [15:0] write_data2_i;
    reg signed [15:0] write_data3_i;

    reg               read_en_i;
    reg        [15:0] read_addr_i;

    wire signed [15:0] read_data_o;

    integer check_count;
    integer error_count;

    feature_map_bank4 dut (
        .clk              (clk),
        .rst_n            (rst_n),

        .write_valid_i    (write_valid_i),
        .write_pe_enable_i(write_pe_enable_i),
        .write_group_i    (write_group_i),
        .write_y_i        (write_y_i),
        .write_x_i        (write_x_i),

        .write_data0_i    (write_data0_i),
        .write_data1_i    (write_data1_i),
        .write_data2_i    (write_data2_i),
        .write_data3_i    (write_data3_i),

        .read_en_i        (read_en_i),
        .read_addr_i      (read_addr_i),
        .read_data_o      (read_data_o)
    );

    always #5 clk = ~clk;

    // 한 Output Channel Group의 PE0~PE3 결과를 동시에 저장
    task write_group;
        input        [5:0] group;
        input        [4:0] y;
        input        [4:0] x;
        input        [3:0] pe_mask;
        input signed [15:0] data0;
        input signed [15:0] data1;
        input signed [15:0] data2;
        input signed [15:0] data3;
        begin
            @(negedge clk);

            write_group_i     = group;
            write_y_i         = y;
            write_x_i         = x;
            write_pe_enable_i = pe_mask;

            write_data0_i = data0;
            write_data1_i = data1;
            write_data2_i = data2;
            write_data3_i = data3;

            write_valid_i = 1'b1;

            @(negedge clk);

            write_valid_i     = 1'b0;
            write_pe_enable_i = 4'b0000;
        end
    endtask

    // Channel/Y/X 주소로 읽고 1-Clock 뒤의 결과 검사
    task check_read;
        input        [5:0] channel;
        input        [4:0] y;
        input        [4:0] x;
        input signed [15:0] expected;
        begin
            @(negedge clk);

            // 주소 구조: Channel 6-bit + Y 5-bit + X 5-bit
            read_addr_i = {channel, y, x};
            read_en_i   = 1'b1;

            @(posedge clk);
            #1;

            check_count = check_count + 1;

            if (read_data_o !== expected) begin
                error_count = error_count + 1;

                $display(
                    "[FAIL] channel=%0d y=%0d x=%0d actual=%0d expected=%0d",
                    channel,
                    y,
                    x,
                    read_data_o,
                    expected
                );
            end
            else begin
                $display(
                    "[PASS] channel=%0d y=%0d x=%0d data=%0d",
                    channel,
                    y,
                    x,
                    read_data_o
                );
            end

            @(negedge clk);
            read_en_i = 1'b0;
        end
    endtask

    initial begin
        clk   = 1'b0;
        rst_n = 1'b0;

        write_valid_i     = 1'b0;
        write_pe_enable_i = 4'b0000;
        write_group_i     = 6'd0;
        write_y_i         = 5'd0;
        write_x_i         = 5'd0;

        write_data0_i = 16'sd0;
        write_data1_i = 16'sd0;
        write_data2_i = 16'sd0;
        write_data3_i = 16'sd0;

        read_en_i   = 1'b0;
        read_addr_i = 16'd0;

        check_count = 0;
        error_count = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // Group 3은 Channel 12~15에 해당
        write_group(
            6'd3, 5'd2, 5'd5, 4'b1111,
            16'sd101, -16'sd202, 16'sd303, -16'sd404
        );

        check_read(6'd12, 5'd2, 5'd5,  16'sd101);
        check_read(6'd13, 5'd2, 5'd5, -16'sd202);
        check_read(6'd14, 5'd2, 5'd5,  16'sd303);
        check_read(6'd15, 5'd2, 5'd5, -16'sd404);

        // 같은 주소에서 PE0과 PE2만 갱신
        write_group(
            6'd3, 5'd2, 5'd5, 4'b0101,
            16'sd1111, 16'sd2222, 16'sd3333, 16'sd4444
        );

        check_read(6'd12, 5'd2, 5'd5,  16'sd1111);
        check_read(6'd13, 5'd2, 5'd5, -16'sd202);
        check_read(6'd14, 5'd2, 5'd5,  16'sd3333);
        check_read(6'd15, 5'd2, 5'd5, -16'sd404);

        // 마지막 Group과 마지막 좌표 경계 검사
        write_group(
            6'd15, 5'd31, 5'd31, 4'b1111,
            16'sd5001, 16'sd5002, 16'sd5003, 16'sd5004
        );

        check_read(6'd60, 5'd31, 5'd31, 16'sd5001);
        check_read(6'd61, 5'd31, 5'd31, 16'sd5002);
        check_read(6'd62, 5'd31, 5'd31, 16'sd5003);
        check_read(6'd63, 5'd31, 5'd31, 16'sd5004);

        $display("========================================");
        $display("Feature Map Bank4 Test Completed");
        $display("check_count = %0d", check_count);
        $display("error_count = %0d", error_count);

        if ((check_count == 12) && (error_count == 0))
            $display("[PASS] All Feature Map Bank checks passed");
        else
            $display("[FAIL] Feature Map Bank test failed");

        $display("========================================");

        $finish;
    end

    initial begin
        #10000;
        $display("[FAIL] Feature Map Bank simulation timeout");
        $finish;
    end

endmodule
