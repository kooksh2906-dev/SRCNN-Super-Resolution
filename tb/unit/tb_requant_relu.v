`timescale 1ns / 1ps

module tb_requant_relu;

    localparam CASE_COUNT = 45;

    reg clk;
    reg rst_n;

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
        .clk    (clk),
        .rst_n  (rst_n),
        .acc_i  (acc_i),
        .shift_i(shift_i),
        .data_o (data_o)
    );

    // 100 MHz, 10 ns 주기 Clock
    always #5 clk = ~clk;

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

        clk         = 1'b0;
        rst_n       = 1'b0;
        acc_i       = 48'sd0;
        shift_i     = 6'd0;
        error_count = 0;

        // Pipeline Register 초기화를 위해 Reset 유지
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        for (case_index = 0;
             case_index < CASE_COUNT;
             case_index = case_index + 1) begin

            // 하강 에지에서 입력을 적용해 다음 상승 에지까지 안정화
            @(negedge clk);
            acc_i   = accumulator_mem[case_index];
            shift_i = shift_mem[case_index];

            // Stage1→Stage2→Stage3→Stage4 완료 대기
            repeat (4) @(posedge clk);
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
        $display("Requant Pipeline Directed Test Completed");
        $display("case_count  = %0d", CASE_COUNT);
        $display("error_count = %0d", error_count);

        if (error_count == 0)
            $display("[PASS] All requant pipeline cases passed");
        else
            $display("[FAIL] Requant pipeline directed test failed");

        $display("========================================");

        $finish;
    end

endmodule
