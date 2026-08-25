# =============================================================================
# SRCNN NPU 4-Stage Requant Pipeline
# 100MHz Out-of-Context Post-Route Timing Verification
# Target: Zybo Z7-20 / XC7Z020-1CLG400
# =============================================================================

# 현재 이 스크립트는 Repository 최상위 경로에서 실행해야 함
set repo_dir  [file normalize [pwd]]
set run_dir   "/tmp/srcnn_four_stage_timing_opt_impl"
set part_name "xc7z020clg400-1"

puts "============================================================"
puts "SRCNN Four-Stage Timing Verification"
puts "Repository : $repo_dir"
puts "Run Dir    : $run_dir"
puts "Part       : $part_name"
puts "Clock      : 100MHz / 10.000ns"
puts "============================================================"

# -----------------------------------------------------------------------------
# 1. 임시 Vivado Project 생성
# -----------------------------------------------------------------------------

file mkdir $run_dir

create_project -force \
    srcnn_four_stage_timing_opt \
    $run_dir \
    -part $part_name

set_property target_language Verilog [current_project]

# -----------------------------------------------------------------------------
# 2. SRCNN RTL Source 추가
# -----------------------------------------------------------------------------

set a_rtl_files [glob -nocomplain \
    "$repo_dir/rtl/a_control_numeric_soc/*.v"]

set b_rtl_files [glob -nocomplain \
    "$repo_dir/rtl/b_compute_core/*.v"]

# 경로 오류로 빈 합성이 진행되지 않도록 검사
if {[llength $a_rtl_files] == 0} {
    error "A-part RTL files were not found."
}

if {[llength $b_rtl_files] == 0} {
    error "B-part RTL files were not found."
}

add_files -norecurse $a_rtl_files
add_files -norecurse $b_rtl_files

set_property top srcnn_npu_top [current_fileset]
update_compile_order -fileset sources_1

# -----------------------------------------------------------------------------
# 3. 합성 전 100MHz Clock Constraint 등록
#
# 합성 단계부터 10ns Clock 목표를 인식하도록 임시 XDC를 생성함.
# srcnn_npu_top은 내부 NPU Core이므로 실제 FPGA Pin Constraint는 적용하지 않음.
# -----------------------------------------------------------------------------

set xdc_file "$run_dir/srcnn_100mhz_ooc.xdc"
set xdc_fp [open $xdc_file "w"]

puts $xdc_fp {
create_clock -name clk -period 10.000 [get_ports clk]
}

close $xdc_fp

add_files -fileset constrs_1 -norecurse $xdc_file
update_compile_order -fileset sources_1

# -----------------------------------------------------------------------------
# 4. Out-of-Context 합성
#
# srcnn_npu_top의 BRAM Data/Address Port를 실제 FPGA IO Pin으로 배치하지 않고
# 내부 NPU Core 자체의 Timing 및 자원 사용량을 검증함.
# -----------------------------------------------------------------------------

puts "============================================================"
puts "Step 1: Out-of-Context Synthesis"
puts "============================================================"

synth_design \
    -top srcnn_npu_top \
    -part $part_name \
    -mode out_of_context

write_checkpoint -force \
    "$run_dir/srcnn_four_stage_post_synth.dcp"

report_utilization \
    -file "$run_dir/utilization_post_synth.rpt"

report_timing_summary \
    -delay_type min_max \
    -max_paths 20 \
    -report_unconstrained \
    -file "$run_dir/timing_summary_post_synth.rpt"

# -----------------------------------------------------------------------------
# 5. Timing 중심 Logic Optimization
# -----------------------------------------------------------------------------

puts "============================================================"
puts "Step 2: Logic Optimization"
puts "============================================================"

opt_design -directive ExploreWithRemap

write_checkpoint -force \
    "$run_dir/srcnn_four_stage_post_opt.dcp"

# -----------------------------------------------------------------------------
# 6. Placement
# -----------------------------------------------------------------------------

puts "============================================================"
puts "Step 3: Placement"
puts "============================================================"

place_design -directive Explore

write_checkpoint -force \
    "$run_dir/srcnn_four_stage_post_place.dcp"

