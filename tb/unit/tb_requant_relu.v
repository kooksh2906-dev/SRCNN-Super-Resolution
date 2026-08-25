`timescale 1ns / 1ps

module tb_requant_relu;

    localparam CASE_COUNT = 45;

    reg signed [47:0] acc_i;
    reg        [5:0]  shift_i;

    wire signed [15:0] data_o;

    reg signed [47:0] accumulator_mem [0:CASE_COUNT-1];
    reg        [5:0]  shift_mem       [0:CASE_COUNT-1];
    reg        [1:0]  mode_mem        [0:CASE_COUNT-1];
    reg signed [15:0] expected_mem    [0:CASE_COUNT-1];

    integer case_index;
    integer error_count;

    requant_relu dut (
        .acc_i  (acc_i),
        .shift_i(shift_i),
        .data_o (data_o)
    );

    initial begin
        $readmemh(
            "data/directed_requant/requant_accumulator.hex",
            accumulator_mem
        );

        $readmemh(
            "data/directed_requant/requant_shift.hex",
            shift_mem
        );

        $readmemh(
            "data/directed_requant/requant_mode.hex",
            mode_mem
        );

        $readmemh(
            "data/directed_requant/requant_output_expected.hex",
            expected_mem
        );

        acc_i      = 48'sd0;
        shift_i    = 6'd0;
        error_count = 0;

        #1;

        for (case_index = 0;
             case_index < CASE_COUNT;
             case_index = case_index + 1) begin

            acc_i   = accumulator_mem[case_index];
            shift_i = shift_mem[case_index];

            #1;

            if (data_o !== expected_mem[case_index]) begin
                error_count = error_count + 1;

                $display(
                    "[FAIL] case=%0d mode=%0d acc=%0d shift=%0d actual=%0d expected=%0d",
                    case_index,
                    mode_mem[case_index],
                    accumulator_mem[case_index],
                    shift_mem[case_index],
                    data_o,
                    expected_mem[case_index]
                );
            end
        end

        $display("========================================");
        $display("Requant Directed Test Completed");
        $display("case_count  = %0d", CASE_COUNT);
        $display("error_count = %0d", error_count);

        if (error_count == 0)
            $display("[PASS] All requant directed cases passed");
        else
            $display("[FAIL] Requant directed test failed");

        $display("========================================");

        $finish;
    end

endmodule
