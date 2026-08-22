`timescale 1ns / 1ps

module tb_requant_round_shift();

    // DUT 입력
reg signed [47:0] acc_i;
reg        [5:0]  shift_i;

// DUT 출력
wire signed [47:0] rounded_o;

// 실패한 테스트 개수
integer error_count;

// 검사 대상 모듈
requant_round_shift dut (
	.acc_i     (acc_i),
	.shift_i   (shift_i),
	.rounded_o (rounded_o)
);

// 하나의 입력과 예상 출력값을 검사하는 Task
task check_case;
	input signed [47:0] test_acc;
	input        [5:0]  test_shift;
	input signed [47:0] expected;

	begin
		acc_i   = test_acc;
		shift_i = test_shift;

		// 조합논리 출력이 안정화될 시간
		#10;

		if (rounded_o !== expected) begin
			$display(
				"[FAIL] acc=%0d shift=%0d expected=%0d actual=%0d",
				test_acc,
				test_shift,
				expected,
				rounded_o
			);

			error_count = error_count + 1;
		end
		else begin
			$display(
				"[PASS] acc=%0d shift=%0d result=%0d",
				test_acc,
				test_shift,
				rounded_o
			);
		end
	end
endtask

initial begin
	acc_i      = 48'sd0;
	shift_i    = 6'd0;
	error_count = 0;

	#10;

	// 예시: 0을 14-bit Shift하면 0
	check_case(48'sd0, 6'd14, 48'sd0);

	// TODO 1: 8191을 14-bit Shift하면 0
	check_case(48'sd8191, 6'd14, 48'sd0);

	// TODO 2: 8192를 14-bit Shift하면 1
	check_case(48'sd8192, 6'd14, 48'sd1);

	// TODO 3: 16384를 14-bit Shift하면 1
	check_case(48'sd16384, 6'd14, 48'sd1);

	// TODO 4: 24576을 14-bit Shift하면 2
	check_case(48'sd24576, 6'd14, 48'sd2);

	// TODO 5: -8191을 14-bit Shift하면 0
	check_case(-48'sd8191, 6'd14, 48'sd0);

	// TODO 6: -8192를 14-bit Shift하면 -1
	check_case(-48'sd8192, 6'd14, -48'sd1);

	// TODO 7: -24576을 14-bit Shift하면 -2
	check_case(-48'sd24576, 6'd14, -48'sd2);

	// TODO 8: 12345를 0-bit Shift하면 12345
	check_case(48'sd12345, 6'd0, 48'sd12345);

	// TODO 9: 32768을 16-bit Shift하면 1
	check_case(48'sd32768, 6'd16, 48'sd1);

	// TODO 10: 지원하지 않는 Shift 48은 0 출력
	check_case(48'sd32768, 6'd48, 48'sd0);

	if (error_count == 0) begin
		$display("========================================");
		$display("ALL TESTS PASSED");
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