# SRCNN INT16 FPGA Project

Zybo Z7-20 실보드에서 최종 검증한 SRCNN 9-5-5 INT16 가속기의 PC 전처리·후처리, Python Golden, 검증 데이터, UART Host 및 Web UI를 제공한다.

원본 학습 저장소의 학습 코드와 과거 MVP 산출물은 제외하고, 현재 FPGA 프로젝트에 필요한 추론·양자화·타일·HEX·UART 흐름만 분리했다.

## 처리 흐름

```text
LR RGB 128×128
  → Bicubic 256×256
  → Y 채널 추출
  → signed INT16 F15
  → Halo 8 포함 32×32 Tile 256개
  → FPGA UART 전송
  → 중앙 16×16 출력 256개 수신
  → 256×256 결과 결합 및 Golden 비교
```

## 주요 파일

| 파일 | 역할 |
|---|---|
| `prepare_full_image.py` | 128×128 LR 또는 256×256 HR로 전체 입력 타일 생성 |
| `tile_halo.py` | Halo 타일 분리, 경계 mask, 유효 출력 결합 |
| `srcnn_int16_core.py` | FPGA와 동일한 INT16 SRCNN Golden 연산 |
| `generate_tiled_golden.py` | 256개 타일 Golden과 병합 이미지 생성 |
| `evaluate_full_image.py` | Bicubic, FP32, INT16 품질과 오차 평가 |
| `export_full_image_mem.py` | 전체 이미지 NPY를 RTL용 HEX로 변환 |
| `pack_weights_pe4.py` | INT16 weight를 PE4용 64-bit word로 packing |
| `generate_directed_vectors.py` | MAC/Requant RTL 단위 검증 벡터 생성 |
| `uart_protocol.py` | UART Packet encode/decode 및 CRC32 |
| `uart_host.py` | 실제 보드 또는 Mock 보드와 256 Tile 송수신 |
| `uart_single_tile_test.py` | 실제 보드 UART 한 Tile 왕복 및 Golden exact 검사 |
| `srcnn_backend.py` | UI가 공통으로 사용하는 Python/ZYBO Backend 구현 |
| `srcnn_pipeline.py` | Backend 종류와 무관한 256 Tile 실행·결합·비교 파이프라인 |
| `srcnn_demo_image.py` | UI 이미지 전처리, RGB 결과 복원, Y-PSNR 계산 |
| `srcnn_web_ui.py` | 사진 선택·미리보기·진행률·저장을 제공하는 로컬 Web UI |

## 데이터 폴더

| 폴더 | 내용 |
|---|---|
| `weights/` | FP32 pretrained SRCNN ×2 weight |
| `dump_fp32/` | FP32 입력, weight, bias, 계층 출력 기준값 |
| `dump_int16/` | 양자화된 weight, bias와 activation 기준값 |
| `golden_int16/` | 단일 32×32 타일 INT16 Golden |
| `rtl_data/` | 단일 타일 RTL 입력·기대값 HEX |
| `full_image_data/` | 256×256 입력과 32×32 타일 256개 |
| `full_image_golden/` | 전체 이미지 INT16 Golden 출력 |
| `full_image_rtl_data/` | 전체 이미지 RTL용 HEX |
| `packed_weights/` | PE4 64-bit packed weight |
| `directed_vectors/` | MAC와 Requant directed test vector |
| `full_image_evaluation/` | FP32/INT16 비교 이미지와 metric |
| `team_handoff/` | A/B 역할별 최종 설계·인수인계 문서 |
| `docs/` | 프로젝트, UART, 입력 타일 설명 문서 |

## 환경 구성

최종 검증 환경은 Python 3.12.3이며 프로젝트 `.venv`를 사용한다.

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

Linux:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

## 검증 순서

전체 단위 테스트:

```powershell
python -m unittest discover -s . -p "test_*.py"
```

평가용 Butterfly HR에서 입력 생성:

```powershell
python prepare_full_image.py --hr-image data\butterfly_GT.bmp --output-dir full_image_data
```

전체 타일 Golden 생성:

```powershell
python generate_tiled_golden.py
```

UART Mock 검증:

```powershell
python uart_host.py --mock
```

실제 보드 연결 예시:

```powershell
python uart_host.py --list-ports
python uart_host.py --port COM5 --baud 115200 --timeout 10 --retries 0
```

