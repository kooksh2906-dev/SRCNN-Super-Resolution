# SRCNN Rev5 NPU UART Binary Protocol v1

## 1. 적용 범위

이 문서는 Team C PC 프로그램과 Team A Rev5 Vitis 펌웨어 사이의 실제 UART 바이너리 계약을 정의한다.

Rev5의 핵심 변경 사항은 다음과 같다.

- 요청 Magic: `SRQ1`
- 응답 Magic: `SRS1`
- 요청과 응답의 Header 형식 분리
- CRC32는 Payload에 대해서만 계산하고 Header 내부에 저장
- 요청마다 `tile_x`, `tile_y`를 명시적으로 전송
- Vitis 펌웨어는 NPU START 전에 `TILE_POS(0x20)`를 기록하고 Readback 검사
- 정상 NPU 완료 상태: `npu_status = 0x00000002`

기존 `SNPU` 공통 Header 및 Packet 끝 CRC 형식과 호환되지 않는다.

## 2. 전송 원칙

- PC가 Master인 Stop-and-Wait 방식
- UART 기본 설정: `115200 baud`, `8 data bits`, `no parity`, `1 stop bit`
- 모든 다중 바이트 정수: little-endian
- 픽셀: signed INT16 two's complement
- 전체 영상: 16×16 타일, 총 256개
- 요청: Halo 포함 32×32 입력
- 응답: 유효 중앙 영역 16×16
- 타일 순서: row-major

```text
tile_id = tile_y * 16 + tile_x
tile_x  = tile_id & 0x0F
tile_y  = (tile_id >> 4) & 0x0F
```

## 3. PC → Vitis 요청

요청 Header는 20 Byte이며 Python 형식은 `<4sBBHIII`이다.

| Offset | 크기 | 형식 | 필드 | 설명 |
|---:|---:|---|---|---|
| 0 | 4 | ASCII | Magic | `SRQ1` |
| 4 | 1 | uint8 | Version | `1` |
| 5 | 1 | uint8 | Command | PROCESS_TILE `1`, PING `2` |
| 6 | 1 | uint8 | Tile X | `0~15` |
| 7 | 1 | uint8 | Tile Y | `0~15` |
| 8 | 4 | uint32 LE | Sequence | Team C에서는 `tile_id` 사용 |
| 12 | 4 | uint32 LE | Payload Length | Byte 단위 |
| 16 | 4 | uint32 LE | Payload CRC32 | Payload만 계산, 빈 Payload는 `0` |
| 20 | N | bytes | Payload | Command별 데이터 |

`<4sBBHIII>`의 uint16 필드는 다음과 같이 패킹한다. little-endian이므로 실제 Byte 6과 7은 각각 `tile_x`, `tile_y`이다.

```python
tile_coordinates = ((tile_y & 0xFF) << 8) | (tile_x & 0xFF)
```

### PROCESS_TILE 요청

- Command: `1`
- 입력 형상: `(1, 32, 32)`
- 픽셀: 1,024개 signed INT16
- Payload: 2,048 Byte
- 전체 요청: `20 + 2048 = 2068 Byte`
- 순서: `pixel_index = local_y * 32 + local_x`

Vitis 처리 순서:

1. `tile_x`, `tile_y` 범위 검사
2. Payload 길이 및 CRC32 검사
3. NPU VERSION `0x00010001` 검사
4. `TILE_POS(0x20)` 기록 및 Readback 검사
5. 32×32 입력 BRAM 기록
6. NPU START 및 DONE 대기
7. 중앙 16×16 결과 송신

```text
TILE_POS[3:0] = tile_x
TILE_POS[7:4] = tile_y
tile_pos = ((tile_y & 0x0F) << 4) | (tile_x & 0x0F)
```

### PING 요청

- Command: `2`
- Payload Length: `0`
- Payload CRC32: `0`
- 전체 요청: 20 Byte
- 정상 응답 Payload: NPU VERSION uint32 `0x00010001`

## 4. Vitis → PC 응답

응답 Header는 28 Byte이며 Python 형식은 `<4sBBBBIIIII`이다.

