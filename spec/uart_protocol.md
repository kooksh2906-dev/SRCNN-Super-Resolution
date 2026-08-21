# UART Protocol

PC Host와 Zynq 시스템 사이의 UART Packet 계약 문서입니다.

## 확정 전 체크리스트

- Baud rate, data bits, parity, stop bits
- Packet header 및 version
- Command ID와 payload length
- Tile/Halo 입력 및 출력 전송 순서
- CRC 또는 checksum
- ACK/NACK, timeout, retry 정책
- Error code

> Byte 단위 Packet 표와 상태 전이는 팀 합의 후 이 문서에서 동결합니다.