Linux에서는 보통 `COM5` 대신 `/dev/ttyUSB0` 또는 `/dev/ttyACM0`을 사용한다.

```bash
python uart_single_tile_test.py --list-ports
python uart_single_tile_test.py --port /dev/ttyUSB0 --baud 115200 --timeout 10
python uart_host.py --port /dev/ttyUSB0 --baud 115200 --timeout 10 --retries 0
```

## UI용 Backend 분리

UI는 SRCNN 계산이나 UART Packet을 직접 처리하지 않고 `run_pipeline()`만 호출한다.
최종 프로그램은 Python INT16 Backend와 Rev5 ZYBO UART Backend를 모두 지원하며, 두 Backend는 동일한 전처리·타일 병합·후처리 파이프라인을 사용한다.

임시 Python 실행:

```python
import numpy as np

from srcnn_backend import PythonInt16Backend
from srcnn_pipeline import run_pipeline

input_tiles = np.load('full_image_data/input_tiles_int16.npy')
backend = PythonInt16Backend()
result = run_pipeline(backend, input_tiles)
sr_y_int16 = result.merged_output  # shape=(1, 256, 256)
```

실제 ZYBO 실행으로 전환:

```python
from srcnn_backend import ZyboUartBackend

backend = ZyboUartBackend(port='COM5', baudrate=115200, timeout=10.0)
result = run_pipeline(backend, input_tiles)
backend.close()
```

두 Backend 모두 같은 `(256, 1, 32, 32)` INT16 입력을 받고 같은 `(1, 256, 256)` INT16 결과를 반환한다. 상세 구조는 `docs/BACKEND_ARCHITECTURE.md`를 참고한다.

## Web UI 실행

현재 Python 환경에는 Tcl/Tk 런타임이 없어, 추가 GUI 패키지가 필요 없는 로컬 Web UI로 구성했다. 화면에서 Python INT16 또는 ZYBO UART Backend를 선택할 수 있다.

```powershell
python srcnn_web_ui.py
```

Linux에서 Python Backend로 실행:

```bash
python srcnn_web_ui.py --no-browser
```

Linux에서 ZYBO UART를 기본값으로 실행:

```bash
python srcnn_web_ui.py \
  --backend zybo \
  --serial-port /dev/ttyUSB0 \
  --baud 115200 \
  --uart-timeout 10 \
  --retries 0
```

실행하면 기본 브라우저에서 `http://127.0.0.1:8765`가 열린다. 종료할 때는 UI를 실행한 터미널에서 `Ctrl+C`를 누른다.

`사진 선택`에서 다음 중 하나를 입력한다.

- 128×128 이미지: 실제 LR 입력으로 처리
- 256×256 이미지: 평가용 HR로 처리하고 내부에서 128×128 LR 생성

기본 `시연 모드`에는 화면 확대된 LR, Bicubic, SRCNN 결과가 같은 크기로 표시된다. 동일한 64×64 영역을 4배 확대하는 비교창의 X/Y 슬라이더로 세부 차이를 확인할 수 있다. 256×256 HR 입력일 때만 `평가 모드`가 활성화되며, HR 정답과 Bicubic/SRCNN Y-PSNR을 표시한다. 실제 UART Backend에서는 여러 브라우저 작업이 동시에 같은 Serial Port를 열지 않도록 서버가 작업을 직렬화한다.

## 제외한 기존 파일

- `train.py`, `datasets.py`, `prepare.py`: pretrained 모델을 사용하므로 학습 흐름 제외
- `prepare_mvp.py`: 초기 16×16/32×32 MVP 전용
- `thumbnails/`: 원본 저장소 README 표시용
- `uart_*_results/`: 실행할 때 다시 생성되는 임시 결과
- `full_image_golden_smoke/`: 전체 Golden과 중복되는 smoke 산출물
- `full_image_evaluation_crop8/`: 평가 스크립트로 재생성 가능한 중복 결과
- Zebra/PPT3 및 과거 ×3 출력 이미지: 현재 ×2 128→256 데모와 무관

## 기준 문서

- 양자화 규칙: `quant_spec.json`
- UART 규격: `docs/uart_protocol.md`
- 역할별 인수인계: `team_handoff/docs/`
- 전체 프로젝트 인수인계: `docs/SRCNN_FPGA_PROJECT_HANDOFF.md`
