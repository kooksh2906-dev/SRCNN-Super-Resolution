#------------------------------------------------------------------------------
# SRCNN NPU AXI Custom IP Packaging Script
#
# 실행 위치와 관계없이 이 파일의 위치를 기준으로 Repository Root를 계산한다.
# 이 파일은 Repository의 scripts/vivado/ 아래에 저장한다.
# 생성 Project와 Packaged IP는 /tmp/srcnn_zybo_soc 아래에만 만든다.
#------------------------------------------------------------------------------

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ../..]]

set soc_root         [file normalize /tmp/srcnn_zybo_soc]
set board_repo_dir   [file join $soc_root board_repo]
set ip_repo_dir      [file join $soc_root ip_repo]
set ip_root          [file join $ip_repo_dir AXI4_SRCNN_NPU_1_0]
set pack_project_dir [file join $soc_root AXI4_SRCNN_NPU_pack_project]
set wizard_backup    [file join $soc_root wizard_backup AXI4_SRCNN_NPU_1_0]

set part_name  xc7z020clg400-1
set board_vlnv digilentinc.com:zybo-z7-20:part0:1.2
set top_name   AXI4_SRCNN_NPU

proc srcnn_fail {message} {
    puts "ERROR: $message"
    return -code error $message
}

puts "REPO_ROOT=$repo_root"
puts "SOC_ROOT=$soc_root"
puts "IP_ROOT=$ip_root"

if {![file isdirectory $repo_root]} {
    srcnn_fail "Repository Root를 찾을 수 없습니다: $repo_root"
}

set required_files [list \
    [file join $repo_root rtl a_control_numeric_soc AXI4_SRCNN_NPU.v] \
    [file join $repo_root rtl a_control_numeric_soc AXI4_SRCNN_NPU_slave_lite_v1_0_S00_AXI.v] \
    [file join $repo_root rtl a_control_numeric_soc srcnn_npu_fixed_top.v] \
    [file join $repo_root rtl a_control_numeric_soc srcnn_npu_top.v] \
    [file join $repo_root rtl a_control_numeric_soc global_boundary_mask.v] \
    [file join $repo_root rtl b_compute_core srcnn_compute_core.v] \
    [file join $repo_root rtl mem_init srcnn_weights_all.hex] \
    [file join $repo_root rtl mem_init srcnn_biases_all.hex]]

foreach required_file $required_files {
    if {![file exists $required_file]} {
        srcnn_fail "필수 RTL 파일이 없습니다: $required_file"
    }
}

file mkdir $soc_root
file mkdir $ip_repo_dir

# 최초 실행에서는 Wizard 생성본을 별도 위치에 보존한다.
# 재실행에서는 이전 최종 Packaged IP만 새로 만든다.
if {[file exists $ip_root]} {
    if {![file exists $wizard_backup]} {
        file mkdir [file dirname $wizard_backup]
        file rename $ip_root $wizard_backup
        puts "WIZARD_BACKUP=$wizard_backup"
    } else {
        file delete -force $ip_root
    }
}

if {[file exists $pack_project_dir]} {
    file delete -force $pack_project_dir
}

# Board Repository는 첫 Board 조회보다 먼저 설정한다.
if {[file isdirectory $board_repo_dir]} {
    set_param board.repoPaths [list $board_repo_dir]
}

create_project \
    AXI4_SRCNN_NPU_pack \
    $pack_project_dir \
    -part $part_name \
    -force

if {[llength [get_board_parts -quiet $board_vlnv]] > 0} {
    set_property board_part $board_vlnv [current_project]
}

# Role A Control RTL과 Role B Compute RTL을 모두 Self-Contained IP에 포함한다.
set rtl_sources {}
foreach rtl_dir [list \
    [file join $repo_root rtl a_control_numeric_soc] \
    [file join $repo_root rtl b_compute_core]] {

    foreach rtl_file [glob -nocomplain -directory $rtl_dir *.v] {
        lappend rtl_sources [file normalize $rtl_file]
    }
}

set rtl_sources [lsort -unique $rtl_sources]
if {[llength $rtl_sources] == 0} {
    srcnn_fail "Packaging할 Verilog RTL이 없습니다."
}

add_files -norecurse $rtl_sources
set_property top $top_name [current_fileset]
update_compile_order -fileset sources_1

puts "RTL_SOURCE_COUNT=[llength $rtl_sources]"
puts "RTL_TOP=[get_property TOP [current_fileset]]"

# AMD Vivado IP Packager 표준 Project Packaging Flow
ipx::package_project \
    -root_dir $ip_root \
    -vendor user.org \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -set_current true

