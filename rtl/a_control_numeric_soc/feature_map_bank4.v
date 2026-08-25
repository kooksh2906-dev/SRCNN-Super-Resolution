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

    // Bank 하나당 최대 16 Group × 32 × 32 = 16384개 INT16 저장
    reg signed [15:0] bank0_mem [0:16383];
    reg signed [15:0] bank1_mem [0:16383];
    reg signed [15:0] bank2_mem [0:16383];
    reg signed [15:0] bank3_mem [0:16383];

    wire [13:0] write_addr;
    wire [1:0]  read_bank_sel;
    wire [13:0] read_bank_addr;

    // Bank 내부 Write 주소 = Group 4-bit + Y 5-bit + X 5-bit
    assign write_addr = {write_group_i[3:0], write_y_i, write_x_i};

    // read_addr_i의 Channel 하위 2비트로 Bank 선택
    // read_addr_i 구조:
    // [15:10] Channel, [9:5] Y, [4:0] X
    assign read_bank_sel = read_addr_i[11:10];

    // Bank 내부 Read 주소에서 Channel 하위 2비트를 제거
    // 주소 = Channel Group 4-bit + Y/X 10-bit
    assign read_bank_addr = {read_addr_i[15:12],read_addr_i[9:0]};

    // PE별 Bank에 한 Clock 동안 최대 4개 결과를 동시에 저장
    always @(posedge clk) begin
        // write_valid_i와 각 write_pe_enable_i가 모두 1일 때만 Write
        if (rst_n && write_valid_i && write_pe_enable_i[0])
            bank0_mem[write_addr] <= write_data0_i;

        if (rst_n && write_valid_i && write_pe_enable_i[1])
            bank1_mem[write_addr] <= write_data1_i;

        if (rst_n && write_valid_i && write_pe_enable_i[2])
            bank2_mem[write_addr] <= write_data2_i;

        if (rst_n && write_valid_i && write_pe_enable_i[3])
            bank3_mem[write_addr] <= write_data3_i;
    end

    // 선택한 Bank에서 1-Clock Latency로 Activation Read
    always @(posedge clk) begin
        if (!rst_n)
            read_data_o <= 16'sd0;
        else if (read_en_i) begin
            // read_bank_sel에 따라 Bank0~Bank3 중 하나를 선택
            case (read_bank_sel)
                2'd0: read_data_o <= bank0_mem[read_bank_addr];
                2'd1: read_data_o <= bank1_mem[read_bank_addr];
                2'd2: read_data_o <= bank2_mem[read_bank_addr];
                2'd3: read_data_o <= bank3_mem[read_bank_addr];
                default: read_data_o <= 16'sd0;
            endcase
        end
    end

endmodule
