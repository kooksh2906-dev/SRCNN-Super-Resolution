# SRCNN INT16 FPGA 프로젝트 인수인계 문서

## 1. 프로젝트 목표

PyTorch로 학습된 FP32 SRCNN을 INT16 고정소수점 연산으로 재현하고, 이를 FPGA RTL로 구현한다.

최종 비교 대상은 다음과 같다.

1. PyTorch FP32 SRCNN 출력
2. Python INT16 Golden Model 출력
3. FPGA RTL INT16 출력

RTL의 일차 합격 조건은 **FPGA RTL 출력이 Python INT16 Golden Model과 정수값 기준으로 일치하는 것**이다. FP32와 INT16의 차이는 별도로 오차와 PSNR로 평가한다. 이후 Python/CPU와 FPGA의 처리 시간도 측정한다.

개발 도구는 다음 버전으로 통일한다.

- RTL 설계, 시뮬레이션, 합성: Vivado 2024.2
- Zynq SoC 소프트웨어: Vitis Unified IDE 2024.2
- RTL 언어: SystemVerilog
- 대상 보드: ZYBO Z7 예정. Z7-10 또는 Z7-20 모델 확인 필요

---

## 2. 사용 모델

기준 저장소는 `yjn870/SRCNN-pytorch`이며, pretrained `srcnn_x2.pth`를 사용한다.

모델 구조는 다음과 같다.

| 계층 | 입력 채널 | 출력 채널 | 커널 | Padding | 활성화 |
|---|---:|---:|---:|---:|---|
| Conv1 | 1 | 64 | 9×9 | 4 | ReLU |
| Conv2 | 64 | 32 | 5×5 | 2 | ReLU |
| Conv3 | 32 | 1 | 5×5 | 2 | 없음 |

Padding 때문에 각 계층의 입력과 출력 높이·너비는 동일하다. 전체 receptive field는 17×17이며, 한 출력 픽셀은 중심에서 최대 8픽셀 떨어진 입력까지 참조한다.

이 구현은 RGB 전체가 아니라 YCbCr의 **Y(휘도) 채널**에 SRCNN을 적용한다. Cb, Cr은 일반적으로 bicubic 결과를 사용한 뒤 Y 채널과 다시 결합한다.

---

## 3. HR, LR 및 SRCNN 입력의 의미

- HR(High Resolution): 정답으로 사용하는 원본 고해상도 이미지
- LR(Low Resolution): HR을 축소하여 만든 저해상도 이미지
- SRCNN 입력: LR을 bicubic으로 목표 크기까지 다시 확대한 이미지
- SRCNN 출력: bicubic 입력을 보정하여 복원한 고해상도 추정 이미지

Classic SRCNN x2의 전처리는 다음과 같다.

```text
HR 32×32
  ↓ x2 축소
LR 16×16
  ↓ bicubic x2 확대
SRCNN 입력 32×32
  ↓ SRCNN
복원 출력 32×32
  ↔ HR 32×32와 품질 비교
```

따라서 `butterfly_GT.bmp`는 HR 정답 이미지다. `butterfly_GT_srcnn_x3.bmp`와 같은 파일은 LR 자체가 아니라 SRCNN이 생성한 복원 결과다. 실제 사용 시 HR 정답이 없어도 LR로부터 복원 이미지를 만들 수 있지만, 정답 HR이 없으면 PSNR 같은 정량적 복원 품질은 계산할 수 없다.

현재 32×32 크기는 SRCNN 모델이 반드시 요구하는 크기가 아니라 RTL 검증을 단순하게 만들기 위해 선택한 테스트 크기다.

---

## 4. 이미지 크기가 32×32에서 30×30이 되었던 이유

원본 코드에는 다음과 같이 이미지 크기를 scale의 배수로 자르는 처리가 있다.

```python
image_width = (image.width // args.scale) * args.scale
image_height = (image.height // args.scale) * args.scale
```

32×32 이미지에 `scale=3`을 사용하면 다음과 같이 30×30이 된다.

```text
(32 // 3) × 3 = 30
```

`scale=2`로 실행하면 32가 2의 배수이므로 32×32를 유지한다. 뒤이어 수행되는 resize 세 번은 HR 크기를 scale의 배수로 정리하고, LR로 축소한 다음, 다시 bicubic으로 원래 목표 크기까지 확대하는 전처리 과정이다.

---

## 5. `test.py` 실행 인자

