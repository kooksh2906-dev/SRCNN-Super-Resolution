`timescale 1 ns / 1 ps

//------------------------------------------------------------------------------
// SRCNN NPU AXI Custom IP Top
// Vivado Create AXI4 Peripheral 형식의 Top/Slave 계층을 유지한다.
//------------------------------------------------------------------------------
module srcnn_npu_axi #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 5
)
(
    // Input BRAM Port B
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 INPUT_BRAM CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME INPUT_BRAM, MASTER_TYPE BRAM_CTRL, MEM_SIZE 2048" *)
    output wire        input_bram_clk_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 INPUT_BRAM RST" *)
    output wire        input_bram_rst_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 INPUT_BRAM EN" *)
    output wire        input_bram_en_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 INPUT_BRAM WE" *)
    output wire [3:0]  input_bram_we_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 INPUT_BRAM ADDR" *)
    output wire [8:0]  input_bram_addr_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 INPUT_BRAM DIN" *)
    output wire [31:0] input_bram_wrdata_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 INPUT_BRAM DOUT" *)
    input  wire [31:0] input_bram_rddata_i,

    // Output BRAM Port B
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 OUTPUT_BRAM CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME OUTPUT_BRAM, MASTER_TYPE BRAM_CTRL, MEM_SIZE 2048" *)
    output wire        output_bram_clk_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 OUTPUT_BRAM RST" *)
    output wire        output_bram_rst_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 OUTPUT_BRAM EN" *)
    output wire        output_bram_en_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 OUTPUT_BRAM WE" *)
    output wire [3:0]  output_bram_we_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 OUTPUT_BRAM ADDR" *)
    output wire [8:0]  output_bram_addr_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 OUTPUT_BRAM DIN" *)
    output wire [31:0] output_bram_wrdata_o,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 OUTPUT_BRAM DOUT" *)
    input  wire [31:0] output_bram_rddata_i,

    // Active-High Level Interrupt
    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 IRQ INTERRUPT" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME IRQ, SENSITIVITY LEVEL_HIGH, PortWidth 1" *)
    output wire irq,

    // AXI4-Lite Clock/Reset
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 S_AXI_CLK CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_CLK, ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn, FREQ_HZ 100000000" *)
    input wire s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 S_AXI_RST RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_RST, POLARITY ACTIVE_LOW" *)
    input wire s_axi_aresetn,

    // AXI4-Lite Slave Interface
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 5, FREQ_HZ 100000000, READ_WRITE_MODE READ_WRITE" *)
    input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input wire [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input wire s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input wire s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input wire s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input wire [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input wire s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input wire s_axi_rready
);

    srcnn_npu_axi_slave_lite_v1_0_S_AXI #
    (
        .C_S_AXI_DATA_WIDTH (C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH (C_S_AXI_ADDR_WIDTH)
    ) u_srcnn_npu_axi_slave (
        .input_bram_clk_o    (input_bram_clk_o),
        .input_bram_rst_o    (input_bram_rst_o),
        .input_bram_en_o     (input_bram_en_o),
        .input_bram_we_o     (input_bram_we_o),
        .input_bram_addr_o   (input_bram_addr_o),
        .input_bram_wrdata_o (input_bram_wrdata_o),
        .input_bram_rddata_i (input_bram_rddata_i),

        .output_bram_clk_o    (output_bram_clk_o),
        .output_bram_rst_o    (output_bram_rst_o),
        .output_bram_en_o     (output_bram_en_o),
        .output_bram_we_o     (output_bram_we_o),
        .output_bram_addr_o   (output_bram_addr_o),
        .output_bram_wrdata_o (output_bram_wrdata_o),
        .output_bram_rddata_i (output_bram_rddata_i),

        .irq          (irq),
        .S_AXI_ACLK   (s_axi_aclk),
        .S_AXI_ARESETN(s_axi_aresetn),
        .S_AXI_AWADDR (s_axi_awaddr),
        .S_AXI_AWPROT (s_axi_awprot),
        .S_AXI_AWVALID(s_axi_awvalid),
        .S_AXI_AWREADY(s_axi_awready),
        .S_AXI_WDATA  (s_axi_wdata),
        .S_AXI_WSTRB  (s_axi_wstrb),
        .S_AXI_WVALID (s_axi_wvalid),
        .S_AXI_WREADY (s_axi_wready),
        .S_AXI_BRESP  (s_axi_bresp),
        .S_AXI_BVALID (s_axi_bvalid),
        .S_AXI_BREADY (s_axi_bready),
        .S_AXI_ARADDR (s_axi_araddr),
        .S_AXI_ARPROT (s_axi_arprot),
        .S_AXI_ARVALID(s_axi_arvalid),
        .S_AXI_ARREADY(s_axi_arready),
        .S_AXI_RDATA  (s_axi_rdata),
        .S_AXI_RRESP  (s_axi_rresp),
        .S_AXI_RVALID (s_axi_rvalid),
        .S_AXI_RREADY (s_axi_rready)
    );

endmodule
