"""보드 없이 256회 Stop-and-Wait UART 흐름을 검증하는 Mock 실행기."""

from __future__ import annotations

import argparse
import hashlib
import json
import time
from pathlib import Path

import numpy as np

from uart_protocol import (
    ProtocolError,
    Status,
    decode_run_tile,
    decode_tile_result,
    encode_run_tile,
    encode_tile_result,
)


NOMINAL_TILE_CYCLES = 30_839_827


def sha256_array(array: np.ndarray) -> str:
    return hashlib.sha256(np.ascontiguousarray(array).tobytes()).hexdigest()


def merge_valid_tiles(valid_tiles: np.ndarray) -> np.ndarray:
    valid_tiles = np.asarray(valid_tiles)
    if valid_tiles.shape != (256, 1, 16, 16):
        raise ValueError(f'expected (256, 1, 16, 16), got {valid_tiles.shape}')

    merged = np.empty((1, 256, 256), dtype=valid_tiles.dtype)
    for tile_id in range(256):
        tile_x = tile_id % 16
        tile_y = tile_id // 16
        x0 = tile_x * 16
        y0 = tile_y * 16
        merged[:, y0:y0 + 16, x0:x0 + 16] = valid_tiles[tile_id]
    return merged


class MockZybo:
    """RUN_TILE을 검사하고 미리 계산된 Golden Valid Tile을 반환한다."""

    def __init__(
        self,
        expected_inputs: np.ndarray,
        golden_valid_outputs: np.ndarray,
        cycle_count: int = NOMINAL_TILE_CYCLES,
    ):
        if expected_inputs.shape != (256, 1, 32, 32):
            raise ValueError(f'bad expected input shape: {expected_inputs.shape}')
        if golden_valid_outputs.shape != (256, 1, 16, 16):
            raise ValueError(f'bad Golden output shape: {golden_valid_outputs.shape}')
        self.expected_inputs = expected_inputs
        self.golden_valid_outputs = golden_valid_outputs
        self.cycle_count = cycle_count

    def transact(self, request: bytes) -> bytes:
        packet, input_pixels = decode_run_tile(request)
        if not np.array_equal(input_pixels, self.expected_inputs[packet.tile_id]):
            raise ProtocolError(
                f'Mock input mismatch for Tile {packet.tile_id}'
            )

        return encode_tile_result(
            packet.tile_id,
            self.golden_valid_outputs[packet.tile_id],
            cycle_count=self.cycle_count,
        )


def run_mock(
    input_tiles: np.ndarray,
    output_tiles: np.ndarray,
    merged_expected: np.ndarray,
) -> tuple[np.ndarray, dict]:
    golden_valid = output_tiles[:, :, 8:24, 8:24]
    board = MockZybo(input_tiles, golden_valid)
    received = np.empty_like(golden_valid)

    total_tx_bytes = 0
    total_rx_bytes = 0
    total_cycles = 0
    started = time.perf_counter()

    for tile_id in range(256):
        request = encode_run_tile(
            tile_id,
            input_tiles[tile_id],
            last_tile=(tile_id == 255),
        )
        response = board.transact(request)
        packet, result = decode_tile_result(response)

        if packet.tile_id != tile_id:
            raise ProtocolError(f'response Tile ID mismatch: {packet.tile_id} != {tile_id}')
        if packet.status != Status.OK or result is None:
            raise ProtocolError(f'Tile {tile_id} failed: {packet.status.name}')

        received[tile_id] = result
        total_tx_bytes += len(request)
        total_rx_bytes += len(response)
        total_cycles += packet.cycle_count

        if (tile_id + 1) % 16 == 0:
            print(f'Tiles {tile_id + 1:3d}/256 PASS', flush=True)

    elapsed = time.perf_counter() - started
    merged = merge_valid_tiles(received)
    difference = merged.astype(np.int64) - merged_expected.astype(np.int64)
    mismatch_count = int(np.count_nonzero(difference))
    max_error = int(np.max(np.abs(difference)))

    result = {
        'tile_count': 256,
        'mismatch_count': mismatch_count,
        'max_integer_error_lsb': max_error,
        'tx_bytes': total_tx_bytes,
        'rx_bytes': total_rx_bytes,
        'nominal_cycle_count_per_tile': NOMINAL_TILE_CYCLES,
        'nominal_total_cycles': total_cycles,
        'mock_elapsed_seconds': elapsed,
        'received_valid_sha256': sha256_array(received),
        'merged_sha256': sha256_array(merged),
    }
    return merged, result


def main() -> None:
    parser = argparse.ArgumentParser(description='Run the complete 256-Tile UART Mock.')
    parser.add_argument(
        '--input-tiles',
        type=Path,
        default=Path('full_image_data/input_tiles_int16.npy'),
    )
    parser.add_argument(
        '--output-tiles',
        type=Path,
        default=Path('full_image_golden/output_tiles_int16.npy'),
    )
    parser.add_argument(
        '--merged-expected',
        type=Path,
        default=Path('full_image_golden/output_merged_int16.npy'),
    )
    parser.add_argument('--output-dir', type=Path, default=Path('uart_mock_results'))
    args = parser.parse_args()

    input_tiles = np.load(args.input_tiles)
    output_tiles = np.load(args.output_tiles)
    merged_expected = np.load(args.merged_expected)
    merged, result = run_mock(input_tiles, output_tiles, merged_expected)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    np.save(args.output_dir / 'merged_received_int16.npy', merged)
    with (args.output_dir / 'manifest.json').open('w', encoding='utf-8') as file:
        json.dump(result, file, ensure_ascii=False, indent=2)
        file.write('\n')

    print('UART Mock complete.')
    print('Mismatch count:', result['mismatch_count'])
    print('Max error     :', result['max_integer_error_lsb'], 'LSB')
    print('TX bytes      :', result['tx_bytes'])
    print('RX bytes      :', result['rx_bytes'])
    print('Manifest      :', (args.output_dir / 'manifest.json').resolve())


if __name__ == '__main__':
    main()
