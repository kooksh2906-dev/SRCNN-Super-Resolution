# A 인수인계: Rev5 NPU 제어·후처리·SoC/Vitis

## 1. A의 책임 범위

- Layer Controller: Conv1 → Conv2 → Conv3
- Activation, Weight, Bias 주소 생성과 Zero Padding
- Feature BRAM 및 Ping-Pong 제어
- Requantization, ReLU, Saturation, Conv3 Clamp
- 전체 이미지 경계 Feature Mask
- AXI4-Lite, AXI BRAM, Vivado Block Design
- Vitis Rev5 UART Packet, TILE_POS 기록, NPU 실행, Center 16×16 반환

B의 책임은 Bias가 포함된 4×signed INT48 accumulator를 생성하는 데까지다.
A는 accumulator를 받아 아래 후처리를 수행한다.

## 2. 수치 계약

```text
Activation  : signed INT16
Weight      : signed INT16
Bias        : signed INT32
Product     : signed INT32
Accumulator : signed INT48

Conv1 : F29 accumulator → round/shift 14 → ReLU → signed INT16 F15
Conv2 : F30 accumulator → round/shift 16 → ReLU → signed INT16 F14
Conv3 : F29 accumulator → round/shift 14 → clamp 0..32767 → signed INT16 F15
```

Rounding은 round-to-nearest, ties-away-from-zero이다.

```text
half = 1 << (shift - 1)

value >= 0:
    rounded = (value + half) >>> shift

value < 0:
    rounded = -(((-value) + half) >>> shift)
```

HEX는 `0x` 없이 한 줄에 한 값이며 signed 값은 two's complement이다.

- INT16: 4자리
- INT32: 8자리
- INT48: 12자리
- PE4 Weight: 16자리 64-bit

## 3. 초기 개발 순서 및 완료 이력

아래 항목은 Rev5가 완성되기까지 수행한 기반 검증 순서다. 현재 Rev5 Vitis
갱신 작업에서 RTL, IP Packaging, Synthesis, Implementation 또는 Bitstream을
다시 수행하는 절차가 아니다.

1. `directed_requant`의 45개 Case로 round/shift/ReLU/clamp 단위 테스트
2. B의 accumulator 출력과 A Requantizer를 연결
3. `single_tile/rtl_data`의 Layer expected와 비교
4. Conv1 → Conv2 → Conv3 Controller 연결
5. 32×32 Full RTL `output_expected.hex` mismatch=0 확인
6. 이후 AXI/BRAM/Vitis 및 전체 이미지로 확장

## 4. Requant Directed Vector

각 HEX 파일의 같은 줄이 하나의 Case다.

```text
requant_accumulator.hex      signed INT48 입력
requant_shift.hex            14 또는 16
requant_mode.hex             1=ReLU, 2=Clamp 0..32767
requant_round_expected.hex   activation 전 raw rounder 결과
requant_output_expected.hex  최종 signed INT16 출력
```

`requant_cases.json/csv`에 Case 이름과 예상값이 있다.

## 5. Single Tile 주소 규칙

Activation과 accumulator는 NCHW C-order이다.

```text
activation_addr = channel * 1024 + y * 32 + x
accumulator_addr = output_channel * 1024 + y * 32 + x
```

Weight 원본은 OIHW이며 Kernel flip이 없다.

```text
weight_addr = (((oc * input_channels) + ic) * kernel_h + ky) * kernel_w + kx
```

Padding 판정은 A가 담당하고 범위 밖 Activation을 B에 0으로 공급한다.

## 6. PE4 Weight ROM 계약

Packed Weight 주소 순서:

```text
output_channel_group → input_channel → kernel_y → kernel_x
```

64-bit Word:

```text
[63:48] PE3 / oc_group*4+3
[47:32] PE2 / oc_group*4+2
[31:16] PE1 / oc_group*4+1
[15: 0] PE0 / oc_group*4+0
```

Conv3는 PE0만 사용하며 PE1~PE3 Weight는 0이다.

