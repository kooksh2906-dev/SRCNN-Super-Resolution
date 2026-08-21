# A–B Interface Contract

- Document Version: 1.0
- Status: Review Required
- Target: ZYBO Z7-20, PL 100 MHz
- RTL: Verilog-2001
- Owner: Role A / Role B
- Frozen Date: TBD

## 1. 역할 경계

역할 A는 계산할 위치와 데이터를 선택하여 역할 B에 전달한다.

역할 B는 전달받은 Activation과 Weight를 4개의 PE에서 곱하고, Bias를 포함하여 signed INT48 값으로 누산한 뒤 역할 A에 반환한다.

- 역할 A: Layer 순서, 주소, Padding, Memory, Requant, ReLU, Clamp 담당
- 역할 B: signed MAC, Bias Load, 4-PE 누산, INT48 결과 담당
- 역할 B의 출력에는 Bias가 이미 포함되어 있어야 한다.
- 역할 A는 B가 반환한 INT48 결과에 Layer별 후처리를 적용한다.

## 2. 공통 데이터 규칙

| 데이터 | 형식 | 설명 |
| --- | --- | --- |
| Activation | signed INT16 | A가 B에 전달하는 입력값 |
| Weight | signed INT16 | PE별 곱셈 가중치 |
| Bias | signed INT32 | 출력 채널별 초기 누산값 |
| Product | signed INT32 | INT16 × INT16 곱셈 결과 |
| Accumulator | signed INT48 | Bias와 모든 Product의 누산 결과 |
| Post Output | signed INT16 | A의 Requant·ReLU·Clamp 결과 |

모든 signed 데이터는 2의 보수로 표현한다.

## 3. A에서 B로 전달하는 포트

| 포트 | 폭 | 의미 |
| --- | ---: | --- |
| `clk_i` | 1 | PL 동작 Clock |
| `rst_n_i` | 1 | Active-Low Reset |
| `op_start_i` | 1 | 새로운 출력 채널 그룹 계산 시작 |
| `bias_load_i` | 1 | Bias를 INT48 Accumulator에 적재 |
| `mac_valid_i` | 1 | 현재 Activation과 Weight가 유효함 |
| `mac_last_i` | 1 | 현재 값이 마지막 MAC 입력임 |
| `pe_enable_i` | 4 | 사용할 PE 선택 |
| `activation_i` | 16 | 4개 PE에 공통 전달되는 signed INT16 입력 |
| `weight_pe0_i` | 16 | PE0 signed INT16 Weight |
| `weight_pe1_i` | 16 | PE1 signed INT16 Weight |
| `weight_pe2_i` | 16 | PE2 signed INT16 Weight |
| `weight_pe3_i` | 16 | PE3 signed INT16 Weight |
| `bias_pe0_i` | 32 | PE0 signed INT32 Bias |
| `bias_pe1_i` | 32 | PE1 signed INT32 Bias |
| `bias_pe2_i` | 32 | PE2 signed INT32 Bias |
| `bias_pe3_i` | 32 | PE3 signed INT32 Bias |

## 4. B에서 A로 반환하는 포트

| 포트 | 폭 | 의미 |
| --- | ---: | --- |
| `busy_o` | 1 | B가 현재 계산 중임 |
| `acc_valid_o` | 1 | 4개 INT48 결과가 유효함 |
| `core_done_o` | 1 | 현재 출력 채널 그룹 계산 완료 |
| `acc_pe0_o` | 48 | PE0 signed INT48 누산 결과 |
| `acc_pe1_o` | 48 | PE1 signed INT48 누산 결과 |
| `acc_pe2_o` | 48 | PE2 signed INT48 누산 결과 |
| `acc_pe3_o` | 48 | PE3 signed INT48 누산 결과 |

## 5. 계산 순서

1. B의 `busy_o=0`인 것을 A가 확인한다.
2. A가 `op_start_i=1`을 한 Clock 동안 출력한다.
3. B는 기존 누산값을 초기화하고 `busy_o=1`로 변경한다.
4. 다음 Clock에 A가 `bias_load_i=1`을 출력한다.
5. B는 signed INT32 Bias를 signed INT48로 부호 확장하여 Accumulator에 저장한다.
6. A는 유효한 Activation과 Weight를 공급하면서 `mac_valid_i=1`을 출력한다.
7. B는 활성화된 PE마다 `Accumulator = Accumulator + Activation × Weight`를 수행한다.
8. 마지막 MAC 입력에서는 `mac_valid_i=1`과 `mac_last_i=1`을 동시에 출력한다.
9. B는 마지막 곱셈까지 포함한 INT48 결과를 출력한다.
10. 결과가 유효한 한 Clock 동안 `acc_valid_o=1`, `core_done_o=1`을 출력한다.
11. 계산이 끝나면 `busy_o=0`으로 돌아간다.

## 6. Handshake 규칙

- `op_start_i`는 반드시 `busy_o=0`일 때만 1로 설정한다.
- `bias_load_i`는 출력 채널 그룹마다 한 번만 사용한다.
- `mac_last_i=1`일 때는 반드시 `mac_valid_i=1`이어야 한다.
- B는 `mac_valid_i=1`인 매 Clock마다 MAC 입력 하나를 받아들인다.
- A는 `mac_valid_i=1`인 Clock 동안 Activation과 Weight를 안정적으로 유지한다.
- `acc_valid_o`와 `core_done_o`는 결과가 준비된 한 Clock 동안만 1로 출력한다.
- Reset이 입력되면 Busy, Valid, Done과 모든 Accumulator를 0으로 초기화한다.
- `busy_o=1`일 때 새로운 `op_start_i`를 입력하지 않는다.

## 7. PE와 출력 채널 관계

| PE | 출력 채널 |
| --- | --- |
| PE0 | `oc_base + 0` |
| PE1 | `oc_base + 1` |
| PE2 | `oc_base + 2` |
| PE3 | `oc_base + 3` |

- Conv1과 Conv2는 기본적으로 `pe_enable_i=4'b1111`을 사용한다.
- 마지막 출력 채널 그룹에서 존재하지 않는 채널의 PE는 0으로 비활성화한다.
- Conv3는 출력 채널이 1개이므로 `pe_enable_i=4'b0001`을 사용한다.
- 비활성화된 PE의 출력값은 0으로 정의한다.

## 8. Tensor와 주소 순서

### Activation

Activation은 NCHW 순서의 signed INT16 데이터이다.

```text
activation_addr = channel × 1024 + y × 32 + x