다음 선언은 경로 자체를 인자 이름으로 쓰는 코드가 아니다.

```python
parser.add_argument('--weights-file', type=str, required=True)
parser.add_argument('--image-file', type=str, required=True)
parser.add_argument('--scale', type=int, default=3)
```

실행할 때 경로를 전달해야 한다.

```powershell
python test.py --weights-file .\weights\srcnn_x2.pth --image-file .\data\butterfly_GT.bmp --scale 2
```

경로를 코드에 기본값으로 고정하려면 다음처럼 옵션 이름은 유지하고 `default`를 지정한다.

```python
parser.add_argument('--weights-file', type=str, default='./weights/srcnn_x2.pth')
parser.add_argument('--image-file', type=str, default='./data/butterfly_GT.bmp')
parser.add_argument('--scale', type=int, default=2)
```

이 경우 `required=True`는 제거해야 한다.

이미지 저장 경로를 만들 때 문자열 전체에 `replace('.', ...)`를 적용하면 `./data/...`의 첫 점까지 바뀌어 잘못된 경로가 만들어질 수 있다. 출력 파일명은 `pathlib.Path`의 `stem`, `suffix`, `with_name()`으로 생성하는 것이 안전하다.

---

## 6. Python에서 추가한 파일과 역할

| 파일 | 역할 |
|---|---|
| `prepare_mvp.py` | MVP용 이미지 준비 및 LR/HR 전처리 |
| 수정한 `test.py` | FP32 SRCNN 추론, PSNR 계산, 계층별 데이터 dump |
| `inspect_dump.py` | NPY shape, min, max, max absolute value 확인 |
| `quantize_int16.py` | FP32 입력·가중치·bias 등을 지정된 Q-format 정수로 변환 |
| `int16_golden.py` | RTL과 동일한 INT16/INT48 규칙으로 SRCNN을 계산하는 Golden Model |
| `compare_fixed_point.py` | FP32와 INT16 결과의 최대오차, 평균오차, RMSE, PSNR 계산 |
| `export_mem.py` | NPY 정수 데이터를 RTL `$readmemh`용 HEX 파일로 변환하고 재검증 |

주요 출력 폴더의 의미는 다음과 같다.

| 폴더 | 내용 |
|---|---|
| `dump_fp32` | PyTorch FP32 입력, 가중치, bias, 계층 출력 |
| `dump_int16` | 양자화된 RTL 입력, 가중치, bias 및 관련 정수 데이터 |
| `golden_int16` | Python INT16 Golden Model의 계층별 기대 출력 |
| `rtl_data` | RTL에서 읽을 수 있게 HEX로 직렬화한 데이터와 `manifest.json` |

`dump_int16`은 새로운 학습 결과가 아니다. 이미 학습된 FP32 모델의 파라미터와 테스트 입력을 INT16 고정소수점 표현으로 변환한 것이다. `golden_int16`은 그 정수 데이터를 RTL과 같은 규칙으로 계산한 기준 결과다.

일반적인 머신러닝 용어도 다음과 같이 구분한다.

- `x_train`, `y_train`: 모델 학습에 사용
- `x_test`, `y_test`: 학습된 모델 평가에 사용
- pretrained weight: 학습이 완료된 모델 파라미터
- quantization: 학습된 FP32 파라미터와 연산값을 정수 형식으로 근사

---

## 7. FP32 dump 결과

32×32 입력 기준 주요 배열은 다음과 같다.

| 데이터 | Shape | 최솟값 | 최댓값 |
|---|---|---:|---:|
| input_y | (1, 1, 32, 32) | 0.220318 | 0.766795 |
| conv1 weight | (64, 1, 9, 9) | -1.368269 | 0.493044 |
| conv1 output | (1, 64, 32, 32) | -1.937088 | 0.575621 |
| relu1 output | (1, 64, 32, 32) | 0 | 0.575621 |
| conv2 weight | (32, 64, 5, 5) | -0.964747 | 0.694670 |
| conv2 output | (1, 32, 32, 32) | -1.574136 | 1.839641 |
| relu2 output | (1, 32, 32, 32) | 0 | 1.839641 |
| conv3 weight | (1, 32, 5, 5) | -0.164505 | 0.191430 |
| output_fp32 | (1, 1, 32, 32) | 0.170315 | 0.844288 |

PyTorch에서 별도 양자화 처리를 하지 않은 원본 모델과 weight는 FP32로 연산한다.

