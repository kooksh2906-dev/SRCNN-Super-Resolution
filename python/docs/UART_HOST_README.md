# Rev5 UART PC Master 사용법

## 1. 실행 환경

Team C 프로그램은 프로젝트 가상환경에서 실행한다.

```bash
cd /home/user3/Downloads/pc_tools/srcnn-fpga-int16
.venv/bin/python --version
```

현재 검증된 환경:

- Python 3.12.3
- NumPy 2.5.2
- Pillow 12.3.0
- pyserial 3.5

패키지를 다시 설치해야 할 때만 다음을 실행한다.

```bash
.venv/bin/python -m pip install -r requirements.txt
```

## 2. Rev5 고정 계약

- UART: `115200 baud`, 8 data bits, no parity, 1 stop bit
- 요청 Magic: `SRQ1`
- 응답 Magic: `SRS1`
- 요청 Header: `<4sBBHIII>`, 20 Byte
- 응답 Header: `<4sBBBBIIIII>`, 28 Byte
- CRC32: Payload만 계산하고 Header에 저장
- 요청 Payload: 32×32 signed INT16, 2,048 Byte
- 응답 Payload: 중앙 16×16 signed INT16, 512 Byte
- 정상 NPU 상태: `0x00000002`
- NPU VERSION: `0x00010001`

AXI UART의 Baud Rate는 Bitstream에 포함된 HW 설정이다. PC 옵션만 460800 또는
921600으로 변경하지 않는다. Baud Rate를 변경하려면 Vivado HW와 Bitstream을 함께
다시 생성해야 한다.

상세 Packet 정의는 `docs/uart_protocol.md`를 참조한다.

## 3. 기본 데이터

프로그램은 다음 Rev5 Global Boundary Mask Golden 자료를 기본으로 사용한다.

```text
full_image_data/input_tiles_int16.npy
  shape: (256, 1, 32, 32)

full_image_golden/output_tiles_int16.npy
  shape: (256, 1, 32, 32)

full_image_golden/output_merged_int16.npy
  shape: (1, 256, 256)
```

타일 순서는 row-major이다.

```text
tile_id = tile_y * 16 + tile_x
```

## 4. Mock 검증

실보드 실행 전에 Mock으로 PC의 Packet, 타일 순서, 병합 및 Golden 비교를 검증한다.

### 단일 타일 Mock

```bash
.venv/bin/python uart_single_tile_test.py \
    --mock \
    --tile-id 0 \
    --output-dir uart_single_tile_results_rev5_mock_000
```

대표 경계·내부 타일은 최소한 다음 ID를 검사한다.

| Tile ID | 좌표 | 구분 |
|---:|---|---|
| 0 | `(0,0)` | 왼쪽 위 경계 |
| 17 | `(1,1)` | 내부 |
| 255 | `(15,15)` | 오른쪽 아래 경계 |

정상 기준:

```text
Golden mismatch  : 0/256
Max error        : 0 LSB
NPU status       : 0x00000002
Result           : PASS
```

### 전체 256타일 Mock

기존 결과를 덮어쓰지 않도록 새 출력 폴더를 지정한다.

```bash
.venv/bin/python uart_host.py \
    --mock \
    --output-dir uart_results_rev5_mock
```

정상 기준:

```text
Tiles             : 256/256
Mismatch Tiles    : 0
Merged Mismatch   : 0
Max Error         : 0 LSB
```

## 5. 실보드 실행 전 준비

1. Zybo Z7-20의 JTAG와 UART USB를 연결한다.
2. `hw_server`를 실행한다.
3. Vitis 2024.2 GUI에서 Rev5 Launch Configuration을 사용한다.
4. Rev5 BIT와 `srcnn_team_a_final.elf`를 Run한다.
5. moserial 등 UART 포트를 점유하는 프로그램을 모두 닫는다.
6. UART 장치가 비어 있는지 확인한다.

```bash
UART_DEV=/dev/serial/by-id/usb-Digilent_Digilent_Adept_USB_Device_210351BD7302-if01-port0

readlink -f "$UART_DEV"
fuser -v "$UART_DEV"
```

