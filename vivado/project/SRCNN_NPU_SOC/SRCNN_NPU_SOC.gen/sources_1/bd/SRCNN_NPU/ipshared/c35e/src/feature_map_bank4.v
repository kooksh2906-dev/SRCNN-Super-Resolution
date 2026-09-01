`timescale 1ns / 1ps

module feature_map_bank4 (
    input  wire clk,
    input  wire rst_n,

    // PE0~PE3 결과를 동시에 저장하는 Write Interface
    input  wire               write_valid_i,
    input  wire        [3:0]  write_pe_enable_i,
    input  wire        [5:0]  write_group_i,
    input  wire        [4:0]  write_y_i,
    input  wire        [4:0]  write_x_i,

    input  wire signed [15:0] write_data0_i,
    input  wire signed [15:0] write_data1_i,
    input  wire signed [15:0] write_data2_i,
    input  wire signed [15:0] write_data3_i,

    // 다음 Layer가 Channel별 Activation을 읽는 Read Interface
    input  wire               read_en_i,
    input  wire        [15:0] read_addr_i,

    output reg  signed [15:0] read_data_o
);

    // 각 PE Bank를 Block RAM으로 합성하도록 Vivado에 명시
    // Bank 하나는 16 Group × 32 × 32개의 signed INT16 저장
    (* ram_style = "block" *)
    reg signed [15:0] bank0_mem [0:16383];

    (* ram_style = "block" *)
    reg signed [15:0] bank1_mem [0:16383];

    (* ram_style = "block" *)
    reg signed [15:0] bank2_mem [0:16383];

    (* ram_style = "block" *)
    reg signed [15:0] bank3_mem [0:16383];

    wire [13:0] write_addr;
    wire [1:0]  read_bank_sel;
    wire [13:0] read_bank_addr;

    // 각 BRAM의 동기식 Read Data Register
    reg signed [15:0] bank0_read_data_reg;
    reg signed [15:0] bank1_read_data_reg;
    reg signed [15:0] bank2_read_data_reg;
    reg signed [15:0] bank3_read_data_reg;

    // Read 요청 시 선택된 Bank 번호를 Data와 같은 Cycle까지 유지
    reg [1:0] read_bank_sel_reg;

    // Bank 내부 Write 주소 = Group 4비트 + Y 5비트 + X 5비트
    assign write_addr =
        {write_group_i[3:0], write_y_i, write_x_i};

    // 전체 Read 주소:
    // [15:10] Channel, [9:5] Y, [4:0] X
    // Channel 하위 2비트로 PE Bank 선택
    assign read_bank_sel = read_addr_i[11:10];

    // Channel 하위 2비트를 제거해 Bank 내부 주소 생성
    assign read_bank_addr =
        {read_addr_i[15:12], read_addr_i[9:0]};

    // Bank0: PE0 Write와 Bank0 Channel Read
    always @(posedge clk) begin
        if (!rst_n)
            bank0_read_data_reg <= 16'sd0;
        else begin
            if (write_valid_i && write_pe_enable_i[0])
                bank0_mem[write_addr] <= write_data0_i;

            if (read_en_i && (read_bank_sel == 2'd0))
                bank0_read_data_reg <=
                    bank0_mem[read_bank_addr];
        end
    end

    // Bank1: PE1 Write와 Bank1 Channel Read
    always @(posedge clk) begin
        if (!rst_n)
            bank1_read_data_reg <= 16'sd0;
        else begin
            if (write_valid_i && write_pe_enable_i[1])
                bank1_mem[write_addr] <= write_data1_i;

            if (read_en_i && (read_bank_sel == 2'd1))
                bank1_read_data_reg <=
                    bank1_mem[read_bank_addr];
        end
    end

    // Bank2: PE2 Write와 Bank2 Channel Read
    always @(posedge clk) begin
        if (!rst_n)
            bank2_read_data_reg <= 16'sd0;
        else begin
            if (write_valid_i && write_pe_enable_i[2])
                bank2_mem[write_addr] <= write_data2_i;

            if (read_en_i && (read_bank_sel == 2'd2))
                bank2_read_data_reg <=
                    bank2_mem[read_bank_addr];
        end
    end

    // Bank3: PE3 Write와 Bank3 Channel Read
    always @(posedge clk) begin
        if (!rst_n)
            bank3_read_data_reg <= 16'sd0;
        else begin
            if (write_valid_i && write_pe_enable_i[3])
                bank3_mem[write_addr] <= write_data3_i;

            if (read_en_i && (read_bank_sel == 2'd3))
                bank3_read_data_reg <=
                    bank3_mem[read_bank_addr];
        end
    end

    // 동기식 Read 요청의 Bank 번호도 1 Clock 유지
    always @(posedge clk) begin
        if (!rst_n)
            read_bank_sel_reg <= 2'd0;
        else if (read_en_i)
            read_bank_sel_reg <= read_bank_sel;
    end

    // 1 Clock 전에 선택한 BRAM의 Read Data를 출력
    always @(*) begin
        case (read_bank_sel_reg)
            2'd0: read_data_o = bank0_read_data_reg;
            2'd1: read_data_o = bank1_read_data_reg;
            2'd2: read_data_o = bank2_read_data_reg;
            2'd3: read_data_o = bank3_read_data_reg;
            default: read_data_o = 16'sd0;
        endcase
    end

endmodule
