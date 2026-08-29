# SRCNN PC/Python Final Release

## 범위

이 디렉터리는 최종 SRCNN Super-Resolution 시연에 사용하는 PC 전처리·후처리,
Python INT16 Golden, UART Host, Mock 보드, Web UI, 검증 데이터와 테스트를 제공한다.

## Source 기준

- 원본 프로젝트: Team C `srcnn-fpga-int16`
- 원본 Git HEAD: `99d95667d54f8773ddbc6a83a057fb1c2959b296`
- 통합 기준: 원본 HEAD와 Rev5 UART working-tree 수정사항
- 최종 검증 Python: `3.12.3`
- 최종 위치: 통합 저장소의 `python/`

## 최종 UART 계약

| 항목 | 값 |
|---|---|
| UART | PS UART1, 115200 baud, 8N1 |
| 요청 Magic | `SRQ1` |
| 응답 Magic | `SRS1` |
| 요청 크기 | 2,068 Byte |
| 정상 응답 크기 | 540 Byte |
| 입력 | signed INT16 32×32 Halo Tile |
| 출력 | signed INT16 중앙 16×16 |
| Tile 순서 | row-major, 총 256개 |
| NPU VERSION | `0x00010001` |
| 정상 NPU Status | `0x00000002` |

## 검증 결과

- Python 전체 회귀 테스트: 48 tests PASS
- 대표 Single-Tile Mock: Tile 0, 17, 255 exact PASS
- 전체 256-Tile Mock: Tile mismatch 0, merged mismatch 0, retry 0
- 대표 실보드 Tile 0, 17, 255: Golden exact PASS
- 전체 실보드 256-Tile: Golden byte-identical PASS
- 실보드 검증 근거: `../vitis/docs/board_validation.md`

## 제외한 이전·중복 산출물

- `.git/`, `.venv/`, `__pycache__/`
- `uart_results*/`, `uart_single_tile_results*/`
- 중복 `data/demo_candidates.zip`
- 2026-08-21 A/B 전달 ZIP 패키지
- 구형 Packet 계약의 `docs/UART_SINGLE_TILE_BOARD_TEST.md`
- 존재하지 않는 MVP 입력을 기본값으로 사용하던 구형 `test.py`

## 실행 기준

- 환경 구성과 Web UI: `README.md`
- UART Host 및 실보드 실행: `docs/UART_HOST_README.md`
- Binary Packet 계약: `docs/uart_protocol.md`
- Backend 구조: `docs/BACKEND_ARCHITECTURE.md`
