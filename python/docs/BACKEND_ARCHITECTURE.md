# Python / ZYBO Backend 분리 구조

## 목적

UI는 이미지 선택, 진행률, 결과 표시만 담당한다. 실제 타일 계산이 Python에서 수행되는지 ZYBO에서 수행되는지는 Backend가 결정한다.

```text
Web UI (현재) / PyQt UI (향후)
   │
   ▼
srcnn_pipeline.run_pipeline()
   │
   ├─ PythonInt16Backend.run_tile()
   └─ ZyboUartBackend.run_tile()
```

두 Backend의 입력과 출력 계약은 같다.

```text
입력 : Tile ID + signed INT16 [1, 32, 32]
출력 : signed INT16 [1, 16, 16]
```

## 임시 Python 실행

```python
import numpy as np

from srcnn_backend import PythonInt16Backend
from srcnn_pipeline import run_pipeline

input_tiles = np.load('full_image_data/input_tiles_int16.npy')

backend = PythonInt16Backend()
try:
    result = run_pipeline(backend, input_tiles)
finally:
    backend.close()

print(result.merged_output.shape)  # (1, 256, 256)
```

## 실제 ZYBO 실행

```python
import numpy as np

from srcnn_backend import ZyboUartBackend
from srcnn_pipeline import run_pipeline

input_tiles = np.load('full_image_data/input_tiles_int16.npy')

backend = ZyboUartBackend(
    port='COM5',
    baudrate=115200,
    timeout=10.0,
    retries=0,
)
try:
    result = run_pipeline(backend, input_tiles)
finally:
    backend.close()
```

UI에서 바뀌는 부분은 Backend 생성 부분뿐이다. 현재 Web UI는 화면의
`Backend` 선택과 Serial Port 설정을 `BackendSettings`로 전달하고,
`JobManager`가 Python 또는 ZYBO Backend를 생성한다.

```python
# 개발 중
backend = PythonInt16Backend()

# 보드 완성 후
backend = ZyboUartBackend(port=selected_port)
```

Web UI 실행 시 ZYBO를 기본값으로 지정할 수도 있다.

```bash
python srcnn_web_ui.py \
  --backend zybo \
  --serial-port /dev/ttyUSB0 \
  --baud 115200 \
  --uart-timeout 10 \
  --retries 0
```

ZYBO UART 작업은 서버 내부 Lock으로 직렬화된다. 여러 브라우저 탭에서
동시에 실행 요청이 들어오더라도 실제 Serial Port와 NPU를 사용하는 작업은
한 번에 하나씩 처리한다.

## 진행률 연결

```python
def on_progress(done, total, tile_result):
    percent = int(done * 100 / total)
    print(percent, tile_result.tile_id)


result = run_pipeline(
    backend,
    input_tiles,
    progress_callback=on_progress,
)
```

현재 Web UI는 이 callback을 백그라운드 작업 상태에 기록하고 브라우저가 주기적으로 조회한다. 향후 PyQt에서는 Worker Signal로 연결하며, `run_pipeline()`은 UI Main Thread가 아닌 `QThread`에서 실행해야 한다.

## 결과 검증

```python
from srcnn_pipeline import compare_int16

comparison = compare_int16(
    result.merged_output,
    golden_merged,
)

print(comparison.mismatch_count)
print(comparison.max_error_lsb)
```