---

## 8. 확정된 고정소수점 규격

F는 소수부 비트 수를 뜻한다. 실수값 `x`를 정수로 변환하는 기본식은 다음과 같다.

```text
q = round(x × 2^F)
```

확정된 계층별 형식은 다음과 같다.

| 데이터 | 저장형 | F | RTL 처리 |
|---|---|---:|---|
| 입력 Y | int16 | 15 | Conv1 입력 |
| Conv1 weight | int16 | 14 | 입력과 곱셈 |
| Conv1 bias | int32 | 29 | accumulator에 부호 확장 후 더함 |
| ReLU1 출력 | int16 | 15 | 14비트 requantize 후 ReLU/saturation |
| Conv2 weight | int16 | 15 | ReLU1과 곱셈 |
| Conv2 bias | int32 | 30 | accumulator에 부호 확장 후 더함 |
| ReLU2 출력 | int16 | 14 | 16비트 requantize 후 ReLU/saturation |
| Conv3 weight | int16 | 15 | ReLU2와 곱셈 |
| Conv3 bias | int32 | 29 | accumulator에 부호 확장 후 더함 |
| 최종 출력 | int16 | 15 | 14비트 requantize 후 0~32767 clamp |

계층별 핵심 연산은 다음과 같다.

```text
Conv1: INT48_ACC → symmetric rounding → >>> 14 → ReLU → INT16
Conv2: INT48_ACC → symmetric rounding → >>> 16 → ReLU → INT16
Conv3: INT48_ACC → symmetric rounding → >>> 14 → clamp 0..32767 → INT16
```

RTL 데이터 폭은 다음을 기준으로 한다.

- activation: signed 16-bit
- weight: signed 16-bit
- multiplication result: signed 32-bit
- bias: signed 32-bit
- accumulator: signed 48-bit

현재 테스트에서 관찰한 accumulator 필요 비트 수는 Conv1 31비트, Conv2 32비트, Conv3 30비트였다. 하지만 다른 이미지와 최악 조건의 여유를 위해 RTL에서는 48비트를 사용한다.

주의: Python Golden Model과 RTL은 rounding, arithmetic right shift, signed extension, saturation 순서가 정확히 같아야 한다. 특히 음수의 rounding 규칙이 다르면 1 LSB 이상의 차이가 누적될 수 있다.

---

## 9. 양자화 및 Golden Model 검증 결과

양자화된 각 배열에서는 saturation이 0회였다. 대표 최대 양자화 오차는 다음 범위였다.

- INT16 F14: 약 0.00003052 이하
- INT16 F15: 약 0.00001526 이하
- INT32 bias: 약 1e-9 이하

계층별 INT16 Golden 오차는 다음과 같다.

| 위치 | 최대오차 | 평균오차 | 완전 일치율 |
|---|---:|---:|---:|
| ReLU1 | 8 LSB | 1.1776 LSB | 43.73% |
| ReLU2 | 10 LSB | 1.2140 LSB | 44.15% |
| Output | 17 LSB | 8.3604 LSB | 1.17% |

INT16 최종 출력과 FP32 출력의 비교 결과는 다음과 같다.

```text
Maximum error : 0.000518798828125
Mean error    : 0.00025513768196105957
RMSE          : 0.0002801190022034553
PSNR          : 71.05314858595723 dB
```

PSNR 약 71 dB이므로 현재 Q-format에서 FP32 대비 양자화 오차는 매우 작다. RTL은 우선 FP32와 직접 동일성을 요구하는 것이 아니라 `golden_int16`과 정수 단위로 동일해야 한다.

---

## 10. NPY에서 HEX로 변환

`export_mem.py`는 `dump_int16`과 `golden_int16`의 NPY 파일을 RTL 메모리 파일로 변환한다.

처음 발생했던 오류는 실행 위치 기준 상대경로에서 `dump_int16/input_y.npy`를 찾지 못해 발생했다. 입력 폴더를 실제 절대경로 또는 올바른 프로젝트 상대경로로 수정한 뒤 변환이 성공했다.

완료 메시지는 다음과 같았다.

```text
All HEX files verified.
Output directory: .\rtl_data
Manifest: .\rtl_data\manifest.json
```

HEX는 signed 정수를 two's complement로 기록한다. RTL에서 signed로 해석해야 한다. 각 파일의 bit width, element count, shape, 순서는 `rtl_data/manifest.json`을 단일 기준으로 삼는다.

