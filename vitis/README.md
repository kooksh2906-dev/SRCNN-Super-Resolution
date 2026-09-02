# SRCNN Vitis Firmware

이 디렉터리는 Zybo Z7-20에서 최종 검증한 Cortex-A9 펌웨어, Vitis 재생성
스크립트, UART 진단 도구 및 실행 산출물을 보존한다.

## 디렉터리 구성

- `firmware/src`: 최종 Bare-metal UART 펌웨어
- `scripts`: Platform/Application 재생성 및 Release 검증
- `tools`: SRQ1/SRS1 UART PING·단일 타일 클라이언트
- `output`: 실보드에서 검증한 Application ELF와 FSBL
- `docs`: 최종 실보드 검증 기록

Vivado 하드웨어 입력은 다음 파일을 사용한다.

- `vivado/output/SRCNN_NPU_wrapper.xsa`
- `vivado/output/SRCNN_NPU_wrapper.bit`

## 최종 하드웨어·펌웨어 계약

| 항목 | 값 |
|---|---|
| Board | Zybo Z7-20 / XC7Z020CLG400-1 |
| CPU / OS | `ps7_cortexa9_0` / Standalone |
| UART | PS UART1, 115200 baud, 8N1 |
| Input BRAM | `0x40000000` |
| NPU AXI4-Lite | `0x43C00000` |
| NPU VERSION | `0x00010001` |
| TILE_POS | `0x20` |
| 완료 방식 | DONE polling |
| 정상 NPU Status | `0x00000002` |

## Release 무결성 검사

저장소 최상위에서 실행한다.

```bash
python3 vitis/scripts/verify_release.py
```

BIT, XSA, ELF, FSBL SHA-256, XSA 내장 BIT, 주소 맵, VERSION,
TILE_POS 및 UART 계약이 모두 PASS여야 한다.

## Vitis Platform 재생성

Vitis가 생성하는 Workspace는 기본적으로 `build/vitis_workspace`에 생성되며
Git에서 제외된다.

```bash
source /media/user3/data/tools/Vitis/2024.2/settings64.sh
vitis -s vitis/scripts/create_platform.py
```

외부 Workspace를 사용하려면 다음 환경변수를 지정한다.

```bash
export SRCNN_VITIS_WS=/원하는/외부/워크스페이스
vitis -s vitis/scripts/create_platform.py
```

## 최종 Application 재생성

Platform 생성이 완료된 뒤 실행한다.

```bash
source /media/user3/data/tools/Vitis/2024.2/settings64.sh
vitis -s vitis/scripts/create_application.py
```

생성되는 Platform은 `srcnn_team_a_platform`이고 Application은
`srcnn_team_a_final`이다.

## Workspace 재생성 및 GUI 실행

저장소에 포함된 자동화 스크립트는 최종 XSA를 사용해 Platform과
Application을 순서대로 Build한 뒤 Vitis Unified IDE에서 Workspace를 연다.

저장소 최상위에서 다음 한 줄을 실행한다.

```bash
bash vitis/scripts/rebuild_and_open_workspace.sh
```

기본 Vitis 설치 경로는 `/media/user3/data/tools/Vitis/2024.2`이고,
Workspace는 `build/vitis_workspace`이다. 다른 설치 또는 Workspace 경로를
사용할 때는 환경변수로 지정한다.

```bash
SRCNN_VITIS_HOME=/원하는/Vitis/2024.2 \
SRCNN_VITIS_WS=/원하는/워크스페이스 \
bash vitis/scripts/rebuild_and_open_workspace.sh
```

스크립트를 사용하지 않고 수동으로 실행할 때의 전체 순서는 다음과 같다.

```bash
repo=/path/to/SRCNN-Super-Resolution

source /media/user3/data/tools/Vitis/2024.2/settings64.sh
cd "$repo"

vitis -s vitis/scripts/create_platform.py
vitis -s vitis/scripts/create_application.py

vitis -w "$repo/build/vitis_workspace"
```

생성되는 Workspace는 Build 산출물이므로 Git에 포함하지 않는다. 최종 소스,
재생성 스크립트, 실보드 검증 ELF/FSBL만 저장소에서 관리한다.

## JTAG 연결 확인

별도 터미널에서 Vitis 환경을 설정하고 `hw_server`를 실행한다.

```bash
source /media/user3/data/tools/Vitis/2024.2/settings64.sh
hw_server
```

다른 터미널에서 JTAG Target을 조회한다.

```bash
source /media/user3/data/tools/Vitis/2024.2/settings64.sh
vitis -s vitis/scripts/probe_targets.py
```

## Vitis Launch Configuration

보드 Programming과 Application Download에는 다음 파일을 사용한다.

- Bitstream: `vivado/output/SRCNN_NPU_wrapper.bit`
- FSBL: `vitis/output/fsbl.elf`
- Application: `vitis/output/srcnn_team_a_final.elf`

Board Initialization은 FSBL 또는 Platform에서 생성한 PS7 Init을 사용하고,
Processor는 `ps7_cortexa9_0`을 선택한다.

## UART PING

```bash
python3 vitis/tools/srcnn_uart_client.py --port /dev/serial/by-id/usb-Digilent_Digilent_Adept_USB_Device_210351BD7302-if01-port0 --baud 115200 --ping
```

정상 출력:

```text
PING PASS: NPU_VERSION=0x00010001 STATUS=0x00000000
```

## 단일 타일 실행

```bash
python3 vitis/tools/srcnn_uart_client.py --port /dev/serial/by-id/usb-Digilent_Digilent_Adept_USB_Device_210351BD7302-if01-port0 --baud 115200 --tile-x 0 --tile-y 0 --input input_tile.bin --output output_center.bin
```

정상 응답은 512 Byte의 16×16 signed INT16 결과이며 NPU Status는
`0x00000002`다.

최종 실보드 결과는 `docs/board_validation.md`를 참조한다.
