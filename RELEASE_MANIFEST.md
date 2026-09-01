# SRCNN NPU Final Release Manifest

- Release 정리일: 2026-08-29
- 최종 실보드 검증일: 2026-08-28
- Board: Zybo Z7-20 / XC7Z020CLG400-1
- Toolchain: Vivado/Vitis 2024.2
- Release 구성: RTL, Vivado, Vitis, Python, Testbench, Spec 및 재현 Script

## 구성 Commit

| 구성 | Commit | 내용 |
|---|---|---|
| RTL | `0cdbf20c3229eebd38da54121531f3ed07b89ab0` | Boundary-aware 최종 SRCNN NPU RTL |
| Vivado | `07c7fabe969710d72e0829f98df12d2ee8250684` | 최종 SoC Project와 BIT/XSA |
| Vitis | `286518e1e6457630b94d3f019bc61031b38dc8ea` | 최종 Firmware, ELF/FSBL 및 Release 검증 |
| Python | `f3c353fc99022817fc00242bee9cff913b68492f` | 최종 PC UART Host, INT16 Golden 및 Web UI |

## 최종 디렉터리

| 경로 | Release 역할 |
|---|---|
| `rtl/` | 합성 가능한 최종 NPU RTL과 Parameter Memory |
| `tb/` | RTL Testbench와 Golden Vector |
| `vivado/` | 실보드에 사용한 Block Design, BIT 및 XSA |
| `vitis/` | 실보드에 사용한 Firmware Source, ELF 및 FSBL |
| `python/` | PC 전처리·후처리, UART Host, Mock, Web UI 및 Test |
| `spec/` | 수치·RTL·AXI·UART 최종 계약 |
| `scripts/` | Memory 생성, 합성 및 Timing 검증 Script |

## 고정 산출물 SHA-256

| 산출물 | SHA-256 |
|---|---|
| `vivado/output/SRCNN_NPU_wrapper.bit` | `2b84f0a11c8292763724d8222ff261bd059acc14b567ad9009ad7063791adc38` |
| `vivado/output/SRCNN_NPU_wrapper.xsa` | `701064a853a2f3027ceb7d02df8f0dbdef6e732a0f29d3b0e109d11ed34eeb2f` |
| `vitis/output/srcnn_team_a_final.elf` | `bcd84c278759cb78de60d26663995bd35570e7fbd26e8aa1a4944bb23becdaee` |
| `vitis/output/fsbl.elf` | `235717926f324ab7c2cd6e13a7afdac17dd45a747f93da6f8bd5d6a5e41b142c` |
| 전체 병합 INT16 실보드 결과 | `dc45b579efeb4c1063ee44d2d33d9df84a5ad6043d442c54d437b7307aa9cd74` |

XSA 내장 Bitstream과 외부 BIT는 byte-identical이다.

## 최종 시스템 계약

| 항목 | 값 |
|---|---|
| NPU VERSION | `0x00010001` |
| Input BRAM | `0x40000000` |
| NPU AXI4-Lite | `0x43C00000` |
| TILE_POS | Offset `0x20` |
| UART | PS UART1, 115200 baud, 8N1 |
| Request | `SRQ1`, Header 20 Byte, 정상 총 2,068 Byte |
| Response | `SRS1`, Header 28 Byte, 정상 총 540 Byte |
| CRC32 | Payload만 계산하여 Header에 저장 |
| 완료 방식 | DONE Polling |
| 정상 NPU Status | `0x00000002` |

## 검증 결과

| 검증 | 결과 |
|---|---|
| Fixed Parameter/Layer/Full RTL Golden | PASS |
| Global Boundary Mask RTL Simulation | PASS |
| Vitis Release Integrity | PASS |
| Python 전체 회귀 테스트 | 48 tests PASS |
| Mock 대표 Tile 0/17/255 | mismatch 0, Max Error 0 LSB |
| Mock 전체 256 Tile | mismatch 0, Retry 0 |
| 실보드 대표 Tile 0/17/255 | mismatch 0, Max Error 0 LSB |
| 실보드 전체 256 Tile | mismatch 0, Retry 0 |
| 병합 256×256 출력 | Python INT16 Golden과 byte-identical |
| 최종 영상 Tile Seam | 없음 |

실보드 전체 256 Tile 전송량은 TX 529,408 Byte, RX 138,240 Byte이며 총 PL Cycle은 7,894,995,712이다.

## Release 무결성 확인

```bash
python3 vitis/scripts/verify_release.py
cd python
.venv/bin/python -m unittest discover -s . -p "test_*.py"
```

저장소 전체 파일 무결성은 최상위 `SHA256SUMS`로 확인한다. `SHA256SUMS` 자체와 Git Metadata는 Manifest 대상에서 제외한다.

## 포함하지 않는 항목

- 이전 Protocol과 이전 RTL/Vivado/Vitis 산출물
- Output BRAM 및 PL Interrupt 기반 비채택 SoC 변형
- Vivado/Vitis 자동 생성 Workspace와 Cache
- Python 가상환경, Cache, Log 및 UART 실행 결과 폴더
- 실패 Backup, 임시 파일, 발표 영상 및 개발 과정의 외부 아카이브

이 저장소의 기본 파일명은 실보드에서 최종 검증한 파일을 의미한다. 이전 버전과 조사 근거는 별도 외부 아카이브로 보존하며 Release에는 포함하지 않는다.

## Vivado GUI Project Snapshot

- XPR: `vivado/project/SRCNN_NPU_SOC/SRCNN_NPU_SOC.xpr`
- Vivado Version: 2024.2
- Block Design 및 `AXI4_SRCNN_NPU:1.0` 검증: PASS
- Global Boundary Mask 포함 확인: PASS
- 최종 Implementation BIT와 Release BIT byte-identical: PASS