set core [ipx::current_core]

set_property vendor              user.org $core
set_property library             user $core
set_property name                AXI4_SRCNN_NPU $core
set_property version             1.0 $core
set_property display_name        {AXI4 SRCNN NPU v1.0} $core
set_property description         {Fixed-parameter 3-layer SRCNN NPU with AXI4-Lite control, input BRAM pins, and register-based result readout} $core
set_property vendor_display_name {SRCNN NPU Team} $core
set_property core_revision       5 $core
set_property supported_families  {zynq Production} $core

# 팀원 B의 Vivado AXI4-Lite Wizard 구조와 동일한 Interface를 검사한다.
foreach interface_name {S00_AXI S00_AXI_CLK S00_AXI_RST} {
    set interface_object [ipx::get_bus_interfaces -quiet -of_objects $core $interface_name]
    if {[llength $interface_object] == 0} {
        srcnn_fail "Interface 추론 실패: $interface_name"
    }
}

# AXI4-Lite Address Space: 0x00 ~ 0x20, 64 Byte Range
set s_axi_if [lindex [ipx::get_bus_interfaces -quiet -of_objects $core S00_AXI] 0]
set memory_maps [ipx::get_memory_maps -quiet -of_objects $core S00_AXI]

if {[llength $memory_maps] == 0} {
    set memory_map [ipx::add_memory_map S00_AXI $core]
} else {
    set memory_map [lindex $memory_maps 0]
}

set_property slave_memory_map_ref [get_property NAME $memory_map] $s_axi_if

set address_blocks [ipx::get_address_blocks -quiet -of_objects $memory_map]
if {[llength $address_blocks] == 0} {
    set address_block [ipx::add_address_block S00_AXI_reg $memory_map]
    set_property range 0x40 $address_block
    set_property width 32 $address_block
    set_property usage register $address_block
} else {
    set address_block [lindex $address_blocks 0]
    set_property range 0x40 $address_block
    set_property width 32 $address_block
    set_property usage register $address_block
}

# IP Packager와 Vitis에서 Register 이름과 Offset을 확인할 수 있게 기록한다.
set register_specs {
    CTRL         0x00 read-write
    STATUS       0x04 read-only
    OUTPUT_ADDR  0x08 read-write
    OUTPUT_DATA  0x0C read-only
    CYCLE_COUNT  0x10 read-only
    LAYER_DEBUG  0x14 read-only
    RESERVED     0x18 read-only
    VERSION      0x1C read-only
    TILE_POS     0x20 read-write
}

if {[llength [ipx::get_registers -quiet -of_objects $address_block]] == 0} {
    foreach {register_name register_offset register_access} $register_specs {
        set register_object [ipx::add_register $register_name $address_block]
        set_property address_offset $register_offset $register_object
        set_property size 32 $register_object
        set_property access $register_access $register_object
    }
}

ipx::create_xgui_files $core
ipx::update_checksums $core

set integrity_result [ipx::check_integrity -quiet $core]
puts "IP_INTEGRITY_RESULT=$integrity_result"

ipx::save_core $core

# Weight/Bias ROM은 basename을 사용해 readmemh를 수행한다.
# 팀원 B의 Rev4 IP와 동일하게 두 초기화 파일을 Packaged IP의
# RTL Source 디렉터리에 함께 배치한다.
set packaged_mem_init_dir [file join $ip_root src]
file mkdir $packaged_mem_init_dir

foreach mem_init_file [list \
    [file join $repo_root rtl mem_init srcnn_weights_all.hex] \
    [file join $repo_root rtl mem_init srcnn_biases_all.hex]] {

    set packaged_mem_init_file \
        [file join $packaged_mem_init_dir [file tail $mem_init_file]]

    file copy -force $mem_init_file $packaged_mem_init_file
    puts "PACKAGED_MEM_INIT_FILE=$packaged_mem_init_file"
}

set_property ip_repo_paths [list $ip_repo_dir] [current_fileset]
update_ip_catalog -rebuild

set packaged_ip [get_ipdefs -all -quiet user.org:user:AXI4_SRCNN_NPU:1.0]
if {[llength $packaged_ip] == 0} {
    srcnn_fail "Packaged IP가 IP Catalog에서 검색되지 않습니다."
}

puts "PACKAGED_IP=$packaged_ip"
puts "PACKAGED_INTERFACES=[lsort [get_property NAME [ipx::get_bus_interfaces -of_objects $core]]]"
puts "COMPONENT_XML=[get_property XML_FILE_NAME $core]"
puts "IP_PACKAGE=PASS"

close_project
exit 0