`fuser`가 아무 프로세스도 표시하지 않아야 한다.

사용 가능한 포트 목록은 다음 명령으로 확인할 수 있다.

```bash
.venv/bin/python uart_single_tile_test.py --list-ports
```

Windows에서는 `/dev/serial/...` 대신 장치 관리자에서 확인한 `COM5`와 같은 포트를
`--port`에 지정한다.

## 6. 실보드 단일 타일 검증

전체 256타일 실행 전에 반드시 단일 타일을 먼저 통과시킨다.

```bash
UART_DEV=/dev/serial/by-id/usb-Digilent_Digilent_Adept_USB_Device_210351BD7302-if01-port0

.venv/bin/python uart_single_tile_test.py \
    --port "$UART_DEV" \
    --baud 115200 \
    --timeout 5 \
    --tile-id 0 \
    --output-dir uart_single_tile_results_rev5_board_000
```

Tile 0이 통과하면 같은 방식으로 Tile 17과 Tile 255를 검사한다. 각 실행마다 서로
다른 `--output-dir`을 사용한다.

정상 기준:

- 응답 Tile ID가 요청 Tile ID와 동일
- Payload 크기 512 Byte
- NPU Status `0x00000002`
- Golden mismatch `0/256`
- 최대 오차 `0 LSB`
- 결과 `PASS`

## 7. 실보드 전체 256타일 검증

단일 타일 검증이 모두 통과한 뒤 실행한다.

```bash
UART_DEV=/dev/serial/by-id/usb-Digilent_Digilent_Adept_USB_Device_210351BD7302-if01-port0

.venv/bin/python uart_host.py \
    --port "$UART_DEV" \
    --baud 115200 \
    --timeout 5 \
    --retries 1 \
    --output-dir uart_results_rev5_board
```

정상 완료 조건:

- 256개 타일 처리 완료
- 응답 Tile ID 누락·중복 없음
- `Mismatch Tiles = 0`
- `Merged Mismatch = 0`
- `Max Error = 0 LSB`
- Timeout 또는 Protocol Error 없음

## 8. 결과 파일

### 단일 타일

`--output-dir` 아래에 다음 파일이 생성된다.

- `actual_valid_int16.npy`: 보드에서 받은 16×16 결과
- `golden_valid_int16.npy`: 비교용 Golden 16×16
- `difference_lsb.npy`: Actual-Golden 정수 오차
- `summary.json`: Tile ID, cycle, NPU status, mismatch 요약

### 전체 256타일

- `fpga_merged_int16.npy`: 256개 Valid Tile을 병합한 INT16 결과
- `fpga_merged_256.png`: 확인용 256×256 Gray 이미지
- `session_summary.json`: 시간, cycle, retry, mismatch 요약
- `mismatch_log.json`: 실패 타일과 최초 불일치 좌표

기존 결과 보존을 위해 Mock과 실보드 실행에 서로 다른 출력 폴더를 사용한다.

## 9. 오류 확인 순서

1. UART 포트를 moserial이나 다른 프로세스가 점유하는지 확인
2. PC Baud가 115200인지 확인
3. Vitis가 Rev5 BIT와 Rev5 ELF를 실행했는지 확인
4. NPU VERSION이 `0x00010001`인지 확인
5. 오류 Status 이름 확인
6. Tile ID와 좌표 범위 확인
7. Payload 길이와 CRC32 확인
8. NPU Status가 `0x00000002`인지 확인

주요 Status:

- `HW_VERSION`: 구 ELF 또는 잘못된 HW VERSION
- `BAD_TILE_POSITION`: Tile 좌표가 0~15 범위를 벗어남
- `TILE_POS_IO`: TILE_POS Write/Readback 불일치
- `BAD_CRC`: Payload 손상 또는 Protocol 불일치
- `NPU_TIMEOUT`: START 후 DONE Timeout

실패한 전체 실행은 같은 출력 폴더에 즉시 재실행하지 말고, 로그와 결과 폴더를 먼저
보존한 뒤 원인을 분석한다.
