"""Send one 32x32 INT16 SRCNN Tile and compare the 16x16 response.

The real-board path uses the same Rev5 SRQ1/SRS1 protocol as ``uart_host.py``.  The
mock path makes the tool fully testable before it is moved to the board PC.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np

from uart_protocol import (
    RESPONSE_HEADER,
    RESPONSE_MAGIC,
    RESULT_PAYLOAD_BYTES,
    ProtocolError,
    Status,
    decode_packet,
    decode_tile_result,
    encode_run_tile,
    encode_tile_result,
)


DEFAULT_CYCLE_COUNT = 30_839_827


def read_exact(serial_port, size: int) -> bytes:
    data = bytearray()
    while len(data) < size:
        chunk = serial_port.read(size - len(data))
        if not chunk:
            raise TimeoutError(
                f'UART timeout: received {len(data)}/{size} bytes'
            )
        data.extend(chunk)
    return bytes(data)


def read_frame(serial_port) -> bytes:
    """Find SRS1 magic and read exactly one validated Rev5 response."""
    window = bytearray()
    while True:
        window.extend(read_exact(serial_port, 1))
        if len(window) > len(RESPONSE_MAGIC):
            del window[0]
        if bytes(window) == RESPONSE_MAGIC:
            break

    header = RESPONSE_MAGIC + read_exact(
        serial_port,
        RESPONSE_HEADER.size - len(RESPONSE_MAGIC),
    )
    fields = RESPONSE_HEADER.unpack(header)
    payload_length = fields[6]
    if payload_length > RESULT_PAYLOAD_BYTES:
        raise ProtocolError(
            f'response payload_length is too large: {payload_length}'
        )

    frame = header + read_exact(serial_port, payload_length)
    decode_packet(frame)
    return frame


def list_serial_ports() -> list[tuple[str, str]]:
    try:
        from serial.tools import list_ports
    except ImportError as error:
        raise RuntimeError(
            'pyserial is required. Install it with: python -m pip install pyserial'
        ) from error
    return [(port.device, port.description) for port in list_ports.comports()]


def serial_transaction(
    port: str,
    baud: int,
    timeout: float,
    request: bytes,
) -> bytes:
    try:
        import serial
    except ImportError as error:
        raise RuntimeError(
            'pyserial is required. Install it with: python -m pip install pyserial'
        ) from error

    with serial.Serial(
        port=port,
        baudrate=baud,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=timeout,
        write_timeout=timeout,
    ) as serial_port:
        serial_port.reset_input_buffer()
        serial_port.reset_output_buffer()
        written = serial_port.write(request)
        if written != len(request):
            raise TimeoutError(f'UART short write: {written}/{len(request)} bytes')
        serial_port.flush()
        return read_frame(serial_port)


def load_input_tile(path: Path, tile_id: int) -> np.ndarray:
    values = np.load(path)
    if not np.issubdtype(values.dtype, np.signedinteger):
        raise ValueError(
            f'input must be a signed integer array, got {values.dtype}'
        )

    if values.shape == (256, 1, 32, 32):
        selected = values[tile_id]
    elif values.size == 32 * 32:
        selected = values.reshape(1, 32, 32)
    else:
        raise ValueError(
            'input must be one 32x32 Tile or the complete '
            f'(256, 1, 32, 32) array, got shape={values.shape}'
        )

    return selected.astype(np.int16, copy=False).reshape(1, 32, 32)


def load_golden_valid(path: Path, tile_id: int) -> np.ndarray:
    values = np.load(path)
    if not np.issubdtype(values.dtype, np.signedinteger):
        raise ValueError(
            f'Golden must be a signed integer array, got {values.dtype}'
        )

    if values.shape == (256, 1, 32, 32):
        full = values[tile_id].astype(np.int16, copy=False)
        return full[:, 8:24, 8:24]

    if values.shape == (256, 1, 16, 16):
        return values[tile_id].astype(np.int16, copy=False)

    if values.size == 32 * 32:
        full = values.astype(np.int16, copy=False).reshape(1, 32, 32)
        return full[:, 8:24, 8:24]

    if values.size == 16 * 16:
        return values.astype(np.int16, copy=False).reshape(1, 16, 16)

    raise ValueError(
        'Golden must be one 32x32/16x16 Tile or a complete '
        f'256-Tile array, got shape={values.shape}'
    )


def save_results(
    output_dir: Path,
    actual: np.ndarray,
    golden: np.ndarray,
    summary: dict,
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    np.save(output_dir / 'actual_valid_int16.npy', actual)
    np.save(output_dir / 'golden_valid_int16.npy', golden)
    np.save(
        output_dir / 'difference_lsb.npy',
        actual.astype(np.int32) - golden.astype(np.int32),
    )
    with (output_dir / 'summary.json').open('w', encoding='utf-8') as file:
        json.dump(summary, file, ensure_ascii=False, indent=2)
        file.write('\n')


def main() -> int:
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description='SRCNN Current Wrapper single-Tile UART exact test.'
    )
    connection = parser.add_mutually_exclusive_group()
    connection.add_argument('--port', help='real board port, for example COM5')
    connection.add_argument(
        '--mock',
        action='store_true',
        help='return the Golden payload without opening a COM port',
    )
    parser.add_argument('--list-ports', action='store_true')
    parser.add_argument('--baud', type=int, default=115200)
    parser.add_argument('--timeout', type=float, default=5.0)
    parser.add_argument('--tile-id', type=int, default=0)
    parser.add_argument(
        '--input',
        type=Path,
        default=root / 'full_image_data' / 'input_tiles_int16.npy',
    )
    parser.add_argument(
        '--golden',
        type=Path,
        default=root / 'full_image_golden' / 'output_tiles_int16.npy',
    )
    parser.add_argument(
        '--output-dir',
        type=Path,
        default=root / 'uart_single_tile_results',
    )
    args = parser.parse_args()

    if args.list_ports:
        ports = list_serial_ports()
        if not ports:
            print('No serial ports found.')
        for device, description in ports:
            print(f'{device}: {description}')
        return 0

    if bool(args.port) == bool(args.mock):
        parser.error('choose exactly one of --port COMx or --mock')
    if not 0 <= args.tile_id <= 255:
        parser.error('--tile-id must be in [0, 255]')
    if args.baud <= 0:
        parser.error('--baud must be positive')
    if args.timeout <= 0:
        parser.error('--timeout must be positive')

    input_tile = load_input_tile(args.input, args.tile_id)
    golden_valid = load_golden_valid(args.golden, args.tile_id)
    request = encode_run_tile(args.tile_id, input_tile)

    started = time.perf_counter()
    if args.mock:
        response = encode_tile_result(
            args.tile_id,
            golden_valid,
            cycle_count=DEFAULT_CYCLE_COUNT,
            status=Status.OK,
        )
        mode = 'mock'
    else:
        response = serial_transaction(
            args.port,
            args.baud,
            args.timeout,
            request,
        )
        mode = 'serial'
    elapsed = time.perf_counter() - started

    packet, actual = decode_tile_result(response)
    if packet.tile_id != args.tile_id:
        raise ProtocolError(
            f'response Tile ID mismatch: {packet.tile_id} != {args.tile_id}'
        )
    if packet.status != Status.OK or actual is None:
        raise ProtocolError(f'board returned status={packet.status.name}')

    difference = actual.astype(np.int32) - golden_valid.astype(np.int32)
    mismatch_count = int(np.count_nonzero(difference))
    max_error_lsb = int(np.max(np.abs(difference)))
    passed = mismatch_count == 0
    summary = {
        'mode': mode,
        'port': args.port,
        'baud': args.baud if mode == 'serial' else None,
        'tile_id': args.tile_id,
        'request_bytes': len(request),
        'response_bytes': len(response),
        'cycle_count': packet.cycle_count,
        'npu_status': packet.npu_status,
        'elapsed_seconds': elapsed,
        'mismatch_count': mismatch_count,
        'max_error_lsb': max_error_lsb,
        'pass': passed,
    }

    save_results(args.output_dir, actual, golden_valid, summary)

    print('Mode             :', mode)
    print('Tile ID          :', args.tile_id)
    print('Request bytes    :', len(request))
    print('Response bytes   :', len(response))
    print('Cycle count      :', packet.cycle_count)
    print('NPU status       :', f'0x{packet.npu_status:08X}')
    print('Elapsed          :', f'{elapsed:.3f}s')
    print('Golden mismatch  :', f'{mismatch_count}/256')
    print('Max error        :', max_error_lsb, 'LSB')
    if not passed:
        first = tuple(int(v) for v in np.argwhere(difference != 0)[0])
        print('First mismatch   : index', first)
        print('Expected / actual:', int(golden_valid[first]), '/', int(actual[first]))
    print('Result           :', 'PASS' if passed else 'FAIL')
    print('Saved            :', args.output_dir.resolve())
    return 0 if passed else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, TimeoutError, ProtocolError, ValueError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        raise SystemExit(2) from error
