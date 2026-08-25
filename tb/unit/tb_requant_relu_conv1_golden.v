`timescale 1ns / 1ps

module tb_requant_relu_conv1_golden;

    localparam VALUE_COUNT = 65536;

    reg signed [47:0] acc_i;
    reg        [5:0]  shift_i;

    wire signed [15:0] data_o;

    reg signed [47:0] accumulator_mem [0:VALUE_COUNT-1];
    reg signed [15:0] expected_mem    [0:VALUE_COUNT-1];

    integer value_index;
    integer error_count;

    requant_relu dut (
        .acc_i  (acc_i),
        .shift_i(shift_i),
        .data_o (data_o)
    );

    initial begin
        $readmemh(
            "data/single_tile/conv1_acc_expected.hex",
            accumulator_mem
        );

        $readmemh(
            "data/single_tile/relu1_expected.hex",
            expected_mem
        );

        acc_i       = 48'sd0;
        shift_i     = 6'd14;
        error_count = 0;

        #1;

        for (value_index = 0;
             value_index < VALUE_COUNT;
             value_index = value_index + 1) begin

            acc_i = accumulator_mem[value_index];

            #1;

            if (data_o !== expected_mem[value_index]) begin
                error_count = error_count + 1;

                if (error_count <= 10) begin
                    $display(
                        "[FAIL] index=%0d acc=%0d actual=%0d expected=%0d",
                        value_index,
                        accumulator_mem[value_index],
                        data_o,
                        expected_mem[value_index]
                    );
                end
            end

            if ((value_index != 0) &&
                ((value_index % 8192) == 0)) begin
                $display(
                    "[INFO] Values checked: %0d / %0d",
                    value_index,
                    VALUE_COUNT
                );
            end
        end

        $display("========================================");
        $display("Conv1 Requant Golden Test Completed");
        $display("value_count = %0d", VALUE_COUNT);
        $display("error_count = %0d", error_count);

        if (error_count == 0)
            $display("[PASS] Conv1 Requant Golden mismatch = 0");
        else
            $display("[FAIL] Conv1 Requant Golden test failed");

        $display("========================================");

        $finish;
    end

endmodule
