# SRCNN Final Board Validation

- 검증일: 2026-08-28
- 보드: Zybo Z7-20
- UART: PS UART1, 115200 baud, 8N1
- 완료 방식: DONE polling

## Release 식별자

| 산출물 | SHA-256 |
|---|---|
| BIT | `2b84f0a11c8292763724d8222ff261bd059acc14b567ad9009ad7063791adc38` |
| XSA | `701064a853a2f3027ceb7d02df8f0dbdef6e732a0f29d3b0e109d11ed34eeb2f` |
| Application ELF | `bcd84c278759cb78de60d26663995bd35570e7fbd26e8aa1a4944bb23becdaee` |
| FSBL | `235717926f324ab7c2cd6e13a7afdac17dd45a747f93da6f8bd5d6a5e41b142c` |

XSA 내부 BIT와 외부 BIT는 byte-identical이다.

## PING

```text
PING PASS: NPU_VERSION=0x00010001 STATUS=0x00000000
```

## 대표 타일 검증

| Tile ID | 좌표 | 구분 | Mismatch | Max Error | NPU Status |
|---:|---:|---|---:|---:|---:|
| 0 | (0,0) | 좌상단 경계 | 0/256 | 0 LSB | `0x00000002` |
| 17 | (1,1) | 내부 | 0/256 | 0 LSB | `0x00000002` |
| 255 | (15,15) | 우하단 경계 | 0/256 | 0 LSB | `0x00000002` |

세 타일 모두 다음 조건을 만족했다.

- Request: 2068 Byte
- Response: 540 Byte
- PL Cycle Count: `30,839,827`
- Golden 비교: 256/256 sample exact

## 전체 256타일 검증

```text
Tile count       : 256
Mismatch Tiles   : 0
Merged Mismatch  : 0
Max Error        : 0 LSB
Retries          : 0
TX bytes         : 529408
RX bytes         : 138240
Total PL cycles  : 7894995712
Elapsed          : 139.259 s
```

전체 256×256 병합 결과는 Python INT16 Golden과 byte-identical이다.

병합 INT16 결과 SHA-256:

```text
dc45b579efeb4c1063ee44d2d33d9df84a5ad6043d442c54d437b7307aa9cd74
```

Mismatch Log는 빈 배열이며 타일 누락, 중복 및 재시도가 발생하지 않았다.

## 회귀 검증

- Python 전체 회귀 테스트: 48 tests PASS
- Global Boundary Mask RTL Simulation: PASS
- TILE_POS 대표 좌표 Write/Readback: PASS
- NPU VERSION `0x00010001`: PASS
- 경계·내부 대표 타일 Golden exact: PASS
- 전체 256타일 Golden exact: PASS

## 최종 완료 판정

- Conv1/Conv2 Global Boundary Mask 정상 동작
- Tile 좌표가 UART에서 TILE_POS까지 정확히 전달
- NPU Status `0x00000002` 확인
- 256타일 전송 중 CRC·Timeout·Retry 오류 없음
- 최종 영상의 타일 경계선 및 검은 Seam 없음
- 최종 실보드 시연 완료
