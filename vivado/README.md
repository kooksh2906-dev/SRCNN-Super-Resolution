# Vivado Hardware

- `scripts/package_srcnn_npu_axi_ip.tcl`: Final AXI NPU IP packaging
- `project/SRCNN_NPU.bd`: Final Block Design source
- `project/SRCNN_NPU_bd.tcl`: Portable Block Design recreation Tcl
- `constraints/Zybo-Z7-Master.xdc`: Zybo Z7-20 constraints
- `output/SRCNN_NPU_wrapper.bit`: Board-tested bitstream
- `output/SRCNN_NPU_wrapper.xsa`: Board-tested hardware handoff

Generated Vivado cache, runs, and project workspace files are intentionally excluded.

## Final Vivado GUI Project

- XPR: `project/SRCNN_NPU_SOC/SRCNN_NPU_SOC.xpr`
- Vivado: 2024.2
- Board: Zybo Z7-20
- Custom IP Repository: `project/ip_repo/AXI4_SRCNN_NPU_1_0`

프로젝트는 XPR, Source Set, 필요한 Generated Block Design 파일 및 Custom IP를 포함한다.
`.cache`, `.runs`, `.hw`, `.sim`, `.Xil`은 포함하지 않는다.
최종 실보드 BIT/XSA는 `output/`의 검증된 파일을 사용한다.
