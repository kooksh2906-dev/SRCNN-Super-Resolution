# SRCNN Fixed-Parameter Top Post-Route Timing Script
#
# 사용 방법:
# vivado -mode batch -nojournal -nolog \
#     -source scripts/run_srcnn_fixed_top_timing.tcl \
#     -tclargs <repository_path> ?<output_directory>?

if {($argc < 1) || ($argc > 2)} {
    error "Usage: run_srcnn_fixed_top_timing.tcl <repository_path> ?<output_directory>?"
}

set repo_dir [file normalize [lindex $argv 0]]
set part_name "xc7z020clg400-1"
set top_name "srcnn_npu_fixed_top"

if {$argc == 2} {
    set output_dir [file normalize [lindex $argv 1]]
} else {
    set output_dir "/tmp/srcnn_fixed_top_impl"
}

set project_dir    "$output_dir/project"
set constraint_xdc "$output_dir/srcnn_fixed_top_ooc.xdc"

set weight_init_file \
    "$repo_dir/rtl/mem_init/srcnn_weights_all.hex"

set bias_init_file \
    "$repo_dir/rtl/mem_init/srcnn_biases_all.hex"

# Repository와 초기화 파일 확인
if {![file isdirectory "$repo_dir/rtl/a_control_numeric_soc"]} {
    error "A-part RTL directory not found"
}

if {![file isdirectory "$repo_dir/rtl/b_compute_core"]} {
    error "B-part RTL directory not found"
}

if {![file isfile $weight_init_file]} {
    error "Weight initialization file not found: $weight_init_file"
}

if {![file isfile $bias_init_file]} {
    error "Bias initialization file not found: $bias_init_file"
}

file mkdir $output_dir

# Zybo Z7-20의 Zynq-7020 Part 확인
if {[llength [get_parts -quiet $part_name]] == 0} {
    error "Required device part not found: $part_name"
}

# Fixed-ROM Top 구현 전용 Project
create_project srcnn_fixed_top_impl \
    $project_dir \
    -part $part_name \
    -force

# 합성 가능한 A/B RTL 추가
set rtl_files [concat \
    [glob -nocomplain "$repo_dir/rtl/a_control_numeric_soc/*.v"] \
    [glob -nocomplain "$repo_dir/rtl/b_compute_core/*.v"] \
]

if {[llength $rtl_files] == 0} {
    error "No Verilog RTL files found"
}

add_files \
    -fileset sources_1 \
    -norecurse \
    $rtl_files

# $readmemh 초기화 파일을 Vivado Project에 명시적으로 등록
set memory_files [list \
    $weight_init_file \
    $bias_init_file \
]

add_files \
    -fileset sources_1 \
    -norecurse \
    $memory_files

set_property file_type \
    {Memory Initialization Files} \
    [get_files $memory_files]

# 합성 전 100MHz Clock 제약 등록
set xdc_fp [open $constraint_xdc "w"]
puts $xdc_fp {create_clock -name clk -period 10.000 [get_ports clk]}
close $xdc_fp

add_files \
    -fileset constrs_1 \
    -norecurse \
    $constraint_xdc

set_property top $top_name [current_fileset]

update_compile_order -fileset sources_1

puts "========================================"
puts "Starting Fixed-ROM NPU Synthesis"
puts "Top    : $top_name"
puts "Part   : $part_name"
puts "Clock  : 100 MHz"
puts "========================================"

# Out-of-Context 합성
synth_design \
    -top $top_name \
    -part $part_name \
    -mode out_of_context \
    -flatten_hierarchy rebuilt

if {[llength [get_clocks -quiet clk]] == 0} {
    error "Clock constraint was not applied"
}

# 합성 결과 저장
write_checkpoint \
    -force \
    "$output_dir/srcnn_fixed_top_post_synth.dcp"

report_utilization \
    -file "$output_dir/utilization_post_synth.rpt"

report_utilization \
    -hierarchical \
    -hierarchical_depth 5 \
    -file "$output_dir/utilization_hierarchical_post_synth.rpt"

report_timing_summary \
    -delay_type min_max \
    -max_paths 20 \
    -report_unconstrained \
    -file "$output_dir/timing_post_synth.rpt"

check_timing \
    -verbose \
    -file "$output_dir/check_timing_post_synth.rpt"

puts "========================================"
puts "Starting Logic Optimization"
puts "========================================"

opt_design

puts "========================================"
puts "Starting Placement"
puts "========================================"

place_design

# 배치 후 물리 최적화
phys_opt_design

write_checkpoint \
    -force \
    "$output_dir/srcnn_fixed_top_post_place.dcp"

report_timing_summary \
    -delay_type min_max \
    -max_paths 20 \
    -report_unconstrained \
    -file "$output_dir/timing_post_place.rpt"

puts "========================================"
puts "Starting Routing"
puts "========================================"

route_design

# 최종 배선 후 최악 Setup 경로를 추가로 최적화
phys_opt_design \
    -directive AggressiveExplore

write_checkpoint \
    -force \
    "$output_dir/srcnn_fixed_top_post_route.dcp"

# 최종 Post-route 자원 사용량
report_utilization \
    -file "$output_dir/utilization_post_route.rpt"

report_utilization \
    -hierarchical \
    -hierarchical_depth 5 \
    -file "$output_dir/utilization_hierarchical_post_route.rpt"

# Setup과 Hold를 모두 포함한 최종 Timing Summary
report_timing_summary \
    -delay_type min_max \
    -max_paths 20 \
    -report_unconstrained \
    -file "$output_dir/timing_post_route.rpt"

# 최악 Setup 경로 상세 정보
report_timing \
    -delay_type max \
    -max_paths 10 \
    -path_type full_clock_expanded \
    -file "$output_dir/worst_setup_paths.rpt"

# 최악 Hold 경로 상세 정보
report_timing \
    -delay_type min \
    -max_paths 10 \
    -path_type full_clock_expanded \
    -file "$output_dir/worst_hold_paths.rpt"

report_route_status \
    -file "$output_dir/route_status.rpt"

report_clock_utilization \
    -file "$output_dir/clock_utilization.rpt"

check_timing \
    -verbose \
    -file "$output_dir/check_timing_post_route.rpt"

report_drc \
    -file "$output_dir/drc_post_route.rpt"

report_methodology \
    -file "$output_dir/methodology_post_route.rpt"

# Tcl Console에도 최종 최악 Slack 출력
set worst_setup_path [
    get_timing_paths \
        -delay_type max \
        -max_paths 1
]

set worst_hold_path [
    get_timing_paths \
        -delay_type min \
        -max_paths 1
]

set setup_wns [get_property SLACK $worst_setup_path]
set hold_whs  [get_property SLACK $worst_hold_path]

puts "========================================"
puts "SRCNN Fixed-ROM Post-Route Completed"
puts "Top       : $top_name"
puts "Part      : $part_name"
puts "Clock     : 100 MHz"
puts "Setup WNS : $setup_wns ns"
puts "Hold WHS  : $hold_whs ns"
puts "Reports   : $output_dir"

if {$setup_wns >= 0.0} {
    puts {[PASS] Setup Timing constraints are met}
} else {
    puts {[FAIL] Setup Timing violation detected}
}

if {$hold_whs >= 0.0} {
    puts {[PASS] Hold Timing constraints are met}
} else {
    puts {[FAIL] Hold Timing violation detected}
}

puts "========================================"

exit
