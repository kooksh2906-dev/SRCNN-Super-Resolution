# A–B Interface Contract

역할 A의 제어·주소·후처리 블록과 역할 B의 Compute Core 사이의 공용 계약 문서입니다.

## 확정 전 체크리스트

- Clock 및 Reset 극성
- 입력·가중치·Bias 데이터 폭과 signed 규칙
- Valid/Ready 또는 Start/Done Handshake
- INT48 누산 결과 전달 규칙
- Feature Map 및 Weight 주소 순서
- Layer별 Padding, Stride, Channel 순회 순서
- Requant·ReLU·Clamp 적용 위치
- 에러 및 Timeout 동작

> 포트 이름, 폭, 타이밍은 팀 합의 후 이 문서에서 동결합니다.

