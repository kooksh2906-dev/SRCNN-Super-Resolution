# SRCNN Super-Resolution

ZYBO Z7-20 기반 INT16 4-PE SRCNN Super-Resolution NPU 프로젝트입니다.

## 디렉터리

| 경로 | 내용 |
| --- | --- |
| `spec/` | RTL·Python·SoC가 공유하는 인터페이스 및 수치 명세 |
| `vectors/` | 원본 벡터, 패킹된 가중치, 전체 이미지 Tile/Halo 데이터 |
| `rtl/a_control_numeric_soc/` | 제어·주소·후처리·AXI·NPU Top RTL |
| `rtl/b_compute_core/` | MAC·PE·4-PE Array·누산 Core RTL |
| `tb/` | Unit, Layer, Full RTL 테스트벤치 |
| `python/` | 전처리·Tile/Halo·Weight Packing·UART·병합·평가·GUI |
| `vivado/` | Block Design, Tcl, Constraints 및 빌드 산출물 관리 |
| `vitis/` | NPU Driver와 UART Firmware |
| `results/` | 일별 검증, Regression, Board 및 QoR 결과 |
| `docs/` | 일일 기록, 문제 해결, 시연 및 발표 자료 |

## 브랜치 규칙

- `main`: 검증 Gate를 통과한 안정 버전과 최종 제출본
- `dev`: 역할 A/B/C의 일일 통합 및 Regression 기준
- `feature/a-*`: 제어·수치·SoC 개발
- `feature/b-*`: Compute Core 개발
- `feature/c-*`: Python 및 Vector 개발

기능은 역할별 feature 브랜치에서 개발하고 `dev`에서 공동 검증한 뒤, Gate를 통과한 결과만 `main`에 반영합니다.

## RTL 규칙

- Verilog-2001 (`.v`)을 우선 사용합니다.
- 공용 인터페이스와 수치 규칙은 구현보다 먼저 `spec/`에서 확정합니다.
- 생성 벡터는 `vectors/`, 검증 로그와 측정 결과는 `results/`에 저장합니다.