## 7. 전체 이미지 경계 Mask - 중요

입력 Tile의 Halo만 0으로 채우는 것으로는 원본 SRCNN의 전체 이미지 경계를
정확히 재현할 수 없다. Bias 때문에 전체 이미지 바깥 위치의 Conv1/Conv2 Feature가
0이 아닌 값이 될 수 있기 때문이다.

각 Tile의 local 좌표에 해당하는 전체 좌표는 다음과 같다.

```text
global_x = tile_x * 16 - 8 + local_x
global_y = tile_y * 16 - 8 + local_y

valid = 0 <= global_x < 256 and 0 <= global_y < 256
```

다음 두 위치에서 `valid=0`인 Feature를 강제로 0으로 만든다.

```text
Conv1 Requant/ReLU 출력 → boundary mask
Conv2 Requant/ReLU 출력 → boundary mask
```

`full_image/tile_valid_masks.hex`는 `[256,1,32,32]` uint8 검증 데이터다.

```text
mask_addr = tile_id * 1024 + local_y * 32 + local_x
```

Rev5 PL에는 `global_boundary_mask`가 구현되어 있으며 Vitis가 매 타일 START 전에
`TILE_POS(0x20)`를 기록한다.

```text
TILE_POS[3:0] = tile_x
TILE_POS[7:4] = tile_y
tile_pos = ((tile_y & 0x0F) << 4) | (tile_x & 0x0F)
```

Vitis는 좌표 범위를 검사하고 TILE_POS Write/Readback이 일치한 경우에만 NPU를
START한다.

## 8. 전체 이미지 Vector

```text
input_tiles.hex              256×1×32×32 NPU 입력
tile_valid_masks.hex         Conv1/Conv2 후 적용할 경계 Mask
output_tiles_expected.hex    256×1×32×32 전체 Tile 출력
output_valid_expected.hex    256×1×16×16 Center Crop 정답
output_merged_expected.hex   1×256×256 최종 병합 정답
```

Rev5 32×32 Full RTL과 내부 타일의 실보드 Golden 비교는 통과했다.
전체 이미지 Vector는 Team C 프로그램의 대표 경계 타일 및 실제 256타일
실보드 병합 검증에 사용한다.

## 9. Rev5 UART/Vitis 계약

상세 형식은 `docs/uart_protocol.md`를 기준으로 한다.

- PC Master Stop-and-Wait
- 요청 Magic `SRQ1`, 응답 Magic `SRS1`
- little-endian
- PROCESS_TILE 요청: 20-Byte Header + 2,048-Byte Payload = 2,068 Byte
- 정상 응답: 28-Byte Header + 512-Byte Payload = 540 Byte
- CRC32/ISO-HDLC는 Payload만 계산하여 Header에 저장
- Packet 끝에 별도 CRC32를 추가하지 않음
- 요청마다 `tile_x`, `tile_y`, Sequence=`tile_id`를 명시
- 응답은 Command와 Sequence를 Echo하고 PL Cycle Count 및 NPU Status 포함
- NPU VERSION `0x00010001`, 정상 DONE `0x00000002`
- UART `115200 baud`, 8-N-1
- NPU Base `0x43C00000`, Input BRAM Base `0x40000000`
- TILE_POS Offset `0x20`

## 10. 통과 기준

```text
Requant directed mismatch = 0
Conv1/2/3 Layer output mismatch = 0
32×32 Full RTL mismatch = 0
TILE_POS 대표 좌표 Write/Readback = PASS
대표 경계·내부 Board Tile vs Rev5 Python Golden mismatch = 0
Team C UART 256 Tile 누락·중복 = 0
256 Tile FPGA vs Python INT16 mismatch = 0
Merged 256×256 maximum error = 0 LSB
Tile seam 또는 검은 경계선 = 없음
```

`quant_spec.json`이 수치 규격의 단일 원본이고, 각 데이터 폴더의 manifest 및
패키지 최상위 `PACKAGE_SHA256.txt`로 파일 무결성을 확인한다.
