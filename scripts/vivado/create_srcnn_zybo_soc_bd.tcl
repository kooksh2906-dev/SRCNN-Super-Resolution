#------------------------------------------------------------------------------
# SRCNN NPU Zybo Z7-20 Block Design 생성 Script
#
# 구성
# - Zynq-7000 Processing System
# - AXI SmartConnect
# - SRCNN NPU AXI4-Lite Custom IP
# - Input/Output AXI BRAM Controller + True Dual-Port BRAM
# - NPU DONE IRQ -> Zynq IRQ_F2P
#
# UART는 Zybo Board Preset의 PS UART1(MIO)을 사용한다.
# 생성 Project는 /tmp/srcnn_zybo_soc/vivado_project에 저장한다.
#------------------------------------------------------------------------------

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ../..]]

set soc_root       [file normalize /tmp/srcnn_zybo_soc]
set board_repo_dir [file join $soc_root board_repo]
set ip_repo_dir    [file join $soc_root ip_repo]
set project_dir    [file join $soc_root vivado_project]
set report_dir     [file join $soc_root reports]

set project_name srcnn_zybo_soc
set design_name  srcnn_soc_bd
set part_name    xc7z020clg400-1
set board_vlnv   digilentinc.com:zybo-z7-20:part0:1.2
set srcnn_vlnv   user.org:user:srcnn_npu_axi:1.0

proc srcnn_fail {message} {
    puts "ERROR: $message"
    return -code error $message
}

puts "REPO_ROOT=$repo_root"
puts "PROJECT_DIR=$project_dir"
puts "IP_REPO_DIR=$ip_repo_dir"

if {![file exists [file join $ip_repo_dir srcnn_npu_axi_1_0 component.xml]]} {
    srcnn_fail "Packaged SRCNN IP가 없습니다. Packaging을 먼저 완료하십시오."
}

# 고정된 /tmp Build Project만 새로 생성한다.
if {[file exists $project_dir]} {
    file delete -force $project_dir
}
file mkdir $project_dir
file mkdir $report_dir

# Board Catalog는 첫 Board 조회 전에 설정한다.
if {[file isdirectory $board_repo_dir]} {
    set_param board.repoPaths [list $board_repo_dir]
}

create_project \
    $project_name \
    $project_dir \
    -part $part_name \
    -force

if {[llength [get_board_parts -quiet $board_vlnv]] == 0} {
    srcnn_fail "Zybo Z7-20 Board Part를 찾을 수 없습니다: $board_vlnv"
}
set_property board_part $board_vlnv [current_project]

set_property ip_repo_paths [list $ip_repo_dir] [current_fileset]
update_ip_catalog -rebuild

if {[llength [get_ipdefs -all -quiet $srcnn_vlnv]] == 0} {
    srcnn_fail "IP Catalog에서 SRCNN IP를 찾을 수 없습니다: $srcnn_vlnv"
}

create_bd_design $design_name
current_bd_design $design_name

#------------------------------------------------------------------------------
# IP 생성
#------------------------------------------------------------------------------
set ps7 [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:processing_system7:5.5 \
    processing_system7_0]

# Zybo DDR/FIXED_IO 및 PS UART MIO 설정을 Board Preset에서 적용한다.
apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {apply_board_preset "1" make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable"} \
    $ps7

# GP0 AXI Master, 100 MHz PL Clock, Fabric Interrupt를 사용한다.
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0              {1} \
    CONFIG.PCW_EN_CLK0_PORT               {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ   {100.000000} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT       {1} \
    CONFIG.PCW_IRQ_F2P_INTR               {1}] $ps7

set reset_ctrl [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:proc_sys_reset:5.0 \
    proc_sys_reset_0]

set smartconnect [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:smartconnect:1.0 \
    smartconnect_0]
set_property -dict [list \
    CONFIG.NUM_SI {1} \
    CONFIG.NUM_MI {3}] $smartconnect

set srcnn_ip [create_bd_cell \
    -type ip \
    -vlnv $srcnn_vlnv \
    srcnn_npu_axi_0]

set input_bram_ctrl [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 \
    input_axi_bram_ctrl]
set_property -dict [list \
    CONFIG.DATA_WIDTH       {32} \
    CONFIG.SINGLE_PORT_BRAM {1}] $input_bram_ctrl

set output_bram_ctrl [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 \
    output_axi_bram_ctrl]
set_property -dict [list \
    CONFIG.DATA_WIDTH       {32} \
    CONFIG.SINGLE_PORT_BRAM {1}] $output_bram_ctrl

# Port A/B를 32-bit x 512로 맞춘다.
# Custom IP 내부에서 16-bit Sample 2개를 하나의 32-bit Word로 매핑한다.
set input_bram [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:blk_mem_gen:8.4 \
    input_bram]
set_property -dict [list \
    CONFIG.Memory_Type                              {True_Dual_Port_RAM} \
    CONFIG.Use_Byte_Write_Enable                    {true} \
    CONFIG.Byte_Size                                {8} \
    CONFIG.Write_Width_A                            {32} \
    CONFIG.Read_Width_A                             {32} \
    CONFIG.Write_Depth_A                            {512} \
    CONFIG.Write_Width_B                            {32} \
    CONFIG.Read_Width_B                             {32} \
    CONFIG.Enable_A                                 {Use_ENA_Pin} \
    CONFIG.Enable_B                                 {Use_ENB_Pin} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false}] $input_bram

