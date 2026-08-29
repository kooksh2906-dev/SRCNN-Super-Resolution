# RTL Directed Test Vector 사용법

## 1. 목적

전체 convolution보다 먼저 MAC, Bias sign extension, INT48 accumulation,
rounding, shift, ReLU, saturation, clamp를 작은 입력으로 검증한다.

```powershell
python generate_directed_vectors.py
```

모든 결과는 `directed_vectors`에 생성된다.

## 2. MAC Vector

Case별 정보:

- `mac_cases.json`: 전체 입력과 각 MAC 이후 기대 누산값
- `mac_cases.csv`: Case 요약
- `mac_bias.hex`: Case당 signed INT32 Bias 하나
- `mac_term_offset.hex`: Case의 첫 activation/weight 주소
- `mac_term_count.hex`: Case의 MAC 횟수
- `mac_activation.hex`: signed INT16 Activation
- `mac_weight.hex`: signed INT16 Weight
- `mac_step_expected.hex`: 각 MAC 이후 signed INT48 기대값
- `mac_final_expected.hex`: Case 최종 signed INT48 기대값

Testbench 동작:

```text
for case_id:
    acc = sign_extend_32_to_48(bias[case_id])
    offset = term_offset[case_id]

    for i in range(term_count[case_id]):
        acc += signed(activation[offset+i]) * signed(weight[offset+i])
        assert acc == step_expected[offset+i]

    assert acc == final_expected[case_id]
```

## 3. Requant Vector

- `requant_accumulator.hex`: signed INT48 입력
- `requant_shift.hex`: shift 14 또는 16
- `requant_mode.hex`: `1=ReLU`, `2=Clamp 0..32767`
- `requant_round_expected.hex`: activation 전 raw rounder 결과
- `requant_output_expected.hex`: 최종 INT16 결과
- `requant_cases.json`: 각 Case 설명
- `requant_cases.csv`: 사람이 확인하기 위한 표

각 파일의 같은 줄이 하나의 Case다.

```text
accumulator[index]
shift[index]
mode[index]
    ↓
round-to-nearest, ties-away-from-zero
    ↓
ReLU 또는 Clamp
    ↓
output_expected[index]
```

## 4. HEX 형식

- INT16: 4자리 two's complement
- INT32: 8자리 two's complement
- INT48: 12자리 two's complement
- 한 줄에 한 값
- `0x` prefix 없음
- `$readmemh()`로 읽을 수 있음

## 5. 반드시 통과할 Case

- 양수×양수, 양수×음수, 음수×음수
- `INT16_MIN/MAX` 곱셈
- 음수 Bias의 INT48 sign extension
- 누산 결과가 INT32 범위를 넘는 Case
- 9×9 81항, 64×5×5 1,600항 stress
- 양수·음수 Half-LSB ties-away rounding
- shift 14/16
- ReLU 음수→0
- INT16 상한 saturation
- Conv3 clamp 0~32767

`manifest.json`의 SHA-256과 `round_trip_verified=true`를 전달 전 확인한다.
