`timescale 1 ns / 1 ps

//------------------------------------------------------------------------------
// SRCNN NPU AXI4-Lite Slave Module
//
// Vivado 2024.2 Create AXI4 Peripheral 템플릿 구조를 유지하면서
// SRCNN 제어 Register, Fixed NPU Core, Output BRAM Copy Engine을 연결한다.
//
// Offset  Register      Access  Bit Definition
// 0x00    CTRL          W1P     [0] START, [1] CLEAR
// 0x04    STATUS        RO      [0] BUSY, [1] DONE, [2] ERROR
// 0x08    WIDTH         RO      32
// 0x0C    HEIGHT        RO      32
// 0x10    CYCLE_COUNT   RO      NPU 연산 구간 Clock 수
// 0x14    LAYER_DEBUG   RO      [1:0] Layer, [3:2] Source,
//                              [4] Write Bank, [5] NPU Run,
//                              [6] Output Copy Busy
// 0x18    ERROR_STATUS  RO      [0] Busy 상태에서 START 요청
// 0x1C    VERSION       RO      0x0001_0000
//
// DONE은 Output BRAM 복사가 끝난 뒤 1로 유지되며 CTRL.CLEAR로 해제한다.
// irq는 DONE과 동일한 Active-High Level 신호이다.
//------------------------------------------------------------------------------
module srcnn_npu_axi_slave_lite_v1_0_S_AXI #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 5
)
(
    // Input Tile BRAM Port B: 32-bit Word에 16-bit Sample 2개 저장
    output wire        input_bram_clk_o,
    output wire        input_bram_rst_o,
    output wire        input_bram_en_o,
    output wire [3:0]  input_bram_we_o,
    output wire [8:0]  input_bram_addr_o,
    output wire [31:0] input_bram_wrdata_o,
    input  wire [31:0] input_bram_rddata_i,

    // Output BRAM Port B: Byte Enable로 16-bit Sample을 Halfword 단위 저장
    output wire        output_bram_clk_o,
    output wire        output_bram_rst_o,
    output wire        output_bram_en_o,
    output wire [3:0]  output_bram_we_o,
    output wire [8:0]  output_bram_addr_o,
    output wire [31:0] output_bram_wrdata_o,
    input  wire [31:0] output_bram_rddata_i,

    // Zynq PS GIC에 연결할 완료 Interrupt
    output wire irq,

    // AXI4-Lite Slave Interface
    input  wire                              S_AXI_ACLK,
    input  wire                              S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  wire [2:0]                        S_AXI_AWPROT,
    input  wire                              S_AXI_AWVALID,
    output wire                              S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                              S_AXI_WVALID,
    output wire                              S_AXI_WREADY,
    output wire [1:0]                        S_AXI_BRESP,
    output wire                              S_AXI_BVALID,
    input  wire                              S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  wire [2:0]                        S_AXI_ARPROT,
    input  wire                              S_AXI_ARVALID,
    output wire                              S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_RDATA,
    output wire [1:0]                        S_AXI_RRESP,
    output wire                              S_AXI_RVALID,
    input  wire                              S_AXI_RREADY
);

    // AXI4-Lite 내부 신호
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg                          axi_awready;
    reg                          axi_wready;
    reg [1:0]                    axi_bresp;
    reg                          axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg                          axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg [1:0]                    axi_rresp;
    reg                          axi_rvalid;
    reg                          aw_en;

    // 32-bit AXI에서 Address [1:0]은 Byte Lane 선택이다.
    localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
    // 8개 Register 선택: Address [4:2]
    localparam integer OPT_MEM_ADDR_BITS = 2;

    wire slv_reg_wren;
    wire slv_reg_rden;
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;

    // CTRL Write-One-Pulse 요청
    wire ctrl_start_req;
    wire ctrl_clear_req;

    // NPU 제어 및 상태
    reg         npu_start_pulse;
    wire        npu_run;
    wire        npu_done_pulse;
    wire [1:0]  npu_layer_index;
    wire [1:0]  npu_activation_source;
    wire        npu_feature_write_bank;

    // NPU Input BRAM Read 신호
    wire        npu_input_bram_en;
    wire [15:0] npu_input_bram_addr;
    reg         input_half_sel_reg;
    wire [15:0] npu_input_bram_data;

    // NPU Final Feature Read 신호
    wire        npu_final_read_en;
    wire [15:0] npu_final_read_addr;
    wire [15:0] npu_final_read_data;

    // Software 상태 Register
    reg         operation_busy;
    reg         done_sticky;
    reg  [31:0] error_status;
    reg  [31:0] cycle_count;

    // Output BRAM Copy Engine
    localparam [1:0] COPY_IDLE  = 2'd0;
    localparam [1:0] COPY_READ  = 2'd1;
    localparam [1:0] COPY_WRITE = 2'd2;

    reg  [1:0] copy_state;
    reg  [9:0] copy_addr;
    wire       copy_busy;
    wire       copy_last_write;

    // Register Read View
    wire [31:0] status_value;
    wire [31:0] layer_debug_value;

    // AXI 출력 연결
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    //------------------------------------------------------------------------------
    // AXI Write Address Channel
    //------------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready <= 1'b0;
            aw_en       <= 1'b1;
        end else begin
            if (!axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awready <= 1'b1;
                aw_en       <= 1'b0;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                axi_awready <= 1'b0;
                aw_en       <= 1'b1;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_awaddr <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        else if (!axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
            axi_awaddr <= S_AXI_AWADDR;
    end

    //------------------------------------------------------------------------------
    // AXI Write Data Channel
    //------------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_wready <= 1'b0;
        else if (!axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en)
            axi_wready <= 1'b1;
        else
            axi_wready <= 1'b0;
    end

    assign slv_reg_wren = axi_wready && S_AXI_WVALID &&
                          axi_awready && S_AXI_AWVALID;

    // CTRL은 저장형 Register가 아니며 유효 Write에서만 Pulse를 만든다.
    assign ctrl_start_req = slv_reg_wren &&
                            (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 3'h0) &&
                            S_AXI_WSTRB[0] && S_AXI_WDATA[0];

    assign ctrl_clear_req = slv_reg_wren &&
                            (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 3'h0) &&
                            S_AXI_WSTRB[0] && S_AXI_WDATA[1];

    //------------------------------------------------------------------------------
    // AXI Write Response Channel
    //------------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_bvalid <= 1'b0;
            axi_bresp  <= 2'b00;
        end else begin
            if (axi_awready && S_AXI_AWVALID &&
                !axi_bvalid && axi_wready && S_AXI_WVALID) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b00;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    //------------------------------------------------------------------------------
    // AXI Read Address Channel
    //------------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready <= 1'b0;
            axi_araddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            if (!axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    //------------------------------------------------------------------------------
    // AXI Read Data/Response Channel
    //------------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_rvalid <= 1'b0;
            axi_rresp  <= 2'b00;
        end else begin
            if (axi_arready && S_AXI_ARVALID && !axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b00;
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    assign status_value = {29'd0,
                           (|error_status),
                           done_sticky,
                           operation_busy};

    assign layer_debug_value = {25'd0,
                                copy_busy,
                                npu_run,
                                npu_feature_write_bank,
                                npu_activation_source,
                                npu_layer_index};

    assign slv_reg_rden = axi_arready && S_AXI_ARVALID && !axi_rvalid;

    always @(*) begin
        case (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
            3'h0:    reg_data_out = 32'h0000_0000;
            3'h1:    reg_data_out = status_value;
            3'h2:    reg_data_out = 32'd32;
            3'h3:    reg_data_out = 32'd32;
            3'h4:    reg_data_out = cycle_count;
            3'h5:    reg_data_out = layer_debug_value;
            3'h6:    reg_data_out = error_status;
            3'h7:    reg_data_out = 32'h0001_0000;
            default: reg_data_out = 32'h0000_0000;
        endcase
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_rdata <= {C_S_AXI_DATA_WIDTH{1'b0}};
        else if (slv_reg_rden)
            axi_rdata <= reg_data_out;
    end

    //------------------------------------------------------------------------------
    // START/BUSY/DONE/ERROR 제어
    //------------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            npu_start_pulse <= 1'b0;
            operation_busy <= 1'b0;
            done_sticky    <= 1'b0;
            error_status   <= 32'h0000_0000;
        end else begin
            // START는 항상 한 Clock 뒤 0으로 복귀한다.
            npu_start_pulse <= 1'b0;

            if (ctrl_clear_req) begin
                done_sticky  <= 1'b0;
                error_status <= 32'h0000_0000;
            end

            if (ctrl_start_req) begin
                if (!operation_busy) begin
                    npu_start_pulse <= 1'b1;
                    operation_busy <= 1'b1;
                    done_sticky    <= 1'b0;
                end else begin
                    // 실행 또는 Output Copy 중 START 요청
                    error_status[0] <= 1'b1;
                end
            end

            if (copy_last_write) begin
                operation_busy <= 1'b0;
                done_sticky    <= 1'b1;
            end
        end
    end

    // NPU 실제 Run 구간의 Cycle 수만 측정한다.
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            cycle_count <= 32'h0000_0000;
        else if (npu_start_pulse)
            cycle_count <= 32'h0000_0000;
        else if (npu_run)
            cycle_count <= cycle_count + 1'b1;
    end

    //------------------------------------------------------------------------------
    // Output BRAM Copy Engine
    // Final Feature Bank의 1-Clock Read Latency를 READ/WRITE 상태로 흡수한다.
    //------------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            copy_state <= COPY_IDLE;
            copy_addr  <= 10'd0;
        end else begin
            case (copy_state)
                COPY_IDLE: begin
                    copy_addr <= 10'd0;
                    if (npu_done_pulse)
                        copy_state <= COPY_READ;
                end

                COPY_READ: begin
                    copy_state <= COPY_WRITE;
                end

                COPY_WRITE: begin
                    if (copy_addr == 10'd1023) begin
                        copy_state <= COPY_IDLE;
                        copy_addr  <= 10'd0;
                    end else begin
                        copy_addr  <= copy_addr + 1'b1;
                        copy_state <= COPY_READ;
                    end
                end

                default: begin
                    copy_state <= COPY_IDLE;
                    copy_addr  <= 10'd0;
                end
            endcase
        end
    end

    assign copy_busy       = (copy_state != COPY_IDLE);
    assign copy_last_write = (copy_state == COPY_WRITE) &&
                             (copy_addr == 10'd1023);

    assign npu_final_read_en   = (copy_state == COPY_READ);
    assign npu_final_read_addr = {6'd0, copy_addr};

    //------------------------------------------------------------------------------
    // Input/Output BRAM Native Port 연결
    // 양쪽 Port를 32-bit로 맞춰 AXI BRAM Controller의 Byte Enable을 유지한다.
    // NPU의 16-bit Address LSB로 32-bit Word의 하위/상위 Halfword를 선택한다.
    //------------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            input_half_sel_reg <= 1'b0;
        else if (npu_input_bram_en)
            input_half_sel_reg <= npu_input_bram_addr[0];
    end

    assign npu_input_bram_data = input_half_sel_reg ?
                                 input_bram_rddata_i[31:16] :
                                 input_bram_rddata_i[15:0];

    assign input_bram_clk_o    = S_AXI_ACLK;
    assign input_bram_rst_o    = ~S_AXI_ARESETN;
    assign input_bram_en_o     = npu_input_bram_en;
    assign input_bram_we_o     = 4'b0000;
    assign input_bram_addr_o   = npu_input_bram_addr[9:1];
    assign input_bram_wrdata_o = 32'h0000_0000;

    assign output_bram_clk_o    = S_AXI_ACLK;
    assign output_bram_rst_o    = ~S_AXI_ARESETN;
    assign output_bram_en_o     = (copy_state == COPY_WRITE);
    assign output_bram_we_o     = (copy_state != COPY_WRITE) ? 4'b0000 :
                                  (copy_addr[0] ? 4'b1100 : 4'b0011);
    assign output_bram_addr_o   = copy_addr[9:1];
    assign output_bram_wrdata_o = copy_addr[0] ?
                                  {npu_final_read_data, 16'h0000} :
                                  {16'h0000, npu_final_read_data};

    // DONE이 CLEAR될 때까지 Interrupt를 유지한다.
    assign irq = done_sticky;

    //------------------------------------------------------------------------------
    // Fixed Parameter SRCNN NPU Core
    //------------------------------------------------------------------------------
    srcnn_npu_fixed_top u_srcnn_npu_fixed_top (
        .clk                    (S_AXI_ACLK),
        .rst_n                  (S_AXI_ARESETN),
        .start_i                (npu_start_pulse),
        .input_tile_data_i      (npu_input_bram_data),
        .input_tile_bram_en_o   (npu_input_bram_en),
        .input_tile_bram_addr_o (npu_input_bram_addr),
        .final_read_en_i        (npu_final_read_en),
        .final_read_addr_i      (npu_final_read_addr),
        .final_read_data_o      (npu_final_read_data),
        .run_o                  (npu_run),
        .done_o                 (npu_done_pulse),
        .layer_index_o          (npu_layer_index),
        .activation_source_o    (npu_activation_source),
        .feature_write_bank_o   (npu_feature_write_bank)
    );

    // 현재 사용하지 않는 신호
    // S_AXI_AWPROT, S_AXI_ARPROT, output_bram_rddata_i

endmodule
