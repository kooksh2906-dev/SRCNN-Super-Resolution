# B 인수인계: NPU signed MAC·PE4 Compute Core

## 1. B의 책임 범위

- signed 16×16 multiply
- signed INT32 product
- signed INT32 Bias를 INT48로 sign extension
- Bias Load와 Accumulator Clear
- signed INT48 accumulation
- PE 1개와 4-PE Array
- PE Mask와 result valid/busy/done
- Conv1/2/3 Bias 포함 accumulator Golden 비교

B의 최종 출력은 4×signed INT48 accumulator이다. Requantization, ReLU,
Saturation, Clamp, 주소 및 Padding 제어는 A의 책임이다.

## 2. 수치 계약

```text
Activation  : signed INT16
Weight      : signed INT16
Product     : signed INT32
Bias        : signed INT32
Accumulator : signed INT48

acc = sign_extend_32_to_48(bias)
acc = acc + sign_extend_32_to_48(activation * weight)
```

SystemVerilog/Verilog에서 Activation과 Weight, Product, Accumulator가 모두
signed로 선언됐는지 확인한다. unsigned 연산이 섞이면 음수 Test가 실패한다.

## 3. 가장 먼저 할 일

1. PE 1개의 Bias Load와 signed MAC 구현
2. `directed_mac` 15개 Case 및 1,694개 Step mismatch=0
3. 4-PE Array 구현
4. A가 공급하는 operand stream으로 Conv1 accumulator mismatch=0
5. Conv2 accumulator mismatch=0
6. Conv3 accumulator mismatch=0

Requantizer나 전체 Controller보다 MAC exact를 먼저 통과한다.

## 4. MAC Directed Vector

```text
mac_bias.hex           Case별 signed INT32 Bias
mac_term_offset.hex    Case별 첫 term 주소
mac_term_count.hex     Case별 MAC 횟수
mac_activation.hex     signed INT16 Activation
mac_weight.hex         signed INT16 Weight
mac_step_expected.hex  각 MAC 직후 signed INT48 기대값
mac_final_expected.hex Case 최종 signed INT48 기대값
```

Testbench 채점 순서:

```text
for case_id:
    acc = sign_extend_32_to_48(mac_bias[case_id])
    offset = mac_term_offset[case_id]

    for i = 0 .. mac_term_count[case_id]-1:
        product = signed(mac_activation[offset+i]) * signed(mac_weight[offset+i])
        acc = acc + sign_extend_32_to_48(product)
        assert acc == mac_step_expected[offset+i]

    assert acc == mac_final_expected[case_id]
```

`mac_cases.json/csv`에 각 Case의 설명과 사람이 읽을 수 있는 값이 있다.

반드시 통과할 항목:

- 양수×양수, 양수×음수, 음수×음수
- INT16_MIN/MAX 곱셈
- INT32_MIN/MAX Bias sign extension
- INT32 범위를 넘는 INT48 누산
- 9×9 81항 stress
- 64×5×5 1,600항 stress

## 5. Single Tile Tensor 주소 순서

Activation 입력과 accumulator 출력은 NCHW C-order이다.

```text
activation_addr = input_channel * 1024 + y * 32 + x
accumulator_addr = output_channel * 1024 + y * 32 + x
```

Weight 원본은 OIHW C-order이며 Kernel flip이 없다.

```text
weight_addr = (((oc * input_channels) + ic) * kernel_h + ky) * kernel_w + kx
```

Layer별 MAC 수:

```text
Conv1 output 한 점: 1×9×9   = 81 MAC
Conv2 output 한 점: 64×5×5 = 1,600 MAC
Conv3 output 한 점: 32×5×5 = 800 MAC
```

`conv*_acc_expected.hex`는 Bias가 이미 포함된 signed INT48 결과다.

## 6. 계층별 Golden 사용

```text
Conv1:
input_y.hex + conv1_weight.hex + conv1_bias.hex
→ conv1_acc_expected.hex

Conv2:
relu1_expected.hex + conv2_weight.hex + conv2_bias.hex
→ conv2_acc_expected.hex

Conv3:
relu2_expected.hex + conv3_weight.hex + conv3_bias.hex
→ conv3_acc_expected.hex
```

최초 mismatch가 발생한 `(output_channel, y, x)` 한 점의 `ic,ky,kx` 누산 과정을
추적한다.

## 7. PE4 Packed Weight 계약

Packed Weight 주소 순서:

```text
output_channel_group → input_channel → kernel_y → kernel_x
```

64-bit Word:

```text
[63:48] PE3 / oc_group*4+3
[47:32] PE2 / oc_group*4+2
[31:16] PE1 / oc_group*4+1
[15: 0] PE0 / oc_group*4+0
```

Conv3는 PE0만 enable하고 PE1~PE3 Weight는 0이다.

Word 수:

```text
Conv1: 1,296
Conv2: 12,800
Conv3: 800
```

먼저 원본 16-bit Weight로 PE 1개를 검증하고, PE4 인터페이스가 동결된 뒤 Packed
Weight ROM을 연결한다.

## 8. A-B 인터페이스 기준

A → B:

```text
op_start, bias_load, mac_valid, mac_last, pe_enable[3:0]
signed INT16 activation 1개
signed INT16 weight 4개
signed INT32 bias 4개
```

B → A:

```text
busy, acc_valid, core_done
signed INT48 accumulator 4개
```

정확한 포트명과 cycle timing은 A/B가 RTL 작성 전에 공동 동결한다.

## 9. 통과 기준

```text
Directed MAC 모든 Step mismatch = 0
Conv1 accumulator mismatch = 0
Conv2 accumulator mismatch = 0
Conv3 accumulator mismatch = 0
INT48 overflow = 0
```

전체 이미지 Boundary Mask, Requantizer, UART는 B Core의 책임 밖이다.
`quant_spec.json`, 각 manifest, 최상위 `PACKAGE_SHA256.txt`로 전달 파일을 확인한다.