| Offset | 크기 | 형식 | 필드 | 설명 |
|---:|---:|---|---|---|
| 0 | 4 | ASCII | Magic | `SRS1` |
| 4 | 1 | uint8 | Version | `1` |
| 5 | 1 | uint8 | Status | 아래 표 참조 |
| 6 | 1 | uint8 | Returned Command | 요청 Command Echo |
| 7 | 1 | uint8 | Reserved | `0` |
| 8 | 4 | uint32 LE | Returned Sequence | 요청 Sequence Echo |
| 12 | 4 | uint32 LE | Payload Length | Byte 단위 |
| 16 | 4 | uint32 LE | Payload CRC32 | Payload만 계산 |
| 20 | 4 | uint32 LE | Cycle Count | NPU 연산 PL cycle |
| 24 | 4 | uint32 LE | NPU Status | 정상 DONE `0x00000002` |
| 28 | N | bytes | Payload | 응답 데이터 |

Packet 끝에 별도 CRC32 필드는 없다.

### PROCESS_TILE 정상 응답

- Payload: 256개 signed INT16, 512 Byte
- 전체 응답: `28 + 512 = 540 Byte`
- 순서: `valid_index = valid_y * 16 + valid_x`
- Returned Sequence: 요청 `tile_id`
- Returned Command: `1`
- NPU Status: 정확히 `0x00000002`
- Rev5 실측 Cycle Count: `30,839,827`

PC는 Magic, Version, Command, Sequence, Status, Payload Length, Payload CRC32, NPU Status를 모두 검사한다.

## 5. 오류 Status

| 값 | 이름 | 의미 |
|---:|---|---|
| 0 | OK | 정상 |
| 1 | BAD_VERSION | UART Protocol Version 오류 |
| 2 | BAD_COMMAND | 지원하지 않는 Command |
| 3 | BAD_LENGTH | Payload 길이 오류 |
| 4 | BAD_CRC | Payload CRC32 불일치 |
| 5 | RX_TIMEOUT | 요청 Payload 수신 Timeout |
| 6 | NPU_TIMEOUT | NPU DONE 대기 Timeout |
| 7 | NPU_ERROR | NPU 오류 상태 |
| 8 | HW_VERSION | NPU VERSION 불일치 |
| 9 | BAD_TILE_POSITION | 타일 좌표 범위 오류 |
| 10 | TILE_POS_IO | TILE_POS Write/Readback 불일치 |

오류 응답은 일반적으로 Payload 없이 28 Byte Header만 반환한다.

## 6. CRC32

Rev5 CRC32는 Payload에 대해서만 계산한다.

```python
payload_crc32 = zlib.crc32(payload) & 0xFFFFFFFF
```

- 빈 Payload의 CRC32 필드는 `0`
- Header는 계산 대상에서 제외
- Packet 끝에 trailing CRC32를 추가하지 않음

## 7. 전체 영상 병합

```text
merged_x = tile_x * 16 + valid_x
merged_y = tile_y * 16 + valid_y
```

PC는 응답 Sequence를 확인한 뒤 해당 `tile_id` 위치에 결과를 저장한다. Timeout 또는 재시도 시에도 요청 Header의 명시적 좌표와 Sequence를 사용하므로 펌웨어 내부 암묵적 카운터에 의존하지 않는다.

## 8. Packet 크기

| Packet | Header | Payload | 전체 크기 |
|---|---:|---:|---:|
| PING 요청 | 20 | 0 | 20 Byte |
| PING 정상 응답 | 28 | 4 | 32 Byte |
| PROCESS_TILE 요청 | 20 | 2,048 | 2,068 Byte |
| PROCESS_TILE 정상 응답 | 28 | 512 | 540 Byte |
| 오류 응답 | 28 | 0 | 28 Byte |

256타일 정상 세션의 이론적 전송량:

```text
PC → Board = 2068 * 256 = 529,408 Byte
Board → PC = 540 * 256 = 138,240 Byte
```

## 9. 구현 및 검증 파일

- `uart_protocol.py`: Rev5 encode/decode 및 Payload CRC32 검사
- `uart_host.py`: 실제 Serial Stop-and-Wait 256타일 실행
- `uart_mock.py`: Rev5 Mock ZYBO
- `uart_single_tile_test.py`: 단일 타일 Mock/실보드 검사
- `test_uart_protocol.py`: Header, 좌표, CRC32 단위 테스트
- `test_uart_host.py`: Partial read와 전체 세션 검사
- `srcnn_backend.py`: UI와 UART Backend 연결

현재 완료된 PC 측 검증:

- UART/Backend 회귀 테스트 14개 PASS
- Rev5 256타일 Mock 256/256 PASS
- Mock Golden mismatch `0`, 최대 오차 `0 LSB`
- 대표 단일 타일 Mock: Tile 0, 17, 255 PASS

실보드 전체 256타일 검증은 단일 타일 실보드 검증 통과 후 수행한다.
