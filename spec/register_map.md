# NPU Register Map

- Document Version: 1.0
- Status: Review Required
- Interface: AXI4-Lite
- Register Width: 32-bit
- Address Unit: Byte
- Frozen Date: TBD
- Owner: Role A

## 1. 개요

PS의 Vitis 프로그램은 AXI4-Lite 레지스터를 통해 PL의 SRCNN NPU를 제어한다.

- PS: NPU 시작 명령 및 상태 확인
- PL: Conv1, Conv2, Conv3 연산 수행
- 지원 입력 크기: 32×32 Halo Tile
- 정상 출력 영역: 가운데 16×16 영역
- 모든 주소는 4바이트 단위로 정렬한다.

## 2. Access Type

| 표시 | 의미 |
|---|---|
| RW | Software에서 읽기와 쓰기 가능 |
| RO | Software에서는 읽기만 가능 |
| W1P | 1을 쓰면 1 Clock 동안 Pulse 발생 |
| Sticky | CLEAR 전까지 값 유지 |

## 3. Register Summary

| Offset | Register | Access | Reset Value | 설명 |
|---:|---|---|---:|---|
| 0x00 | CTRL | W1P | 0x00000000 | NPU 시작 및 상태 초기화 |
| 0x04 | STATUS | RO | 0x00000000 | BUSY, DONE, ERROR 상태 |
| 0x08 | WIDTH | RW | 0x00000020 | 입력 Tile 너비 |
| 0x0C | HEIGHT | RW | 0x00000020 | 입력 Tile 높이 |
| 0x10 | CYCLE_COUNT | RO | 0x00000000 | 한 번의 추론에 사용된 Clock 수 |
| 0x14 | LAYER_DEBUG | RO | 0x00000000 | 현재 처리 중인 Layer |
| 0x18 | ERROR_STATUS | RO | 0x00000000 | 세부 오류 원인 |
| 0x1C | VERSION | RO | 0x00010000 | NPU Register Map 버전 1.0 |

## 4. CTRL — 0x00

| Bit | 이름 | Access | 설명 |
|---:|---|---|---|
| 0 | START | W1P | 1을 쓰면 NPU 추론 시작 요청 |
| 1 | CLEAR | W1P | DONE, ERROR, ERROR_STATUS 초기화 |
| 31:2 | Reserved | - | 항상 0으로 기록 |

### 동작 규칙

- START는 `BUSY=0`일 때만 정상 접수한다.
- START가 접수되면 CYCLE_COUNT를 0으로 초기화한다.
- `WIDTH=32`, `HEIGHT=32`일 때만 추론을 시작한다.
- BUSY 상태에서 START를 쓰면 새 연산은 시작하지 않고 Busy Start 오류를 기록한다.
- START와 CLEAR를 동시에 쓰면 CLEAR를 먼저 처리한다.
- CLEAR는 현재 실행 중인 추론을 중단하지 않는다.
- CTRL을 읽을 때 START와 CLEAR는 0으로 보인다.

## 5. STATUS — 0x04

| Bit | 이름 | 속성 | 설명 |
|---:|---|---|---|
| 0 | BUSY | Live | NPU가 연산 중이면 1 |
| 1 | DONE | Sticky | 정상적으로 Conv3까지 완료하면 1 |
| 2 | ERROR | Sticky | 하나 이상의 오류가 발생하면 1 |
| 31:3 | Reserved | - | 항상 0 |

### 동작 규칙

- 정상 START 접수 시 BUSY가 1이 된다.
- Conv3와 출력 저장이 완료되면 BUSY는 0, DONE은 1이 된다.
- DONE과 ERROR는 CTRL.CLEAR를 쓸 때 0으로 초기화한다.
- 새로운 START가 정상 접수될 때 이전 DONE 값도 0으로 초기화한다.

## 6. WIDTH — 0x08

| Bit | 이름 | Access | 설명 |
|---:|---|---|---|
| 15:0 | WIDTH | RW | 입력 Tile 너비, 현재 지원값은 32 |
| 31:16 | Reserved | - | 항상 0 |

- Reset 값은 32이다.
- 32 이외의 값으로 START하면 Invalid Size 오류가 발생한다.

## 7. HEIGHT — 0x0C

| Bit | 이름 | Access | 설명 |
|---:|---|---|---|
| 15:0 | HEIGHT | RW | 입력 Tile 높이, 현재 지원값은 32 |
| 31:16 | Reserved | - | 항상 0 |

- Reset 값은 32이다.
- 32 이외의 값으로 START하면 Invalid Size 오류가 발생한다.

## 8. CYCLE_COUNT — 0x10

- 정상 START 접수 시 0으로 초기화한다.
- BUSY가 1인 동안 PL Clock마다 1씩 증가한다.
- 연산 완료 시 마지막 값을 유지한다.
- 단위는 PL Clock Cycle이다.
- PL Clock이 100 MHz라면 1 Cycle은 10 ns이다.

## 9. LAYER_DEBUG — 0x14

| 값 | 상태 |
|---:|---|
| 0 | Idle |
| 1 | Conv1 실행 중 |
| 2 | Conv2 실행 중 |
| 3 | Conv3 실행 중 |
| 그 외 | Reserved |

- 디버깅을 위해 현재 실행 중인 Layer를 표시한다.
- 정상 완료 또는 CLEAR 후에는 0으로 돌아간다.

## 10. ERROR_STATUS — 0x18

| Bit | 이름 | 속성 | 설명 |
|---:|---|---|---|
| 0 | INVALID_SIZE | Sticky | WIDTH 또는 HEIGHT가 32가 아님 |
| 1 | BUSY_START | Sticky | BUSY 상태에서 START 요청 |
| 2 | INTERNAL_ERROR | Sticky | Controller 내부 오류 또는 Timeout |
| 31:3 | Reserved | - | 항상 0 |

- 오류 Bit는 동시에 여러 개가 1이 될 수 있다.
- 하나 이상의 오류 Bit가 1이면 STATUS.ERROR도 1이 된다.
- CTRL.CLEAR를 쓰면 모든 오류 Bit를 0으로 초기화한다.

## 11. VERSION — 0x1C

- Reset 및 고정값: `0x00010000`
- 상위 16-bit: Major Version
- 하위 16-bit: Minor Version
- 현재 버전: 1.0

## 12. Software 기본 제어 순서

1. CTRL.CLEAR에 1을 쓴다.
2. WIDTH에 32를 쓴다.
3. HEIGHT에 32를 쓴다.
4. 입력 Tile과 필요한 데이터를 BRAM에 저장한다.
5. CTRL.START에 1을 쓴다.
6. STATUS.BUSY 또는 STATUS.DONE을 반복 확인한다.
7. DONE이 1이면 출력 BRAM을 읽는다.
8. ERROR가 1이면 ERROR_STATUS를 확인한다.

## 13. 확정 체크리스트

- [ ] 역할 A: RTL 구현 가능 여부 확인
- [ ] 역할 C: Vitis 제어 순서 확인
- [ ] 팀 공통: Offset 및 Bit 위치 확인
- [ ] 검토 완료 후 Status를 Frozen으로 변경
- [ ] Frozen Date 기록