set output_bram [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:blk_mem_gen:8.4 \
    output_bram]
set_property -dict [list \
    CONFIG.Memory_Type                              {True_Dual_Port_RAM} \
    CONFIG.Use_Byte_Write_Enable                    {true} \
    CONFIG.Byte_Size                                {8} \
    CONFIG.Write_Width_A                            {32} \
    CONFIG.Read_Width_A                             {32} \
    CONFIG.Write_Depth_A                            {512} \
    CONFIG.Write_Width_B                            {32} \
    CONFIG.Read_Width_B                             {32} \
    CONFIG.Enable_A                                 {Use_ENA_Pin} \
    CONFIG.Enable_B                                 {Use_ENB_Pin} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false}] $output_bram

set irq_concat [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:xlconcat:2.1 \
    irq_concat]
set_property CONFIG.NUM_PORTS {1} $irq_concat

#------------------------------------------------------------------------------
# AXI와 BRAM Interface 연결
#------------------------------------------------------------------------------
connect_bd_intf_net \
    [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
    [get_bd_intf_pins smartconnect_0/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins smartconnect_0/M00_AXI] \
    [get_bd_intf_pins srcnn_npu_axi_0/S_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins smartconnect_0/M01_AXI] \
    [get_bd_intf_pins input_axi_bram_ctrl/S_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins smartconnect_0/M02_AXI] \
    [get_bd_intf_pins output_axi_bram_ctrl/S_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins input_axi_bram_ctrl/BRAM_PORTA] \
    [get_bd_intf_pins input_bram/BRAM_PORTA]

connect_bd_intf_net \
    [get_bd_intf_pins srcnn_npu_axi_0/INPUT_BRAM] \
    [get_bd_intf_pins input_bram/BRAM_PORTB]

connect_bd_intf_net \
    [get_bd_intf_pins output_axi_bram_ctrl/BRAM_PORTA] \
    [get_bd_intf_pins output_bram/BRAM_PORTA]

connect_bd_intf_net \
    [get_bd_intf_pins srcnn_npu_axi_0/OUTPUT_BRAM] \
    [get_bd_intf_pins output_bram/BRAM_PORTB]

#------------------------------------------------------------------------------
# Clock와 Reset 연결
#------------------------------------------------------------------------------
connect_bd_net \
    [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
    [get_bd_pins proc_sys_reset_0/slowest_sync_clk] \
    [get_bd_pins smartconnect_0/aclk] \
    [get_bd_pins srcnn_npu_axi_0/s_axi_aclk] \
    [get_bd_pins input_axi_bram_ctrl/s_axi_aclk] \
    [get_bd_pins output_axi_bram_ctrl/s_axi_aclk]

connect_bd_net \
    [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
    [get_bd_pins proc_sys_reset_0/ext_reset_in]

connect_bd_net \
    [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
    [get_bd_pins smartconnect_0/aresetn] \
    [get_bd_pins srcnn_npu_axi_0/s_axi_aresetn] \
    [get_bd_pins input_axi_bram_ctrl/s_axi_aresetn] \
    [get_bd_pins output_axi_bram_ctrl/s_axi_aresetn]

# NPU 완료 Interrupt를 PS Fabric Interrupt 0에 연결한다.
connect_bd_net \
    [get_bd_pins srcnn_npu_axi_0/irq] \
    [get_bd_pins irq_concat/In0]

connect_bd_net \
    [get_bd_pins irq_concat/dout] \
    [get_bd_pins processing_system7_0/IRQ_F2P]

#------------------------------------------------------------------------------
# Address 할당과 BD 검증
#------------------------------------------------------------------------------
assign_bd_address

validate_bd_design
save_bd_design

set bd_file [get_files -quiet */${design_name}.bd]
if {[llength $bd_file] == 0} {
    srcnn_fail "생성된 Block Design 파일을 찾을 수 없습니다."
}

generate_target all $bd_file

set wrapper_files [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper_files
set_property top ${design_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

report_ip_status \
    -file [file join $report_dir bd_ip_status.rpt]

puts "BD_ADDRESS_MAP_BEGIN"
foreach address_segment [get_bd_addr_segs -of_objects \
    [get_bd_addr_spaces processing_system7_0/Data]] {
    puts "ADDRESS_SEGMENT=[get_property NAME $address_segment] OFFSET=[get_property OFFSET $address_segment] RANGE=[get_property RANGE $address_segment]"
}
puts "BD_ADDRESS_MAP_END"

puts "PROJECT_FILE=[get_property DIRECTORY [current_project]]/[get_property NAME [current_project]].xpr"
puts "BD_FILE=[lindex $bd_file 0]"
puts "BD_TOP=${design_name}_wrapper"
puts "BD_VALIDATE=PASS"

close_project
exit 0
