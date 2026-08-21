# PC–FPGA UART Binary Protocol

- Document Version: 1.0
- Status: Review Required
- Owner: Role A / Role C
- Transport: UART
- Default Baud Rate: 115200
- Frozen Date: TBD

## 1. 목적

PC Python 프로그램과 ZYBO Z7-20의 Vitis 프로그램이 SRCNN Tile 데이터를 주고받기 위한 Binary Packet 규칙이다.

- PC는 32×32 Halo Tile을 보드로 전송한다.
- Vitis는 Tile을 BRAM에 저장하고 NPU를 시작한다.
- NPU 완료 후 Vitis는 가운데 16×16 결과만 PC로 반환한다.
- PC는 총 256개의 결과 Tile을 원래 위치에 합친다.

UART 통신 중에는 일반 문자열 Debug Message를 함께 전송하지 않는다. 문자열이 Binary Packet 사이에 들어가면 Packet을 구분할 수 없기 때문이다.

## 2. UART 설정

| 항목 | 설정 |
|---|---|
| Baud Rate | 115200 bps |
| Data Bit | 8-bit |
| Parity | None |
| Stop Bit | 1-bit |
| Flow Control | None |
| 전송 방식 | Binary |
| Byte Order | Little Endian |

## 3. 공통 Packet 구조

| Byte Offset | 크기 | 필드 | 설명 |
|---:|---:|---|---|
| 0 | 1 Byte | MAGIC0 | 고정값 `0x53`, 문자 `S` |
| 1 | 1 Byte | MAGIC1 | 고정값 `0x52`, 문자 `R` |
| 2 | 1 Byte | VERSION | Protocol Version, 현재 `0x01` |
| 3 | 1 Byte | TYPE | Packet 종류 |
| 4 | 2 Byte | TILE_ID | Tile 번호, Little Endian |
| 6 | 2 Byte | PAYLOAD_LENGTH | Payload 크기, Little Endian |
| 8 | N Byte | PAYLOAD | 실제 전송 데이터 |
| 8+N | 2 Byte | CHECKSUM | 16-bit Checksum, Little Endian |

전체 Packet 크기는 `10 + PAYLOAD_LENGTH` Byte이다.

## 4. Packet Type

| TYPE | 이름 | 방향 | Payload 크기 |
|---:|---|---|---:|
| 0x00 | PING | PC → FPGA | 0 Byte |
| 0x01 | TILE_INPUT | PC → FPGA | 2048 Byte |
| 0x80 | READY | FPGA → PC | 4 Byte |
| 0x81 | TILE_RESULT | FPGA → PC | 512 Byte |
| 0xE0 | ERROR | FPGA → PC | 4 Byte |

## 5. Tile 번호

전체 256×256 이미지를 유효 영역 16×16 단위로 나누므로 총 256개의 Tile을 사용한다.

- `tile_x`: 0~15
- `tile_y`: 0~15
- `TILE_ID = tile_y × 16 + tile_x`
- 유효한 TILE_ID 범위: 0~255

예시는 다음과 같다.

| tile_x | tile_y | TILE_ID |
|---:|---:|---:|
| 0 | 0 | 0 |
| 1 | 0 | 1 |
| 15 | 0 | 15 |
| 0 | 1 | 16 |
| 15 | 15 | 255 |

## 6. PING Packet — TYPE 0x00

PC가 FPGA의 통신 준비 상태를 확인할 때 사용한다.

- TILE_ID: 0
- PAYLOAD_LENGTH: 0
- FPGA는 PING을 정상 수신하면 READY Packet을 반환한다.

자동으로 전송되는 시작 문자열은 사용하지 않는다. PC가 먼저 PING을 보내고 READY 응답을 확인한다.

## 7. READY Packet — TYPE 0x80

FPGA가 정상적으로 통신할 수 있음을 PC에 알린다.

Payload 구조는 다음과 같다.

| Payload Offset | 크기 | 이름 | 설명 |
|---:|---:|---|---|
| 0 | 1 Byte | PROTOCOL_VERSION | 현재 `0x01` |
| 1 | 1 Byte | TILE_SIZE | 현재 `0x20`, 32 Pixel |
| 2 | 2 Byte | MAX_TILE_ID | 현재 `0x00FF`, 255 |

## 8. TILE_INPUT Packet — TYPE 0x01

PC가 FPGA에 하나의 32×32 Halo Tile을 전송한다.

- Payload 크기: `32 × 32 × 2 = 2048 Byte`
- Pixel 자료형: signed INT16
- Pixel Byte Order: Little Endian
- Pixel 순서: Row-major
- 같은 행에서는 x가 먼저 증가한다.

Pixel의 Payload 위치는 다음 식을 사용한다.

`pixel_index = y × 32 + x`

`byte_offset = pixel_index × 2`

입력 Tile의 좌표 범위는 다음과 같다.

- x: 0~31
- y: 0~31
- 가운데 유효 영역: x=8~23, y=8~23
- 이미지 바깥쪽 Halo 영역은 PC에서 0으로 채운다.

## 9. TILE_RESULT Packet — TYPE 0x81

