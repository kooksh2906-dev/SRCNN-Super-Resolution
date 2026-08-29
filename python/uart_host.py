"""PC UART Master: 256개 SRCNN Tile을 Stop-and-Wait 방식으로 실행한다."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Protocol

import numpy as np
from PIL import Image

from uart_mock import MockZybo, merge_valid_tiles
from uart_protocol import (
    RESPONSE_HEADER,
    RESPONSE_MAGIC,
    RESULT_PAYLOAD_BYTES,
    ProtocolError,
    Status,
    decode_packet,
    decode_tile_result,
    encode_run_tile,
)


class Transport(Protocol):
    def transact(self, request: bytes) -> bytes:
        ...

    def close(self) -> None:
        ...


def read_exact(serial_port, size: int) -> bytes:
    """Serial read가 잘게 나뉘어 반환되어도 정확히 size Byte를 모은다."""
    data = bytearray()
    while len(data) < size:
        chunk = serial_port.read(size - len(data))
        if not chunk:
            raise TimeoutError(f'UART timeout: received {len(data)}/{size} bytes')
        data.extend(chunk)
    return bytes(data)


def read_frame(serial_port) -> bytes:
    """SRS1 Magic을 찾아 Rev5 응답 프레임 한 개를 읽고 검증한다."""
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


class SerialTransport:
    def __init__(self, port: str, baudrate: int, timeout: float):
        try:
            import serial
        except ImportError as error:
            raise RuntimeError(
                'pyserial is required for real UART. Install it with: '
                'python -m pip install pyserial'
            ) from error

        self.serial = serial.Serial(
            port=port,
            baudrate=baudrate,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=timeout,
            write_timeout=timeout,
        )
        self.serial.reset_input_buffer()
        self.serial.reset_output_buffer()

    def transact(self, request: bytes) -> bytes:
        written = self.serial.write(request)
        if written != len(request):
            raise TimeoutError(f'UART short write: {written}/{len(request)} bytes')
        self.serial.flush()
        return read_frame(self.serial)

    def close(self) -> None:
        self.serial.close()


class MockTransport:
    def __init__(self, board: MockZybo):
        self.board = board

    def transact(self, request: bytes) -> bytes:
        return self.board.transact(request)

    def close(self) -> None:
        pass


def list_serial_ports() -> list[tuple[str, str]]:
    try:
        from serial.tools import list_ports
    except ImportError as error:
        raise RuntimeError(
            'pyserial is required to list COM ports. Install it with: '
            'python -m pip install pyserial'
        ) from error
    return [(port.device, port.description) for port in list_ports.comports()]


def run_session(
    transport: Transport,
    input_tiles: np.ndarray,
    *,
    golden_output_tiles: np.ndarray | None = None,
    merged_expected: np.ndarray | None = None,
    retries: int = 1,
    progress_interval: int = 16,
) -> tuple[np.ndarray, dict, list[dict]]:
    if input_tiles.shape != (256, 1, 32, 32):
        raise ValueError(f'expected input shape (256, 1, 32, 32), got {input_tiles.shape}')
    if retries < 0:
        raise ValueError('retries must be non-negative')

    golden_valid = None
    if golden_output_tiles is not None:
        if golden_output_tiles.shape != (256, 1, 32, 32):
            raise ValueError(f'bad Golden output shape: {golden_output_tiles.shape}')
        golden_valid = golden_output_tiles[:, :, 8:24, 8:24]

    received = np.empty((256, 1, 16, 16), dtype=np.int16)
    mismatch_log: list[dict] = []
    total_tx_bytes = 0
    total_rx_bytes = 0
    total_cycles = 0
    retry_count = 0
    started = time.perf_counter()

    for tile_id in range(256):
        request = encode_run_tile(
            tile_id,
            input_tiles[tile_id],
            last_tile=(tile_id == 255),
        )

        last_error: Exception | None = None
        for attempt in range(retries + 1):
            try:
                response = transport.transact(request)
                packet, result = decode_tile_result(response)
                if packet.tile_id != tile_id:
                    raise ProtocolError(
                        f'response Tile ID mismatch: {packet.tile_id} != {tile_id}'
                    )
                if packet.status != Status.OK or result is None:
                    raise ProtocolError(f'Tile {tile_id} failed: {packet.status.name}')
                break
            except (ProtocolError, TimeoutError, OSError) as error:
                last_error = error
                if attempt == retries:
                    raise RuntimeError(
                        f'Tile {tile_id} failed after {retries + 1} attempts'
                    ) from error
                retry_count += 1
        else:
            raise RuntimeError(f'Tile {tile_id} failed') from last_error

        received[tile_id] = result
        total_tx_bytes += len(request)
        total_rx_bytes += len(response)
        total_cycles += packet.cycle_count

        if golden_valid is not None:
            difference = result.astype(np.int64) - golden_valid[tile_id].astype(np.int64)
            mismatch_count = int(np.count_nonzero(difference))
            if mismatch_count:
                first = tuple(int(v) for v in np.argwhere(difference != 0)[0])
                mismatch_log.append({
                    'tile_id': tile_id,
                    'tile_x': tile_id % 16,
                    'tile_y': tile_id // 16,
                    'mismatch_count': mismatch_count,
                    'max_error_lsb': int(np.max(np.abs(difference))),
                    'first_index_ch_y_x': list(first),
                    'expected': int(golden_valid[tile_id][first]),
                    'actual': int(result[first]),
                })

        if progress_interval and (tile_id + 1) % progress_interval == 0:
            print(
                f'Tiles {tile_id + 1:3d}/256 '
                f'mismatched_tiles={len(mismatch_log)} retries={retry_count}',
                flush=True,
            )

    elapsed = time.perf_counter() - started
    merged = merge_valid_tiles(received)
    merged_mismatch = None
    merged_max_error = None
    if merged_expected is not None:
        if merged_expected.shape != (1, 256, 256):
            raise ValueError(f'bad merged expected shape: {merged_expected.shape}')
        difference = merged.astype(np.int64) - merged_expected.astype(np.int64)
        merged_mismatch = int(np.count_nonzero(difference))
        merged_max_error = int(np.max(np.abs(difference)))

    summary = {
        'tile_count': 256,
        'mismatched_tile_count': len(mismatch_log),
        'merged_mismatch_count': merged_mismatch,
        'merged_max_error_lsb': merged_max_error,
        'retry_count': retry_count,
        'tx_bytes': total_tx_bytes,
        'rx_bytes': total_rx_bytes,
        'total_cycle_count': total_cycles,
        'elapsed_seconds': elapsed,
    }
    return merged, summary, mismatch_log


def save_results(
    output_dir: Path,
    merged: np.ndarray,
    summary: dict,
    mismatch_log: list[dict],
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    np.save(output_dir / 'fpga_merged_int16.npy', merged)

    preview = np.rint(
        np.clip(merged[0].astype(np.float64) / 32767.0, 0.0, 1.0) * 255.0
    ).astype(np.uint8)
    Image.fromarray(preview, mode='L').save(output_dir / 'fpga_merged_256.png')

    with (output_dir / 'session_summary.json').open('w', encoding='utf-8') as file:
        json.dump(summary, file, ensure_ascii=False, indent=2)
        file.write('\n')
    with (output_dir / 'mismatch_log.json').open('w', encoding='utf-8') as file:
        json.dump(mismatch_log, file, ensure_ascii=False, indent=2)
        file.write('\n')


def main() -> None:
    parser = argparse.ArgumentParser(description='SRCNN NPU 256-Tile UART PC Master.')
    parser.add_argument('--port', help='예: COM5')
    parser.add_argument('--mock', action='store_true', help='Golden을 반환하는 Mock 보드 사용')
    parser.add_argument('--list-ports', action='store_true')
    parser.add_argument('--baud', type=int, default=115200)
    parser.add_argument('--timeout', type=float, default=5.0)
    parser.add_argument('--retries', type=int, default=1)
    parser.add_argument(
        '--input-tiles',
        type=Path,
        default=Path('full_image_data/input_tiles_int16.npy'),
    )
    parser.add_argument(
        '--golden-output-tiles',
        type=Path,
        default=Path('full_image_golden/output_tiles_int16.npy'),
    )
    parser.add_argument(
        '--merged-expected',
        type=Path,
        default=Path('full_image_golden/output_merged_int16.npy'),
    )
    parser.add_argument('--output-dir', type=Path, default=Path('uart_results'))
    args = parser.parse_args()

    if args.list_ports:
        ports = list_serial_ports()
        if not ports:
            print('No serial ports found.')
        for device, description in ports:
            print(f'{device}: {description}')
        return

    if bool(args.port) == bool(args.mock):
        parser.error('choose exactly one of --port COMx or --mock')

    input_tiles = np.load(args.input_tiles)
    golden_output_tiles = np.load(args.golden_output_tiles)
    merged_expected = np.load(args.merged_expected)

    if args.mock:
        board = MockZybo(
            input_tiles,
            golden_output_tiles[:, :, 8:24, 8:24],
        )
        transport: Transport = MockTransport(board)
        mode = 'mock'
    else:
        transport = SerialTransport(args.port, args.baud, args.timeout)
        mode = 'serial'

    try:
        merged, summary, mismatch_log = run_session(
            transport,
            input_tiles,
            golden_output_tiles=golden_output_tiles,
            merged_expected=merged_expected,
            retries=args.retries,
        )
    finally:
        transport.close()

    summary['mode'] = mode
    summary['port'] = args.port
    summary['baud'] = args.baud if mode == 'serial' else None
    save_results(args.output_dir, merged, summary, mismatch_log)

    print('UART session complete.')
    print('Mode            :', mode)
    print('Mismatch Tiles  :', summary['mismatched_tile_count'])
    print('Merged Mismatch :', summary['merged_mismatch_count'])
    print('Max Error       :', summary['merged_max_error_lsb'], 'LSB')
    print('Retries         :', summary['retry_count'])
    print('Elapsed         :', f'{summary["elapsed_seconds"]:.3f}s')
    print('Results         :', args.output_dir.resolve())


if __name__ == '__main__':
    main()
