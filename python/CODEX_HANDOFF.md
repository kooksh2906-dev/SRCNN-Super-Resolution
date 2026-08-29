# SRCNN FPGA Rev5 Demo Handoff

## Objective

Complete the PC-side demo that selects a 128×128 LR or 256×256 evaluation
image, prepares 256 Halo Tiles, sends them to the Zybo Z7-20 over UART,
receives the INT16 SRCNN output, reconstructs a 256×256 SR image, and presents
the result in the Web UI.

## Repository role

This repository is the Team C PC/Python project. It owns image preprocessing,
Halo Tile generation, Rev5 UART communication, output merging, Golden
comparison, and the Web UI. Vivado and Vitis projects remain in the separate
Linux board environment.

Runtime commands must use the project virtual environment:

```bash
cd /home/user3/Downloads/pc_tools/srcnn-fpga-int16
.venv/bin/python --version
```

Verified runtime versions are Python 3.12.3, NumPy 2.5.2, Pillow 12.3.0, and
pyserial 3.5.

## Verified state

### Existing PC pipeline evidence

- On 2026-08-27, the pre-Rev5 full Python suite passed 47 unit/integration
  tests.
- A real `PythonInt16Backend` Web UI job completed all 256 Tiles.
- FP32 and INT16 Golden data are present.
- Tile/Halo, quantization, Python INT16, image reconstruction, and UI paths
  were already implemented.

### Rev5 PC/UART evidence completed on 2026-08-28

- `uart_protocol.py` was migrated from the old SNPU layout to the Rev5
  `SRQ1`/`SRS1` firmware contract.
- The targeted UART/Backend regression suite passed 14 tests after migration.
- Rev5 single-Tile Mock passed for Tile IDs 0, 17, and 255 with
  `mismatch=0/256` and `max_error=0 LSB`.
- Rev5 full 256-Tile Mock passed with zero Tile and merged mismatches.
- Mock traffic totals matched the contract: TX 529,408 Byte and RX 138,240
  Byte.
- Nominal Rev5 PL cycle count is 30,839,827 per Tile.
- `git diff --check` passed after the code and documentation updates completed
  so far.

### Rev5 hardware/firmware evidence already completed by Team A

- Vitis 2024.2 Platform/BSP was regenerated from the Rev5 XSA.
- NPU base `0x43C00000` and Input BRAM base `0x40000000` were confirmed in the
  generated `xparameters.h`.
- Rev5 BIT, XSA, `ps7_init.tcl`, and ELF were selected in the Vitis GUI Launch
  Configuration.
- Vitis GUI programming and execution succeeded.
- Board PING returned NPU VERSION `0x00010001`.
- Representative `TILE_POS` values from `0x00` through `0xFF` passed write,
  readback, START, and DONE handling.
- Interior Tiles `(1,1)` and `(8,8)` matched the existing INT16 Golden exactly.
- Boundary-Tile output changes followed the expected Global Boundary Mask
  directions.

These Team A checks prove the Rev5 hardware and firmware path. They do not
replace the pending physical-board test using Team C's `uart_single_tile_test.py`
and `uart_host.py`.

## Rev5 hardware and UART contract

- NPU register base: `0x43C00000`
- Input BRAM base: `0x40000000`
- `TILE_POS` register: NPU base + `0x20`
- NPU VERSION: `0x00010001`
- Completion: polling; normal DONE status `0x00000002`
- Input: 1,024 signed INT16 pixels, shape `(1,32,32)`
- Output: central 256 signed INT16 pixels, shape `(1,16,16)`
- Request: `SRQ1`, 20-Byte Header plus 2,048-Byte Payload = 2,068 Byte
- Response: `SRS1`, 28-Byte Header plus 512-Byte Payload = 540 Byte
- CRC32: Payload only, stored in the Header; no trailing CRC
- Coordinates: explicit `tile_x` and `tile_y` in every request
- Sequence: Team C uses and verifies `tile_id`
- UART: 115200 baud, 8-N-1

Do not select 460800 or 921600 in the PC program unless the AXI UART hardware
and Bitstream are regenerated for the same Baud Rate.

See `docs/uart_protocol.md` for the exact wire format.

## Next physical-board checkpoints

Run these in order on the Linux machine connected to the Zybo board.

### 1. Board and port preparation

- Keep `hw_server` running.
- Run the Rev5 Vitis GUI Launch Configuration once.
- Close moserial and every program that may own the UART port.

```bash
UART_DEV=/dev/serial/by-id/usb-Digilent_Digilent_Adept_USB_Device_210351BD7302-if01-port0
readlink -f "$UART_DEV"
fuser -v "$UART_DEV"
```

### 2. Team C single-Tile board test

```bash
.venv/bin/python uart_single_tile_test.py \
  --port "$UART_DEV" \
  --baud 115200 \
  --timeout 5 \
  --tile-id 0 \
  --output-dir uart_single_tile_results_rev5_board_000
```

Required result:

```text
NPU status       : 0x00000002
Golden mismatch  : 0/256
Max error        : 0 LSB
Result           : PASS
```

After Tile 0 passes, repeat with Tile IDs 17 and 255 using separate output
directories.

### 3. Team C full 256-Tile board test

Only after all representative single-Tile tests pass:

```bash
.venv/bin/python uart_host.py \
  --port "$UART_DEV" \
  --baud 115200 \
  --timeout 5 \
  --retries 1 \
  --output-dir uart_results_rev5_board
```

Required result: 256 Tiles completed, zero mismatched Tiles, zero merged
mismatch, zero maximum LSB error, and no missing or duplicate Tile response.

### 4. Web UI board test

Run the Web UI only after the full UART host test passes. Before launching,
inspect the current options with:

```bash
.venv/bin/python srcnn_web_ui.py --help
```

Select the Zybo UART Backend, the verified serial port, and 115200 baud. Verify
all 256 Tiles, final image reconstruction, and output saving.

## Important files

- `uart_protocol.py`: Rev5 SRQ1/SRS1 packet codec
- `uart_single_tile_test.py`: first Team C physical UART checkpoint
- `uart_host.py`: full 256-Tile UART test and merge
- `uart_mock.py`: Rev5 Mock board
- `srcnn_backend.py`: Python and Zybo Backend implementations
- `srcnn_pipeline.py`: common 256-Tile execution and merge
- `srcnn_demo_image.py`: image preparation and RGB reconstruction
- `srcnn_web_ui.py`: browser UI and job management
- `docs/uart_protocol.md`: exact Rev5 wire contract
- `docs/UART_HOST_README.md`: Mock and physical-board runbook

## Remaining completion conditions

- Run the complete Python test discovery after all Rev5 edits.
- Pass Team C single-Tile physical-board tests for representative boundary and
  interior Tiles.
- Pass Team C full 256-Tile physical-board execution and merged Golden
  comparison.
- Inspect the reconstructed image for black lines or Tile seams.
- Pass the Zybo UART Web UI flow.
- Preserve final logs, result directories, and final Git diff for handoff.
