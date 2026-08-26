# SRCNN NPU Out-of-Context Synthesis Script
#
# 사용 방법:
# vivado -mode batch -nojournal -nolog \
#     -source scripts/synth_srcnn_npu_top.tcl \
#     -tclargs <repository_path> ?<output_directory>?

# Repository 경로는 첫 번째 명령행 인수로 받음
if {($argc < 1) || ($argc > 2)} {
    error "Usage: synth_srcnn_npu_top.tcl <repository_path> ?<output_directory>?"
}

set repo_dir [file normalize [lindex $argv 0]]
set part_name "xc7z020clg400-1"

# 두 번째 인수가 없으면 기본 임시 출력 경로 사용
if {$argc == 2} {
    set output_dir [file normalize [lindex $argv 1]]
} else {
    set output_dir "/tmp/srcnn_npu_ooc"
}

set project_dir    "$output_dir/project"
set constraint_xdc "$output_dir/srcnn_npu_ooc.xdc"

# 입력 Repository 구조 확인
if {![file isdirectory "$repo_dir/rtl/a_control_numeric_soc"]} {
    error "A-part RTL directory not found: $repo_dir/rtl/a_control_numeric_soc"
}

if {![file isdirectory "$repo_dir/rtl/b_compute_core"]} {
    error "B-part RTL directory not found: $repo_dir/rtl/b_compute_core"
}

file mkdir $output_dir

# Zynq-7020 디바이스 설치 여부 확인
if {[llength [get_parts -quiet $part_name]] == 0} {
    error "Required device part not found: $part_name"
}

# 합성 전용 임시 Vivado Project 생성
create_project srcnn_npu_ooc \
    $project_dir \
    -part $part_name \
    -force

# A파트와 B파트의 합성 가능한 Verilog RTL 수집
set rtl_files [concat \
    [glob -nocomplain "$repo_dir/rtl/a_control_numeric_soc/*.v"] \
    [glob -nocomplain "$repo_dir/rtl/b_compute_core/*.v"] \
]

if {[llength $rtl_files] == 0} {
    error "No Verilog RTL files found"
}

add_files -norecurse $rtl_files

# 목표 PL Clock 100MHz 제약을 합성 전에 등록
set xdc_fp [open $constraint_xdc "w"]
puts $xdc_fp {create_clock -name clk -period 10.000 [get_ports clk]}
close $xdc_fp

add_files \
    -fileset constrs_1 \
    -norecurse \
    $constraint_xdc

set_property top srcnn_npu_top [current_fileset]

update_compile_order -fileset sources_1

# 외부 I/O 배치 없이 RTL 자원과 Timing을 확인하는 OOC 합성
synth_design \
    -top srcnn_npu_top \
    -part $part_name \
    -mode out_of_context \
    -flatten_hierarchy rebuilt

# Clock 제약이 실제 합성 결과에 적용되었는지 확인
if {[llength [get_clocks -quiet clk]] == 0} {
    error "Clock constraint was not applied to port clk"
}

# 합성 후 자원 사용량 리포트
report_utilization \
    -file "$output_dir/utilization.rpt"

report_utilization \
    -hierarchical \
    -hierarchical_depth 4 \
    -file "$output_dir/utilization_hierarchical.rpt"

# Setup과 Hold를 모두 포함한 합성 후 Timing 리포트
report_timing_summary \
    -delay_type min_max \
    -max_paths 10 \
    -report_unconstrained \
    -file "$output_dir/timing_summary.rpt"

# 누락되거나 잘못된 Timing 제약 확인
check_timing \
    -verbose \
    -file "$output_dir/check_timing.rpt"

report_drc \
    -file "$output_dir/drc.rpt"

# 이후 분석이나 구현 단계에서 재사용할 합성 Checkpoint
write_checkpoint \
    -force \
    "$output_dir/srcnn_npu_top_post_synth.dcp"

puts "========================================"
puts "SRCNN NPU Out-of-Context Synthesis Completed"
puts "Top     : srcnn_npu_top"
puts "Part    : $part_name"
puts "Clock   : 100 MHz"
puts "Reports : $output_dir"
puts "========================================"

exit