32×32 한 장 기준 주요 데이터 개수는 다음과 같다.

| 데이터 | 원소 수 |
|---|---:|
| Input Y | 1,024 |
| Conv1 weight | 5,184 |
| Conv1 bias | 64 |
| Conv1 activation | 65,536 |
| Conv2 weight | 51,200 |
| Conv2 bias | 32 |
| Conv2 activation | 32,768 |
| Conv3 weight | 800 |
| Conv3 bias | 1 |
| Conv3/output | 1,024 |

Vivado 시뮬레이션의 `$readmemh()`는 `.hex` 확장자도 읽을 수 있다. XPM memory initialization 등 Vivado 프로젝트 관례와의 호환성을 위해 동일 내용을 `.mem` 확장자로 복사하거나 exporter가 `.mem`도 생성하게 할 수 있다.

---

## 11. RTL 검증 전략

RTL은 작은 단위부터 다음 순서로 구현한다.

### 11.1 MAC Processing Element

```text
acc = bias + Σ(activation × weight)
```

검증 항목:

- INT16 signed 곱셈 결과가 INT32인지 확인
- INT32 bias를 INT48로 정확히 sign extension
- 매 클럭 enable 시 한 번만 누적
- reset, clear, load_bias 우선순위 확인
- 양수·음수·경계값 테스트

예정 파일:

```text
rtl/src/mac_pe.sv
rtl/tb/tb_mac_pe.sv
```

### 11.2 Requantizer

검증 항목:

- 계층별 shift 14/16/14
- Python과 동일한 symmetric rounding
- arithmetic right shift
- Conv1/Conv2 ReLU
- INT16 saturation
- Conv3 최종 0~32767 clamp

### 11.3 Conv1

입력과 파라미터는 `rtl_data`에서 읽고 출력은 `golden_int16`의 ReLU1 결과와 원소별 비교한다.

```text
Input Y + Conv1 weights + Conv1 bias
    ↓ RTL Conv1
ReLU1 output
    ↔ Golden ReLU1 HEX와 모든 원소 비교
```

### 11.4 Conv2 및 Conv3

Conv1과 같은 방식으로 각 계층을 독립 검증한 뒤 전체 데이터 경로를 연결한다. 디버깅 시 계층의 accumulator 출력까지 비교하면 signed/rounding/shift 오류 위치를 빠르게 찾을 수 있다.

### 11.5 전체 SRCNN

전체 연결 후 최종 1×1×32×32 INT16 출력 1,024개가 Golden과 일치하는지 확인한다. 합격 기준 예시는 다음과 같다.

```text
mismatch_count = 0
max_integer_error = 0 LSB
```

만약 설계 최적화 때문에 bit-accurate 일치를 포기한다면 허용오차 기준을 먼저 문서로 합의해야 한다.

---

## 12. 256×256 이미지 처리와 타일링

32×32 NPU를 256×256 전체에 적용한다면 출력 영역만 단순 계산했을 때 8×8, 총 64개 타일이다.

```text
256 / 32 = 8
8 × 8 = 64
```

하지만 32×32 패치를 서로 독립적으로 처리하면 타일 경계에서 잘못된 zero padding이 적용되어 경계선이나 이음새가 생길 수 있다. SRCNN의 전체 receptive field가 17×17이므로 정확한 내부 출력 타일을 만들려면 각 방향에 최대 8픽셀의 주변 영역(halo)이 필요하다.

예를 들어 내부 출력 32×32를 계산하려면 개념적으로 입력은 다음 크기가 필요하다.

```text
(32 + 8 + 8) × (32 + 8 + 8) = 48×48
```

전체 이미지의 실제 바깥 경계에만 zero padding을 적용하고, 내부 타일 경계에서는 이웃 픽셀을 공급해야 한다. 대안은 RTL 내부에서 line buffer를 사용해 전체 영상 스트림을 연속 처리하는 것이다.

따라서 256×256 확장 시에는 다음 중 하나를 선택한다.

1. 32×32 출력 타일 + 8픽셀 halo 입력
2. 타일 간 중첩 후 유효 중앙 영역만 결합
3. line buffer 기반 스트리밍 convolution

처리 횟수를 일부러 최대화하는 것이 목적은 아니다. 동일한 출력 품질을 유지하면서 latency, throughput, FPS, FPGA 자원, 전력 등을 비교해야 한다. 반복 횟수가 많으면 DMA/제어 오버헤드도 커진다.

