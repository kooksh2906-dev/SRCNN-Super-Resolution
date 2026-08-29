# SRCNN NPU AXI Register Map

이 문서는 최종 Zybo Z7-20 SRCNN NPU의 PS-PL 주소 및 AXI4-Lite Register 계약을 정의한다.

## 시스템 주소

| 구분 | 주소 범위 |
|---|---|
| NPU AXI4-Lite Base | `0x43C00000` |
| NPU AXI4-Lite High | `0x43C0FFFF` |
| Input BRAM Base | `0x40000000` |
| Input BRAM High | `0x40001FFF` |

모든 Register는 32-bit, little-endian, 4-Byte 정렬이다. PL Clock은 100 MHz이며 AXI Reset은 active-low `S_AXI_ARESETN`이다.

## Register Map

| Offset | 이름 | 접근 | Reset | 설명 |
|---:|---|---|---:|---|
| `0x00` | CTRL | WO | `0x00000000` | bit0 START, bit1 CLEAR |
| `0x04` | STATUS | RO | `0x00000000` | bit0 RUN, bit1 DONE, bit2는 최종 RTL에서 0 |
| `0x08` | FINAL_ADDR | RW | `0x00000000` | 최종 32×32 출력 Read Address, 하위 16-bit 사용 |
| `0x0C` | FINAL_DATA | RO | `0x00000000` | 선택된 signed INT16 출력을 32-bit로 Sign Extension |
| `0x10` | CYCLE_COUNT | RO | `0x00000000` | START부터 DONE까지 PL Cycle Count |
| `0x14` | LAYER_DEBUG | RO | `0x00000000` | Idle=0, 실행 중 Conv1/2/3=1/2/3 |
| `0x18` | RESERVED | RO | `0x00000000` | 예약 영역, 현재 0 반환 |
| `0x1C` | VERSION | RO | `0x00010001` | 최종 NPU Hardware Version |
| `0x20` | TILE_POS | RW | `0x00000000` | `[3:0]=tile_x`, `[7:4]=tile_y` |

## CTRL 동작

- bit0 START를 1로 쓰면 NPU가 Idle일 때 1 Clock START Pulse를 생성한다.
- START 시점의 TILE_POS를 내부 Active Tile 좌표로 저장한다.
- NPU 실행 중인 경우 새로운 START는 무시한다.
- bit1 CLEAR를 1로 쓰면 Latch된 DONE을 제거한다.
- 새로운 START도 이전 DONE을 자동으로 제거한다.

## STATUS 동작

- bit0 RUN: NPU 연산 진행 중 1
- bit1 DONE: NPU의 1 Clock DONE Pulse를 Latch
- bit2: Firmware 호환용 ERROR Mask 위치이나 최종 RTL에서는 0

정상 완료 상태는 `0x00000002`이다.

## TILE_POS

```text
TILE_POS[3:0] = tile_x
TILE_POS[7:4] = tile_y
tile_pos = ((tile_y & 0x0F) << 4) | (tile_x & 0x0F)
```

Firmware는 `tile_x`, `tile_y`가 각각 0~15인지 검사하고, TILE_POS Write/Readback이 일치한 경우에만 START를 실행한다.

## Input BRAM

32×32 signed INT16 입력 1,024개를 사용한다. Firmware는 각 INT16 값을 32-bit BRAM Word의 하위 16-bit에 기록한다.

```text
BRAM address = 0x40000000 + pixel_index * 4
pixel_index  = y * 32 + x
```

## 최종 출력 읽기

별도 Output BRAM이나 PL Interrupt를 사용하지 않는다. PS Firmware가 FINAL_ADDR/FINAL_DATA Register를 통해 중앙 16×16 영역을 Polling 방식으로 읽는다.

```text
for y = 8..23
    for x = 8..23
        FINAL_ADDR = y * 32 + x
        pixel = FINAL_DATA[15:0]
```
