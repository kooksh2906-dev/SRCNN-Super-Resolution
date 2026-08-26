`timescale 1ns / 1ps

module tb_weight_stream_addr_gen;

    reg         clk;
    reg         rst_n;
    reg         sequence_start_i;
    reg         read_en_i;
    reg  [5:0]  out_channel_group_i;
    reg  [15:0] weight_word_base_addr_i;

    wire [15:0] weight_word_addr_o;

    integer error_count;
    integer group_check_count;
    integer address_check_count;
    integer group_index;

    weight_stream_addr_gen dut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .sequence_start_i       (sequence_start_i),
        .read_en_i              (read_en_i),
        .out_channel_group_i    (out_channel_group_i),
        .weight_word_base_addr_i(weight_word_base_addr_i),
        .weight_word_addr_o     (weight_word_addr_o)
    );

    always #5 clk = ~clk;

    task check_sequence;
        input [15:0] base_addr;
        input [5:0]  group_number;
        input [15:0] first_addr;
        input integer word_count;

        integer word_index;
        reg [15:0] expected_addr;
        begin
            @(negedge clk);
            weight_word_base_addr_i = base_addr;
            out_channel_group_i     = group_number;
            read_en_i               = 1'b0;
            sequence_start_i        = 1'b1;

            @(posedge clk);
            #1;

            group_check_count = group_check_count + 1;

            if (weight_word_addr_o !== first_addr) begin
                error_count = error_count + 1;
                $display(
                    "[FAIL][START] base=%0d group=%0d actual=%0d expected=%0d",
                    base_addr,
                    group_number,
                    weight_word_addr_o,
                    first_addr
                );
            end

            @(negedge clk);
            sequence_start_i = 1'b0;

            for (word_index = 0;
                 word_index < word_count;
                 word_index = word_index + 1) begin

                expected_addr = first_addr + word_index;

                if (weight_word_addr_o !== expected_addr) begin
                    error_count = error_count + 1;

                    if (error_count <= 10) begin
                        $display(
                            "[FAIL][STREAM] base=%0d group=%0d index=%0d actual=%0d expected=%0d",
                            base_addr,
                            group_number,
                            word_index,
                            weight_word_addr_o,
                            expected_addr
                        );
                    end
                end

                address_check_count = address_check_count + 1;
                read_en_i = 1'b1;

                @(posedge clk);
                #1;
                @(negedge clk);
            end

            read_en_i = 1'b0;
        end
    endtask

    initial begin
        clk                     = 1'b0;
        rst_n                   = 1'b0;
        sequence_start_i        = 1'b0;
        read_en_i               = 1'b0;
        out_channel_group_i     = 6'd0;
        weight_word_base_addr_i = 16'd0;

        error_count         = 0;
        group_check_count   = 0;
        address_check_count = 0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // Conv1 전체 16 Group: 16 × 81 = 1296 Word
        for (group_index = 0;
             group_index < 16;
             group_index = group_index + 1) begin
            check_sequence(
                16'd0,
                group_index[5:0],
                group_index * 81,
                81
            );
        end

        // Conv2 전체 8 Group: 8 × 1600 = 12800 Word
        for (group_index = 0;
             group_index < 8;
             group_index = group_index + 1) begin
            check_sequence(
                16'd1296,
                group_index[5:0],
                16'd1296 + group_index * 1600,
                1600
            );
        end

        // Conv3 단일 Group: 32 × 5 × 5 = 800 Word
        check_sequence(16'd14096, 6'd0, 16'd14096, 800);

        $display("========================================");
        $display("Weight Stream Address Test Completed");
        $display("group_check_count   = %0d / 25", group_check_count);
        $display(
            "address_check_count = %0d / 14896",
            address_check_count
        );
        $display("error_count         = %0d", error_count);

        if ((group_check_count == 25) &&
            (address_check_count == 14896) &&
            (error_count == 0))
            $display("[PASS] All fixed SRCNN Weight addresses passed");
        else
            $display("[FAIL] Weight stream address test failed");

        $display("========================================");
        $finish;
    end

    initial begin
        #500000;
        $display("[FAIL] Weight stream address simulation timeout");
        $finish;
    end

endmodule
