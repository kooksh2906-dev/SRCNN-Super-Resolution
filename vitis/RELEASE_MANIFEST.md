# SRCNN Vitis Final Release

이 디렉터리는 최종 실보드 검증에 사용된 Vitis 펌웨어, 재생성 스크립트와
실행 산출물을 보존한다.

## 포함 항목

- `firmware/src`: 최종 Bare-metal Application 소스 9개
- `scripts/create_platform.py`: Vitis Platform 재생성
- `scripts/create_application.py`: 최종 Application 재생성
- `scripts/verify_release.py`: 전체 Release 무결성 검사
- `scripts/probe_targets.py`: hw_server 및 JTAG Target 확인
- `tools/srcnn_uart_client.py`: SRQ1/SRS1 UART 진단 도구
- `output/srcnn_team_a_final.elf`: 최종 Application
- `output/fsbl.elf`: 최종 FSBL
- `docs/board_validation.md`: 실보드 검증 결과

## Generated Platform 제외 사유

Exported Platform은 `hw/`와 `sw/`를 상대 참조하는 20MB 규모의 생성물이며
BSP 파일에 기존 Workspace 절대경로가 포함된다. 따라서 XPFM 단독 파일과
Generated BSP는 Git에 포함하지 않는다.

Platform은 `vivado/output/SRCNN_NPU_wrapper.xsa`와
`scripts/create_platform.py`로 재생성한다.

실보드 검증에 사용한 XPFM SHA-256:

`efe1184b60f6438e733fc909a95703ad6cba881bd47b0ff0e33167c8942c717c`

## 최종 계약

- NPU VERSION: `0x00010001`
- TILE_POS: `0x20`
- UART Request: SRQ1, 2068 Byte
- UART Response: SRS1, 540 Byte
- 정상 NPU Status: `0x00000002`
- 완료 방식: DONE polling