FPGA가 NPU 처리 결과 중 가운데 16×16 영역만 PC에 반환한다.

- Payload 크기: `16 × 16 × 2 = 512 Byte`
- Pixel 자료형: signed INT16
- 정상 출력 범위: 0~32767
- Pixel Byte Order: Little Endian
- Pixel 순서: Row-major
- 응답 TILE_ID는 요청 TILE_INPUT의 TILE_ID와 같아야 한다.

결과 Pixel의 Payload 위치는 다음 식을 사용한다.

`pixel_index = y × 16 + x`

`byte_offset = pixel_index × 2`

결과 좌표 범위는 다음과 같다.

- x: 0~15
- y: 0~15

## 10. ERROR Packet — TYPE 0xE0

FPGA가 요청을 처리하지 못했을 때 반환한다.

Payload 구조는 다음과 같다.

| Payload Offset | 크기 | 이름 | 설명 |
|---:|---:|---|---|
| 0 | 2 Byte | ERROR_CODE | 오류 종류 |
| 2 | 2 Byte | ERROR_DETAIL | 추가 오류 정보 |

Error Code는 다음과 같다.

| ERROR_CODE | 이름 | 설명 |
|---:|---|---|
| 0x0001 | INVALID_MAGIC | Magic 값 오류 |
| 0x0002 | INVALID_VERSION | 지원하지 않는 Protocol Version |
| 0x0003 | INVALID_TYPE | 지원하지 않는 Packet Type |
| 0x0004 | INVALID_LENGTH | Payload 크기 오류 |
| 0x0005 | CHECKSUM_ERROR | Checksum 불일치 |
| 0x0006 | INVALID_TILE_ID | TILE_ID가 0~255 범위를 벗어남 |
| 0x0007 | NPU_BUSY | 이전 Tile을 처리 중 |
| 0x0008 | NPU_ERROR | NPU 내부 처리 오류 |
| 0x0009 | NPU_TIMEOUT | 제한 시간 내 연산 미완료 |

가능한 경우 ERROR Packet의 TILE_ID에는 오류가 발생한 요청의 TILE_ID를 넣는다.

## 11. Checksum 계산

Checksum은 다음 Byte들의 합을 16-bit로 자른 값이다.

- VERSION
- TYPE
- TILE_ID 2 Byte
- PAYLOAD_LENGTH 2 Byte
- PAYLOAD 전체

MAGIC0, MAGIC1과 마지막 CHECKSUM 필드는 계산에 포함하지 않는다.

계산식은 다음과 같다.

`checksum = sum(VERSION부터 PAYLOAD 마지막 Byte까지) & 0xFFFF`

송신 측과 수신 측이 계산한 값이 다르면 Packet을 사용하지 않는다.

## 12. 기본 통신 순서

1. PC가 UART Port를 연다.
2. PC가 PING Packet을 보낸다.
3. FPGA가 READY Packet을 반환한다.
4. PC가 TILE_ID 0의 TILE_INPUT을 보낸다.
5. Vitis가 32×32 입력을 BRAM에 저장한다.
6. Vitis가 NPU START를 실행한다.
7. Vitis가 STATUS의 DONE 또는 ERROR를 확인한다.
8. 정상 완료 시 TILE_RESULT를 반환한다.
9. PC가 응답 TILE_ID를 확인하고 결과를 저장한다.
10. TILE_ID 1부터 255까지 같은 과정을 반복한다.
11. PC가 256개의 16×16 결과를 하나의 256×256 이미지로 합친다.

한 번에 하나의 TILE_INPUT만 처리한다. PC는 TILE_RESULT 또는 ERROR를 받은 후 다음 Tile을 전송한다.

## 13. Timeout 및 재전송

- PC 응답 대기시간 초기값: 5초
- 제한 시간 내 응답이 없으면 동일 TILE_ID를 다시 전송할 수 있다.
- 기본 최대 재시도 횟수: 3회
- 3회 모두 실패하면 전체 처리를 중단하고 오류를 기록한다.
- Checksum 오류가 발생한 Packet은 결과로 사용하지 않는다.

## 14. 수신 동기 복구

수신 측이 잘못된 Byte를 발견하면 다음 `0x53 0x52` 순서를 찾을 때까지 Byte를 버린다.

새로운 Magic을 발견하면 Header부터 다시 수신한다.

Payload를 수신하기 전에 TYPE과 PAYLOAD_LENGTH가 올바른 조합인지 검사한다. 잘못된 길이를 그대로 신뢰하여 Buffer Overflow가 발생하지 않도록 한다.

## 15. 확정 체크리스트

- [ ] 역할 A: Vitis와 Register 제어 흐름 확인
- [ ] 역할 C: PC Python Packet 구현 가능 여부 확인
- [ ] 역할 C: 115200 Baud Rate 처리시간 확인
- [ ] 팀 공통: Checksum 방식 확인
- [ ] 팀 공통: Timeout 5초 및 재시도 3회 확인
- [ ] 검토 완료 후 Status를 Frozen으로 변경
- [ ] Frozen Date 기록