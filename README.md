# SRCNN Super-Resolution NPU

Zybo Z7-20에서 동작하는 SRCNN x2 9-5-5 INT16 Super-Resolution NPU의 최종 RTL, Vivado SoC, Vitis Firmware, PC Python Host 및 검증 자료를 통합한 저장소이다.

## 최종 구현 상태

- Board: Zybo Z7-20 / XC7Z020CLG400-1
- PL Clock: 100 MHz
- Model: SRCNN x2 9-5-5
- Arithmetic: signed INT16 Activation/Weight, signed INT48 Accumulator
- Processing: 32×32 Halo Tile 입력, 중앙 16×16 출력, 총 256 Tile
- Interface: AXI4-Lite, Input BRAM, PS UART1 115200 baud
- Completion: DONE Polling
- UART: `SRQ1` Request / `SRS1` Response
- NPU VERSION: `0x00010001`
- 정상 NPU Status: `0x00000002`

대표 경계·내부 타일과 전체 256타일 실보드 검증에서 Python INT16 Golden과 정확히 일치했다.

## 저장소 구성

| 경로 | 내용 |
|---|---|
| `rtl/` | 최종 SRCNN NPU RTL, AXI Wrapper 및 고정 Weight/Bias Memory |
| `tb/` | Unit, Layer, Full NPU 검증 Testbench와 Golden Vector |
| `vivado/` | 최종 Block Design, Constraint, IP Packaging 및 실보드 BIT/XSA |
| `vitis/` | 최종 Bare-metal Firmware, 재생성 Script, ELF/FSBL 및 검증 문서 |
| `python/` | 전처리, INT16 Golden, UART Host, Web UI, 데이터 및 Python Test |
| `spec/` | 최종 수치, RTL 연결, AXI Register 및 UART 계약 |
| `scripts/` | Parameter Memory 생성, OOC 합성 및 Timing 검증 Script |

개발 과정의 이전 버전과 비정규 산출물은 최종 저장소에 포함하지 않는다. Git의 기본 파일명은 실제 실보드 검증에 사용한 최종 파일을 의미한다.

## 최종 하드웨어 산출물

| 파일 | SHA-256 |
|---|---|
| `vivado/output/SRCNN_NPU_wrapper.bit` | `2b84f0a11c8292763724d8222ff261bd059acc14b567ad9009ad7063791adc38` |
| `vivado/output/SRCNN_NPU_wrapper.xsa` | `701064a853a2f3027ceb7d02df8f0dbdef6e732a0f29d3b0e109d11ed34eeb2f` |
| `vitis/output/srcnn_team_a_final.elf` | `bcd84c278759cb78de60d26663995bd35570e7fbd26e8aa1a4944bb23becdaee` |
| `vitis/output/fsbl.elf` | `235717926f324ab7c2cd6e13a7afdac17dd45a747f93da6f8bd5d6a5e41b142c` |

XSA에 내장된 Bitstream과 외부 BIT는 byte-identical이다.

## 주요 계약

### Tile과 Global Boundary

```text
tile_id = tile_y * 16 + tile_x
tile_x  = tile_id % 16
tile_y  = tile_id // 16

global_x = tile_x * 16 - 8 + local_x
global_y = tile_y * 16 - 8 + local_y
```

Conv1/Conv2 Requantization과 ReLU 이후 전체 256×256 영상 밖의 Feature를 0으로 만드는 Global Boundary Mask를 적용한다.

### AXI 주소

| 항목 | 값 |
|---|---|
| Input BRAM | `0x40000000` |
| NPU AXI4-Lite | `0x43C00000` |
| VERSION Offset | `0x1C` |
| TILE_POS Offset | `0x20` |

상세 계약은 `spec/contract.md`, `spec/register_map.md`, `spec/uart_protocol.md`, `spec/quant_spec.json`을 따른다.

## Release 무결성 검사

저장소 최상위에서 실행한다.

```bash
python3 vitis/scripts/verify_release.py
```

BIT, XSA, ELF, FSBL SHA-256, XSA 내장 BIT, 주소 맵, NPU VERSION, TILE_POS 및 UART 계약이 모두 PASS여야 한다.

## Python 환경 및 회귀 테스트

```bash
cd python
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m unittest discover -s . -p "test_*.py"
```

최종 기준은 48 tests PASS이다.

대표 타일 Mock 검증:

```bash
.venv/bin/python uart_single_tile_test.py --mock --tile-id 0 --output-dir /tmp/srcnn_tile_000
.venv/bin/python uart_single_tile_test.py --mock --tile-id 17 --output-dir /tmp/srcnn_tile_017
.venv/bin/python uart_single_tile_test.py --mock --tile-id 255 --output-dir /tmp/srcnn_tile_255
```

전체 256타일 Mock 검증:

```bash
.venv/bin/python uart_host.py --mock --output-dir /tmp/srcnn_uart_full_mock
```

## 실보드 실행 순서

1. `vivado/output/SRCNN_NPU_wrapper.bit`로 PL Programming
2. `vitis/output/fsbl.elf`와 `vitis/output/srcnn_team_a_final.elf` 실행
3. UART Port와 NPU VERSION 확인
4. Python 단일 타일 실보드 검증
5. Python 전체 256타일 실보드 검증
6. Python Web UI 시연

세부 명령과 합격 기준은 다음 문서를 참조한다.

- `vitis/README.md`
- `vitis/docs/board_validation.md`
- `python/docs/UART_HOST_README.md`
- `python/CODEX_HANDOFF.md`

## 최종 검증 결과

| 검증 | 결과 |
|---|---|
| Global Boundary Mask RTL Simulation | PASS |
| Python 전체 회귀 테스트 | 48 tests PASS |
| 실보드 Tile 0, 17, 255 | mismatch `0/256`, Max Error `0 LSB` |
| 실보드 전체 256 Tile | Mismatch Tile `0`, Retry `0` |
| 병합 256×256 결과 | Python INT16 Golden과 byte-identical |
| 최종 영상 Tile Seam | 없음 |

최종 실보드 검증 기록은 `vitis/docs/board_validation.md`에 보존한다.

## Vivado GUI 프로젝트

Vivado 2024.2에서 다음 XPR을 열어 최종 Zybo Z7-20 Block Design과 Custom IP를 확인할 수 있다.

- `vivado/project/SRCNN_NPU_SOC/SRCNN_NPU_SOC.xpr`
- Board: `digilentinc.com:zybo-z7-20:part0:1.1`
- Part: `xc7z020clg400-1`
- Custom IP: `user.org:user:AXI4_SRCNN_NPU:1.0`

Vivado 실행 Cache와 Runs는 포함하지 않으며 최종 BIT/XSA는 `vivado/output/`에 보존한다.
