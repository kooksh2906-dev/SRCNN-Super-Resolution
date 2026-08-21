# AXI Register Map

PS와 NPU 사이의 AXI 제어 Register 계약 문서입니다.

## 확정 전 체크리스트

- Base address와 address width
- Control, Status, Interrupt register
- Input/output/weight/bias buffer address
- Tile 크기, Halo, Layer configuration
- Start/Done/Busy/Error bit 정의
- 쓰기 가능 여부와 Reset value

> 주소, bit field, 접근 속성은 Vivado Address Editor 결과와 함께 이 문서에서 동결합니다.