---

## 13. Vivado 2024.2 프로젝트 계획

권장 디렉터리 구조는 다음과 같다.

```text
srcnn_npu_rtl/
├── rtl/
│   ├── src/          # 합성 대상 SystemVerilog
│   └── tb/           # 테스트벤치
├── data/             # RTL 입력 및 Golden .hex/.mem
├── constraints/      # XDC
└── scripts/          # Vivado Tcl 자동화(선택)
```

첫 단계는 보드와 무관한 Behavioral Simulation이다.

1. Vivado 2024.2에서 RTL Project 생성
2. `mac_pe.sv`를 Design Source로 추가
3. `tb_mac_pe.sv`를 Simulation Source로 추가
4. 테스트벤치를 simulation top으로 설정
5. Run Behavioral Simulation
6. MAC PASS 확인
7. Requantizer 및 Conv1 순서로 확장

그다음 단계는 다음과 같다.

```text
MAC
 ↓
Requantizer
 ↓
Conv1
 ↓
Conv2
 ↓
Conv3
 ↓
SRCNN Top/FSM/BRAM
 ↓
Synthesis / Implementation / Timing
```

프로젝트의 FPGA Part 선택과 실제 합성 전에는 보드가 ZYBO Z7-10인지 ZYBO Z7-20인지 확인해야 한다.

---

## 14. 추후 SoC 및 Vitis 2024.2 계획

RTL 단독 검증이 완료되면 Zynq Processing System과 NPU를 연결한다.

예상 데이터 경로는 다음과 같다.

```text
ARM Processing System
  ├─ AXI-Lite: start, done, width, height, status 등 제어 레지스터
  └─ AXI/DMA: 입력 이미지와 출력 이미지 전송
          ↓
      SRCNN NPU IP
          ↓
      DDR 또는 BRAM
```

Vivado 2024.2에서 bitstream 생성 후 하드웨어를 XSA로 내보내고, Vitis Unified IDE 2024.2에서 XSA를 바탕으로 Platform Component와 Application Component를 만든다.

초기 SoC 검증 프로그램의 역할은 다음과 같다.

1. `input_y` 정수 데이터를 메모리에 적재
2. NPU 레지스터와 DMA 설정
3. NPU 시작
4. 완료 대기
5. 출력 1,024개 수집
6. Golden 값과 비교
7. cycle count 또는 실행 시간 출력

---

## 15. 현재 완료 상태

- [x] pretrained FP32 SRCNN 실행
- [x] 이미지 x2 전처리 및 32×32 입력 확인
- [x] FP32 계층별 입력·가중치·bias·출력 dump
- [x] 값 범위와 shape 검사
- [x] 계층별 INT16 Q-format 결정
- [x] Python INT16 Golden Model 구현 및 실행
- [x] FP32와 INT16 출력 오차 및 PSNR 검증
- [x] NPY → HEX 변환
- [x] HEX round-trip 검증
- [x] `rtl_data/manifest.json` 생성
- [ ] MAC RTL 구현 및 단위 테스트
- [ ] Requantizer RTL 구현 및 단위 테스트
- [ ] Conv1 RTL과 Golden 비교
- [ ] Conv2 RTL과 Golden 비교
- [ ] Conv3 RTL과 Golden 비교
- [ ] 전체 SRCNN RTL 통합
- [ ] 합성, Implementation, Timing 분석
- [ ] Zynq PS/AXI/DMA 연결
- [ ] Vitis 애플리케이션 작성
- [ ] 256×256 타일링 또는 스트리밍 확장
- [ ] FPGA와 Python의 품질·속도 비교

---

## 16. 바로 다음 작업

1. 정확한 보드 모델(ZYBO Z7-10 또는 Z7-20)을 확인한다.
2. Vivado 2024.2 RTL 프로젝트를 생성한다.
3. `mac_pe.sv`와 `tb_mac_pe.sv`를 작성한다.
4. signed multiplication, bias load, INT48 accumulate 결과를 Behavioral Simulation으로 검증한다.
5. PASS 후 Python과 동일한 rounding 규칙을 갖는 `requantizer.sv`로 넘어간다.

RTL 구현 중 최우선 원칙은 **Python `int16_golden.py`의 연산 순서와 비트 규칙을 그대로 재현하는 것**이다.
