
`timescale 1 ns / 1 ps

	module AXI4_SRCNN_NPU_slave_lite_v1_0_S00_AXI #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line

		// Width of S_AXI data bus
		parameter integer C_S_AXI_DATA_WIDTH	= 32,
		// Width of S_AXI address bus
		parameter integer C_S_AXI_ADDR_WIDTH	= 6
	)
	(
		// Users to add ports here

        // Input Tile BRAM -> NPU
        input  wire signed [15:0] input_tile_data_i,
        output wire               input_tile_bram_en_o,
        output wire        [15:0] input_tile_bram_addr_o,

		// User ports ends
		// Do not modify the ports beyond this line

		// Global Clock Signal
		input wire  S_AXI_ACLK,
		// Global Reset Signal. This Signal is Active LOW
		input wire  S_AXI_ARESETN,
		// Write address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
		// Write channel Protection type. This signal indicates the
    		// privilege and security level of the transaction, and whether
    		// the transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_AWPROT,
		// Write address valid. This signal indicates that the master signaling
    		// valid write address and control information.
		input wire  S_AXI_AWVALID,
		// Write address ready. This signal indicates that the slave is ready
    		// to accept an address and associated control signals.
		output wire  S_AXI_AWREADY,
		// Write data (issued by master, acceped by Slave)
		input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
		// Write strobes. This signal indicates which byte lanes hold
    		// valid data. There is one write strobe bit for each eight
    		// bits of the write data bus.
		input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
		// Write valid. This signal indicates that valid write
    		// data and strobes are available.
		input wire  S_AXI_WVALID,
		// Write ready. This signal indicates that the slave
    		// can accept the write data.
		output wire  S_AXI_WREADY,
		// Write response. This signal indicates the status
    		// of the write transaction.
		output wire [1 : 0] S_AXI_BRESP,
		// Write response valid. This signal indicates that the channel
    		// is signaling a valid write response.
		output wire  S_AXI_BVALID,
		// Response ready. This signal indicates that the master
    		// can accept a write response.
		input wire  S_AXI_BREADY,
		// Read address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
		// Protection type. This signal indicates the privilege
    		// and security level of the transaction, and whether the
    		// transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_ARPROT,
		// Read address valid. This signal indicates that the channel
    		// is signaling valid read address and control information.
		input wire  S_AXI_ARVALID,
		// Read address ready. This signal indicates that the slave is
    		// ready to accept an address and associated control signals.
		output wire  S_AXI_ARREADY,
		// Read data (issued by slave)
		output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
		// Read response. This signal indicates the status of the
    		// read transfer.
		output wire [1 : 0] S_AXI_RRESP,
		// Read valid. This signal indicates that the channel is
    		// signaling the required read data.
		output wire  S_AXI_RVALID,
		// Read ready. This signal indicates that the master can
    		// accept the read data and response information.
		input wire  S_AXI_RREADY
	);

	// AXI4LITE signals
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
	reg  	axi_awready;
	reg  	axi_wready;
	reg [1 : 0] 	axi_bresp;
	reg  	axi_bvalid;
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
	reg  	axi_arready;
	reg [1 : 0] 	axi_rresp;
	reg  	axi_rvalid;

	// Example-specific design signals
	// local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	// ADDR_LSB is used for addressing 32/64 bit registers/memories
	// ADDR_LSB = 2 for 32 bits (n downto 2)
	// ADDR_LSB = 3 for 64 bits (n downto 3)
	localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
	localparam integer OPT_MEM_ADDR_BITS = 3;
	//----------------------------------------------
	//-- Signals for user logic register space example
	//------------------------------------------------
	//-- Number of Slave Registers 9
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg0;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg1;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg2;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg3;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg4;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg5;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg6;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg7;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg8;
	integer	 byte_index;

	// I/O Connections assignments

	assign S_AXI_AWREADY	= axi_awready;
	assign S_AXI_WREADY	= axi_wready;
	assign S_AXI_BRESP	= axi_bresp;
	assign S_AXI_BVALID	= axi_bvalid;
	assign S_AXI_ARREADY	= axi_arready;
	assign S_AXI_RRESP	= axi_rresp;
	assign S_AXI_RVALID	= axi_rvalid;
	 //state machine varibles
	 reg [1:0] state_write;
	 reg [1:0] state_read;
	 //State machine local parameters
	 localparam Idle = 2'b00,Raddr = 2'b10,Rdata = 2'b11 ,Waddr = 2'b10,Wdata = 2'b11;
	// Implement Write state machine
	// Outstanding write transactions are not supported by the slave i.e., master should assert bready to receive response on or before it starts sending the new transaction
	always @(posedge S_AXI_ACLK)
	  begin
	     if (S_AXI_ARESETN == 1'b0)
	       begin
	         axi_awready <= 0;
	         axi_wready <= 0;
	         axi_bvalid <= 0;
	         axi_bresp <= 0;
	         axi_awaddr <= 0;
	         state_write <= Idle;
	       end
	     else
	       begin
	         case(state_write)
	           Idle:
	             begin
	               if(S_AXI_ARESETN == 1'b1)
	                 begin
	                   axi_awready <= 1'b1;
	                   axi_wready <= 1'b1;
	                   state_write <= Waddr;
	                 end
	               else state_write <= state_write;
	             end
	           Waddr:        //At this state, slave is ready to receive address along with corresponding control signals and first data packet. Response valid is also handled at this state
	             begin
	               if (S_AXI_AWVALID && S_AXI_AWREADY)
	                  begin
	                    axi_awaddr <= S_AXI_AWADDR;
	                    if(S_AXI_WVALID)
	                      begin
	                        axi_awready <= 1'b1;
	                        state_write <= Waddr;
	                        axi_bvalid <= 1'b1;
	                      end
	                    else
	                      begin
	                        axi_awready <= 1'b0;
	                        state_write <= Wdata;
	                        if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
	                      end
	                  end
	               else
	                  begin
	                    state_write <= state_write;
	                    if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
	                   end
	             end
	          Wdata:        //At this state, slave is ready to receive the data packets until the number of transfers is equal to burst length
	             begin
	               if (S_AXI_WVALID)
	                 begin
	                   state_write <= Waddr;
	                   axi_bvalid <= 1'b1;
	                   axi_awready <= 1'b1;
	                 end
	                else
	                 begin
	                   state_write <= state_write;
	                   if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
	                 end
	             end
	          endcase
	        end
	      end

	// Implement memory mapped register select and write logic generation
	// The write data is accepted and written to memory mapped registers when
	// axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
	// select byte enables of slave registers while writing.
	// These registers are cleared when reset (active low) is applied.
	// Slave register write enable is asserted when valid address and data are available
	// and the slave is ready to accept the write address and write data.


	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      slv_reg0 <= 0;
	      slv_reg1 <= 0;
	      slv_reg2 <= 0;
	      slv_reg3 <= 0;
	      slv_reg4 <= 0;
	      slv_reg5 <= 0;
	      slv_reg6 <= 0;
	      slv_reg7 <= 0;
	      slv_reg8 <= 0;
	    end
	  else begin
	    if (S_AXI_WVALID)
	      begin
	        case ( (S_AXI_AWVALID) ? S_AXI_AWADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] : axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
	          4'h0:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes
	                // Slave register 0
	                slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end
	          4'h1:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes
	                // Slave register 1
	                slv_reg1[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end
	          4'h2:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes
	                // Slave register 2
	                slv_reg2[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end
	          4'h3:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes
	                // Slave register 3
	                slv_reg3[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end
	          4'h4:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes
	                // Slave register 4
	                slv_reg4[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end
	          4'h5:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes
	                // Slave register 5
	                slv_reg5[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end
	          4'h6:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes
	                // Slave register 6
	                slv_reg6[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end
	          4'h7:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // Respective byte enables are asserted as per write strobes
	                // Slave register 7
	                slv_reg7[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end
	          4'h8:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                // TILE_POS: bits [3:0] = tile_x, bits [7:4] = tile_y
	                slv_reg8[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end
	          default : begin
	                      slv_reg0 <= slv_reg0;
	                      slv_reg1 <= slv_reg1;
	                      slv_reg2 <= slv_reg2;
	                      slv_reg3 <= slv_reg3;
	                      slv_reg4 <= slv_reg4;
	                      slv_reg5 <= slv_reg5;
	                      slv_reg6 <= slv_reg6;
	                      slv_reg7 <= slv_reg7;
	                      slv_reg8 <= slv_reg8;
	                    end
	        endcase
	      end
	  end
	end

	// Implement read state machine
	  always @(posedge S_AXI_ACLK)
	    begin
	      if (S_AXI_ARESETN == 1'b0)
	        begin
	         //asserting initial values to all 0's during reset
	         axi_arready <= 1'b0;
	         axi_rvalid <= 1'b0;
	         axi_rresp <= 1'b0;
	         state_read <= Idle;
	        end
	      else
	        begin
	          case(state_read)
	            Idle:     //Initial state inidicating reset is done and ready to receive read/write transactions
	              begin
	                if (S_AXI_ARESETN == 1'b1)
	                  begin
	                    state_read <= Raddr;
	                    axi_arready <= 1'b1;
	                  end
	                else state_read <= state_read;
	              end
	            Raddr:        //At this state, slave is ready to receive address along with corresponding control signals
	              begin
	                if (S_AXI_ARVALID && S_AXI_ARREADY)
	                  begin
	                    state_read <= Rdata;
	                    axi_araddr <= S_AXI_ARADDR;
	                    axi_rvalid <= 1'b1;
	                    axi_arready <= 1'b0;
	                  end
	                else state_read <= state_read;
	              end
	            Rdata:        //At this state, slave is ready to send the data packets until the number of transfers is equal to burst length
	              begin
	                if (S_AXI_RVALID && S_AXI_RREADY)
	                  begin
	                    axi_rvalid <= 1'b0;
	                    axi_arready <= 1'b1;
	                    state_read <= Raddr;
	                  end
	                else state_read <= state_read;
	              end
	           endcase
	          end
	        end
	// Implement memory mapped register select and read logic generation

	// ---------------------------------------------------------
    // SRCNN NPU internal signals
    // ---------------------------------------------------------
    reg        npu_start_pulse;
    reg  [3:0] active_tile_x_reg;
    reg  [3:0] active_tile_y_reg;

    wire       npu_run;
    wire       npu_done;
    wire [1:0] npu_layer_index;

    wire signed [15:0] npu_final_read_data;

    wire [1:0] npu_activation_source;
    wire       npu_feature_write_bank;

    // DONE은 NPU에서 1 clock pulse이므로 저장 필요
    reg        npu_done_latched;

    // Cycle Counter
    reg [31:0] npu_cycle_count;
    reg        cycle_count_active;

    wire [3:0] write_reg_index;

    assign write_reg_index =
        (S_AXI_AWVALID) ?
        S_AXI_AWADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] :
        axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB];

    wire ctrl_write;

    assign ctrl_write =
        S_AXI_WVALID &&
        S_AXI_WREADY &&
        (write_reg_index == 4'h0);

    always @(posedge S_AXI_ACLK)begin
        if (!S_AXI_ARESETN) begin
            npu_start_pulse   <= 1'b0;
            active_tile_x_reg <= 4'd0;
            active_tile_y_reg <= 4'd0;
        end
        else begin
            // 기본은 항상 0
            npu_start_pulse <= 1'b0;

            // CTRL 0x00 bit0 = START
            if (ctrl_write && S_AXI_WSTRB[0] && S_AXI_WDATA[0] && !npu_run) begin
                npu_start_pulse <= 1'b1;
                active_tile_x_reg <= slv_reg8[3:0];
                active_tile_y_reg <= slv_reg8[7:4];
            end
        end
    end

    always @(posedge S_AXI_ACLK)begin
        if (!S_AXI_ARESETN) begin
            npu_done_latched <= 1'b0;
        end
        else begin

            // 새로운 연산 시작 시 이전 DONE 제거
            if (npu_start_pulse)
                npu_done_latched <= 1'b0;

            // CTRL bit1 = CLEAR
            else if (ctrl_write && S_AXI_WSTRB[0] && S_AXI_WDATA[1])
                npu_done_latched <= 1'b0;

            // NPU에서 1 clock DONE 발생
            else if (npu_done)
                npu_done_latched <= 1'b1;

        end
    end

    always @(posedge S_AXI_ACLK)begin
        if (!S_AXI_ARESETN) begin
            npu_cycle_count   <= 32'd0;
            cycle_count_active <= 1'b0;
        end
        else begin

            if (npu_start_pulse) begin
                npu_cycle_count    <= 32'd0;
                cycle_count_active <= 1'b1;
            end

            else if (cycle_count_active) begin
                npu_cycle_count <= npu_cycle_count + 1'b1;

                if (npu_done)
                    cycle_count_active <= 1'b0;
            end

        end
    end

	  assign S_AXI_RDATA = (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h0) ? 32'd0 :
	                       (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h1) ? {29'd0, 1'b0, npu_done_latched, npu_run} :
	                       (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h2) ? slv_reg2  :
	                       (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h3) ? {{16{npu_final_read_data[15]}}, npu_final_read_data} :
	                       (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h4) ? npu_cycle_count :
	                       (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h5) ? (npu_run ? {30'd0, (npu_layer_index + 2'd1)} : 32'd0) :
	                       (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h6) ? 32'd0 :
	                       (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h7) ? 32'h0001_0001 :
	                       (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h8) ? slv_reg8 : 32'd0;
	// Add user logic here
    srcnn_npu_fixed_top ins_SRCNN_NPU (
    .clk                    (S_AXI_ACLK),
    .rst_n                  (S_AXI_ARESETN),

    // AXI CTRL 0x00 bit0 -> 1 clock START pulse
    .start_i                (npu_start_pulse),
    .tile_x_i               (active_tile_x_reg),
    .tile_y_i               (active_tile_y_reg),

    // Input Tile BRAM
    .input_tile_data_i      (input_tile_data_i),
    .input_tile_bram_en_o   (input_tile_bram_en_o),
    .input_tile_bram_addr_o (input_tile_bram_addr_o),

    // Final Conv3 result read
    .final_read_en_i        (1'b1),
    .final_read_addr_i      (slv_reg2[15:0]),
    .final_read_data_o      (npu_final_read_data),

    // NPU status
    .run_o                  (npu_run),
    .done_o                 (npu_done),
    .layer_index_o          (npu_layer_index),

    // Debug
    .activation_source_o    (npu_activation_source),
    .feature_write_bank_o   (npu_feature_write_bank)
    );
	// User logic ends

	endmodule
