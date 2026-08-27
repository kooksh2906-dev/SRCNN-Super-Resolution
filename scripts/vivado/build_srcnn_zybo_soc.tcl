#------------------------------------------------------------------------------
# SRCNN NPU Zybo Z7-20 Full SoC Build Script
#
# Input project:
#   /tmp/srcnn_zybo_soc/vivado_project/srcnn_zybo_soc.xpr
#
# Synthesis top:
#   srcnn_soc_bd_wrapper
#
# Build scope:
#   Zynq-7000 PS + AXI interconnect + SRCNN NPU AXI IP
#   + AXI BRAM controllers + input/output BRAM + reset + interrupt
#
# Outputs:
#   /tmp/srcnn_zybo_soc/artifacts/srcnn_soc_bd_wrapper.bit
#   /tmp/srcnn_zybo_soc/artifacts/srcnn_zybo_soc.xsa
#   /tmp/srcnn_zybo_soc/reports/full_soc_build/*.rpt
#------------------------------------------------------------------------------

set soc_root     [file normalize /tmp/srcnn_zybo_soc]
set board_repo_dir [file join $soc_root board_repo]
set project_dir  [file join $soc_root vivado_project]
set project_name srcnn_zybo_soc
set project_file [file join $project_dir ${project_name}.xpr]
set design_name  srcnn_soc_bd
set top_name     ${design_name}_wrapper
set report_dir   [file join $soc_root reports full_soc_build]
set artifact_dir [file join $soc_root artifacts]
set jobs         4

proc srcnn_fail {message} {
    puts "BUILD_RESULT=FAIL"
    puts "ERROR: $message"
    return -code error $message
}

proc srcnn_run_ok {run_name expected_step} {
    set run_object [get_runs -quiet $run_name]
    if {[llength $run_object] == 0} {
        srcnn_fail "Vivado Run을 찾을 수 없습니다: $run_name"
    }

    set run_status   [get_property STATUS $run_object]
    set run_progress [get_property PROGRESS $run_object]

    puts "${run_name}_STATUS=$run_status"
    puts "${run_name}_PROGRESS=$run_progress"

    if {![string match "*Complete*" $run_status]} {
        srcnn_fail "$run_name 실패: $run_status"
    }

    if {$run_progress ne "100%"} {
        srcnn_fail "$run_name 진행률이 100%가 아닙니다: $run_progress"
    }

    if {$expected_step ne "" && ![string match "*$expected_step*" $run_status]} {
        srcnn_fail "$run_name 최종 단계가 $expected_step가 아닙니다: $run_status"
    }
}

proc srcnn_get_run_stat {run_object property_name} {
    if {[catch {get_property $property_name $run_object} property_value]} {
        return "N/A"
    }
    if {$property_value eq ""} {
        return "N/A"
    }
    return $property_value
}

puts "VIVADO_VERSION=[version -short]"
puts "PROJECT_FILE=$project_file"
puts "EXPECTED_TOP=$top_name"

if {![file exists $project_file]} {
    srcnn_fail "Vivado Project가 없습니다. BD 생성 단계를 먼저 완료하십시오: $project_file"
}

file mkdir $report_dir
file mkdir $artifact_dir

if {[file isdirectory $board_repo_dir]} {
    set_param board.repoPaths [list $board_repo_dir]
}

open_project $project_file

set actual_part [get_property PART [current_project]]
set actual_top  [get_property TOP [current_fileset]]

puts "PROJECT_PART=$actual_part"
puts "PROJECT_TOP=$actual_top"

if {$actual_part ne "xc7z020clg400-1"} {
    srcnn_fail "Target Part가 Zybo Z7-20의 xc7z020clg400-1이 아닙니다: $actual_part"
}

if {$actual_top ne $top_name} {
    srcnn_fail "합성 Top이 전체 SoC Wrapper가 아닙니다: $actual_top"
}

set bd_file [get_files -quiet */${design_name}.bd]
if {[llength $bd_file] != 1} {
    srcnn_fail "Block Design 파일을 정확히 하나 찾지 못했습니다: $design_name.bd"
}

open_bd_design [lindex $bd_file 0]
validate_bd_design
save_bd_design
generate_target all $bd_file
update_compile_order -fileset sources_1

report_ip_status \
    -file [file join $report_dir prebuild_ip_status.rpt]

# /tmp에 생성한 Project이므로 매 실행을 Clean Build로 시작한다.
reset_run synth_1

puts "SYNTHESIS_BEGIN=1"
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
srcnn_run_ok synth_1 synth_design
puts "SYNTHESIS_PASS=1"

puts "IMPLEMENTATION_BEGIN=1"
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
srcnn_run_ok impl_1 write_bitstream
puts "IMPLEMENTATION_PASS=1"

open_run impl_1

report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 20 \
    -file [file join $report_dir post_route_timing_summary.rpt]

report_utilization \
    -hierarchical \
    -file [file join $report_dir post_route_utilization.rpt]

report_power \
    -file [file join $report_dir post_route_power.rpt]

report_drc \
    -file [file join $report_dir post_route_drc.rpt]

report_route_status \
    -file [file join $report_dir post_route_status.rpt]

report_clock_utilization \
    -file [file join $report_dir post_route_clock_utilization.rpt]

write_checkpoint \
    -force \
    [file join $artifact_dir ${top_name}_post_route.dcp]

set bit_source [file join \
    $project_dir \
    ${project_name}.runs \
    impl_1 \
    ${top_name}.bit]

set bit_target [file join $artifact_dir ${top_name}.bit]
set xsa_target [file join $artifact_dir ${project_name}.xsa]

if {![file exists $bit_source]} {
    srcnn_fail "전체 SoC Bitstream이 생성되지 않았습니다: $bit_source"
}

file copy -force $bit_source $bit_target

write_hw_platform \
    -fixed \
    -include_bit \
    -force \
    $xsa_target

if {![file exists $bit_target]} {
    srcnn_fail "Bitstream 산출물 복사 실패: $bit_target"
}

if {![file exists $xsa_target]} {
    srcnn_fail "XSA 생성 실패: $xsa_target"
}

set impl_run [get_runs impl_1]
set timing_wns [srcnn_get_run_stat $impl_run STATS.WNS]
set timing_tns [srcnn_get_run_stat $impl_run STATS.TNS]
set timing_whs [srcnn_get_run_stat $impl_run STATS.WHS]
set timing_ths [srcnn_get_run_stat $impl_run STATS.THS]

puts "TIMING_WNS=$timing_wns"
puts "TIMING_TNS=$timing_tns"
puts "TIMING_WHS=$timing_whs"
puts "TIMING_THS=$timing_ths"
puts "BITSTREAM_FILE=$bit_target"
puts "XSA_FILE=$xsa_target"
puts "REPORT_DIR=$report_dir"

set timing_pass 1
if {$timing_wns ne "N/A" && [string is double -strict $timing_wns]} {
    if {$timing_wns < 0.0} {
        set timing_pass 0
    }
}
if {$timing_whs ne "N/A" && [string is double -strict $timing_whs]} {
    if {$timing_whs < 0.0} {
        set timing_pass 0
    }
}

if {!$timing_pass} {
    puts "TIMING_MET=FAIL"
    srcnn_fail "Implementation은 완료됐지만 Timing을 만족하지 못했습니다. Timing Report를 확인하십시오."
}

puts "TIMING_MET=PASS"
puts "FULL_SOC_TOP=$top_name"
puts "BUILD_RESULT=PASS"

close_project
exit 0
