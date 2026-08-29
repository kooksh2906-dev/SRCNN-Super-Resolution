# SRCNN NPU Final Hardware Contract

이 문서는 최종 SRCNN x2 9-5-5 INT16 NPU의 RTL, 수치 형식, Tile 처리 및 A/B 연결 계약을 정의한다.

## 기준 파일

계약 충돌 시 다음 실제 구현 파일을 우선한다.

- 수치 계약: `spec/quant_spec.json`
- NPU 연결: `rtl/a_control_numeric_soc/srcnn_npu_top.v`
- 경계 처리: `rtl/a_control_numeric_soc/global_boundary_mask.v`
- Compute Core: `rtl/b_compute_core/`
- AXI Register: `rtl/a_control_numeric_soc/AXI4_SRCNN_NPU_slave_lite_v1_0_S00_AXI.v`
- Firmware: `vitis/firmware/src/`
- PC UART Codec: `python/uart_protocol.py`

## Clock과 Reset

- 목표 PL Clock: 100 MHz
- AXI/NPU Clock: 동일한 `S_AXI_ACLK`
- 최종 Wrapper Reset: active-low `S_AXI_ARESETN`
- RTL 구현 언어: Verilog-2001

## 수치 형식

| 항목 | 형식 |
|---|---|
| Activation | signed INT16 |
| Weight | signed INT16 |
| Bias | signed INT32 |
| Product | signed INT32 |
| Accumulator | signed INT48 |
| Rounding | round-to-nearest, ties-away-from-zero |

B Compute Core는 Bias가 포함된 4개 PE의 signed INT48 Accumulator를 생성한다. A Control/Numeric 블록은 Requantization, Activation, Saturation 및 Feature Memory Write를 담당한다.

## Layer별 후처리

| Layer | Accumulator | Right Shift | Activation | 출력 |
|---|---|---:|---|---|
| Conv1 | F29 | 14 | ReLU | signed INT16 F15 |
| Conv2 | F30 | 16 | ReLU | signed INT16 F14 |
| Conv3 | F29 | 14 | Clamp `0..32767` | signed INT16 F15 |

음수 Rounding은 절댓값에 Half LSB를 더해 Shift한 후 부호를 복원한다.

## 주소 순서

```text
activation_addr = channel * 1024 + y * 32 + x
accumulator_addr = output_channel * 1024 + y * 32 + x
weight_addr = (((output_channel * input_channels) + input_channel)
               * kernel_height + kernel_y) * kernel_width + kernel_x
```

Weight에는 Kernel Flip을 적용하지 않는다. Packed PE4 Weight 순서는 다음과 같다.

```text
output_channel_group -> input_channel -> kernel_y -> kernel_x
```

64-bit Weight Word는 `[15:0]=PE0`, `[31:16]=PE1`, `[47:32]=PE2`, `[63:48]=PE3`이다.

## Tile과 Halo

- 전체 영상: 256×256
- Tile Grid: 16×16, 총 256개
- 입력 Tile: Halo를 포함한 32×32 signed INT16
- 유효 출력: 중앙 16×16 signed INT16
- Halo: 8 Pixel
- Tile 순서: row-major

```text
tile_id = tile_y * 16 + tile_x
tile_x  = tile_id % 16
tile_y  = tile_id // 16
```

## Global Boundary Mask

입력 Halo의 Zero Padding만으로는 Bias가 생성하는 영상 외부 Feature를 제거할 수 없다. 따라서 Conv1 및 Conv2의 Requantization/ReLU 출력에 Global Boundary Mask를 적용한다.

```text
global_x = tile_x * 16 - 8 + local_x
global_y = tile_y * 16 - 8 + local_y
valid = 0 <= global_x < 256 and 0 <= global_y < 256
```

`valid=0`인 Conv1/Conv2 Feature는 강제로 0으로 저장한다. Conv3 출력에는 별도 Boundary Mask를 적용하지 않는다.

## 실행 순서

1. PC가 tile_id에 대응하는 tile_x/tile_y와 32×32 Payload 전송
2. Firmware가 Payload CRC32 및 NPU VERSION 검사
3. Firmware가 TILE_POS `0x20` Write/Readback
4. Input BRAM에 1,024개 INT16 기록
5. CTRL CLEAR 후 START
6. STATUS DONE Polling
7. 중앙 16×16 출력과 Cycle Count 반환
8. PC가 Sequence, NPU Status 및 Golden 결과 검증

## 완료 기준

- NPU VERSION: `0x00010001`
- 정상 NPU Status: `0x00000002`
- Representative Tile 0/17/255: Golden exact
- 전체 256 Tile 누락·중복·Retry: 0
- 병합 256×256 결과: Python INT16 Golden과 byte-identical
- Global Boundary Mask RTL Simulation: PASS
- Python 전체 회귀 테스트: 48 tests PASS