report_timing_summary \
    -delay_type min_max \
    -max_paths 20 \
    -report_unconstrained \
    -file "$run_dir/timing_summary_post_place.rpt"

# -----------------------------------------------------------------------------
# 7. Pre-Route Physical Optimization
#
# 복제, 재배치 및 배선 예상 지연 개선을 적극적으로 수행함.
# -----------------------------------------------------------------------------

puts "============================================================"
puts "Step 4: Pre-Route Physical Optimization"
puts "============================================================"

phys_opt_design -directive AggressiveExplore

write_checkpoint -force \
    "$run_dir/srcnn_four_stage_post_phys_opt.dcp"

# -----------------------------------------------------------------------------
# 8. Routing
# -----------------------------------------------------------------------------

puts "============================================================"
puts "Step 5: Aggressive Routing"
puts "============================================================"

route_design -directive AggressiveExplore

write_checkpoint -force \
    "$run_dir/srcnn_four_stage_post_route_before_phys_opt.dcp"

# -----------------------------------------------------------------------------
# 9. Post-Route Physical Optimization
#
# 실제 배선 후 남은 Setup/Hold 위반 경로를 다시 최적화함.
# -----------------------------------------------------------------------------

puts "============================================================"
puts "Step 6: Post-Route Physical Optimization"
puts "============================================================"

phys_opt_design -directive AggressiveExplore

# 최종 Routed Checkpoint 보존
write_checkpoint -force \
    "$run_dir/srcnn_four_stage_routed.dcp"

# -----------------------------------------------------------------------------
# 10. 최종 자원 및 Timing Report
# -----------------------------------------------------------------------------

puts "============================================================"
puts "Step 7: Final Reports"
puts "============================================================"

report_utilization \
    -file "$run_dir/utilization_post_route.rpt"

# Setup과 Hold를 모두 포함하는 종합 Timing Report
report_timing_summary \
    -delay_type min_max \
    -max_paths 20 \
    -report_unconstrained \
    -file "$run_dir/timing_summary_post_route.rpt"

# 최악 Setup 경로 20개
report_timing \
    -delay_type max \
    -max_paths 20 \
    -path_type full \
    -file "$run_dir/timing_setup_paths_post_route.rpt"

# 최악 Hold 경로 20개
report_timing \
    -delay_type min \
    -max_paths 20 \
    -path_type full \
    -file "$run_dir/timing_hold_paths_post_route.rpt"

# Clock 관련 검증
report_clock_utilization \
    -file "$run_dir/clock_utilization_post_route.rpt"

# Vivado 설계 방법론 및 잠재적 구조 문제 검사
report_methodology \
    -file "$run_dir/methodology_post_route.rpt"

# -----------------------------------------------------------------------------
# 11. Console에 최악 Setup/Hold Slack 출력
# -----------------------------------------------------------------------------

set worst_setup_path [get_timing_paths \
    -delay_type max \
    -max_paths 1 \
    -nworst 1]

set worst_hold_path [get_timing_paths \
    -delay_type min \
    -max_paths 1 \
    -nworst 1]

puts "============================================================"
puts "SRCNN Four-Stage Post-Route Timing Result"
puts "============================================================"

if {[llength $worst_setup_path] > 0} {
    puts "Worst Setup Slack = [get_property SLACK $worst_setup_path] ns"
} else {
    puts "Worst Setup Slack = No constrained setup path"
}

if {[llength $worst_hold_path] > 0} {
    puts "Worst Hold Slack  = [get_property SLACK $worst_hold_path] ns"
} else {
    puts "Worst Hold Slack  = No constrained hold path"
}

puts "------------------------------------------------------------"
puts "Timing Summary:"
puts "$run_dir/timing_summary_post_route.rpt"

puts "Setup Paths:"
puts "$run_dir/timing_setup_paths_post_route.rpt"

puts "Hold Paths:"
puts "$run_dir/timing_hold_paths_post_route.rpt"

puts "Utilization:"
puts "$run_dir/utilization_post_route.rpt"

puts "Routed Checkpoint:"
puts "$run_dir/srcnn_four_stage_routed.dcp"
puts "============================================================"
puts "SRCNN Four-Stage Timing Verification Completed"
puts "============================================================"
