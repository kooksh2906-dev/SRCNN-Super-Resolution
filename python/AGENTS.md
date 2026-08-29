# SRCNN Project Agent Guide

## Scope

- This repository is the PC/Python side of the SRCNN INT16 FPGA demo.
- Treat `quant_spec.json`, `uart_protocol.py`, and the documented Tile shapes as hardware contracts.
- Vivado and Vitis projects are maintained in the board environment and are not duplicated here.

## Fixed contracts

- Input image flow: LR RGB 128×128 → Bicubic 256×256 → Y Q15.
- FPGA request: explicit `tile_x`/`tile_y` plus signed INT16 `(1, 32, 32)`; Sequence echoes `tile_id`.
- FPGA response: signed INT16 valid center `(1, 16, 16)`.
- Full frame: 256 Tiles arranged as a 16×16 grid.
- UART: Rev5 `SRQ1`/`SRS1` v1, little-endian, Payload CRC32, 115200 baud.
- The Rev5 Wrapper uses polling, writes `TILE_POS(0x20)` before START, and exposes the final output through read-address/read-data registers.

## Development rules

- Keep UI code independent from inference implementation through `SrcnnBackend`.
- Maintain both `PythonInt16Backend` and `ZyboUartBackend` behavior.
- Do not change quantization, rounding, saturation, Tile order, Halo size, or packet layout without updating tests and documentation together.
- Use repository-relative paths and Linux-compatible commands in new documentation.
- Do not commit virtual environments, caches, logs, or generated UART result folders.

## Verification

Run before committing:

```bash
.venv/bin/python -m unittest discover -s . -p "test_*.py"
.venv/bin/python uart_single_tile_test.py --mock --tile-id 0 --output-dir /tmp/srcnn_uart_single_mock
.venv/bin/python uart_host.py --mock --output-dir /tmp/srcnn_uart_full_mock
```

When a board is available, follow `docs/UART_SINGLE_TILE_BOARD_TEST.md` and do not run the full UI until the single-Tile test passes exactly.
