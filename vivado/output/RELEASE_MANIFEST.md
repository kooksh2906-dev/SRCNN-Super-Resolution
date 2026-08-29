# Vivado Final Release

이 폴더의 BIT/XSA는 최종 실보드 검증에 사용된 공식 산출물이다.
개발 과정 명칭인 Rev5는 파일명에서 제거하고 Git 이력과 문서에서 관리한다.

## Hardware
- Board: Zybo Z7-20
- Device: XC7Z020
- Tool: Vivado 2024.2
- AXI NPU Base: 0x43C00000
- Input BRAM Base: 0x40000000
- TILE_POS Offset: 0x20
- NPU VERSION: 0x00010001

## Canonical artifacts
- SRCNN_NPU_wrapper.bit: 2b84f0a11c8292763724d8222ff261bd059acc14b567ad9009ad7063791adc38
- SRCNN_NPU_wrapper.xsa: 701064a853a2f3027ceb7d02df8f0dbdef6e732a0f29d3b0e109d11ed34eeb2f

## Verification
- Global Boundary Mask simulation: PASS
- Vitis PING: PASS
- Representative boundary/interior Tiles: mismatch 0
- Full 256-Tile board run: mismatch 0, retries 0

Files with different hashes are stored only in the external legacy archive.
