"""256개 Tile 입력/출력을 RTL 및 UART 채점용 HEX로 내보낸다."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


def encode_twos_complement(value: int, bits: int) -> int:
    return int(value) & ((1 << bits) - 1)


def decode_twos_complement(value: int, bits: int) -> int:
    sign_bit = 1 << (bits - 1)
    return value - (1 << bits) if value & sign_bit else value


def export_signed_hex(array: np.ndarray, path: Path, bits: int = 16) -> dict:
    values = np.asarray(array).astype(np.int64).reshape(-1, order='C')
    minimum = -(1 << (bits - 1))
    maximum = (1 << (bits - 1)) - 1
    if np.any(values < minimum) or np.any(values > maximum):
        raise ValueError(f'values exceed signed {bits}-bit range')

    path.parent.mkdir(parents=True, exist_ok=True)
    digits = bits // 4
    with path.open('w', encoding='ascii', newline='\n') as file:
        for value in values:
            file.write(f'{encode_twos_complement(value, bits):0{digits}X}\n')

    decoded = []
    with path.open('r', encoding='ascii') as file:
        for line in file:
            text = line.strip()
            if text:
                decoded.append(decode_twos_complement(int(text, 16), bits))
    decoded = np.asarray(decoded, dtype=np.int64)
    if not np.array_equal(values, decoded):
        mismatch = int(np.flatnonzero(values != decoded)[0])
        raise RuntimeError(f'HEX round trip failed at flat index {mismatch}')

    return {
        'output': str(path.resolve()),
        'bits': bits,
        'hex_digits': digits,
        'shape': list(np.asarray(array).shape),
        'count': int(values.size),
        'minimum': int(values.min()),
        'maximum': int(values.max()),
        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'round_trip_verified': True,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description='Export all full-image Tile vectors to HEX.')
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
        '--valid-masks',
        type=Path,
        default=Path('full_image_data/tile_valid_masks.npy'),
    )
    parser.add_argument(
        '--merged-output',
        type=Path,
        default=Path('full_image_golden/output_merged_int16.npy'),
    )
    parser.add_argument(
        '--output-dir',
        type=Path,
        default=Path('full_image_rtl_data'),
    )
    args = parser.parse_args()

    input_tiles = np.load(args.input_tiles)
    valid_masks = np.load(args.valid_masks)
    output_tiles = np.load(args.output_tiles)
    merged_output = np.load(args.merged_output)

    expected_tile_shape = (256, 1, 32, 32)
    if input_tiles.shape != expected_tile_shape:
        raise ValueError(f'input Tiles must be {expected_tile_shape}, got {input_tiles.shape}')
    if valid_masks.shape != expected_tile_shape:
        raise ValueError(f'valid masks must be {expected_tile_shape}, got {valid_masks.shape}')
    if output_tiles.shape != expected_tile_shape:
        raise ValueError(f'output Tiles must be {expected_tile_shape}, got {output_tiles.shape}')
    if merged_output.shape != (1, 256, 256):
        raise ValueError(f'merged output must be (1, 256, 256), got {merged_output.shape}')

    valid_outputs = output_tiles[:, :, 8:24, 8:24]
    files = [
        (
            'input_tiles.hex', input_tiles,
            'All NPU input Tiles; tile_id -> channel -> y -> x',
            'addr = tile_id*1024 + y*32 + x',
        ),
        (
            'tile_valid_masks.hex', valid_masks,
            'Global image boundary mask applied after Conv1 and Conv2 post-processing',
            'addr = tile_id*1024 + local_y*32 + local_x',
        ),
        (
            'output_tiles_expected.hex', output_tiles,
            'All complete 32x32 NPU output Tiles',
            'addr = tile_id*1024 + y*32 + x',
        ),
        (
            'output_valid_expected.hex', valid_outputs,
            'All center 16x16 UART response payloads',
            'addr = tile_id*256 + valid_y*16 + valid_x',
        ),
        (
            'output_merged_expected.hex', merged_output,
            'Merged 256x256 Python INT16 Golden image',
            'addr = y*256 + x',
        ),
    ]

    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest = []
    for filename, array, role, formula in files:
        bits = 8 if filename == 'tile_valid_masks.hex' else 16
        result = export_signed_hex(array, args.output_dir / filename, bits=bits)
        result['role'] = role
        result['address_formula'] = formula
        result['order'] = 'NumPy C-order / row-major'
        manifest.append(result)
        print(
            f'{filename:30s} shape={str(tuple(array.shape)):22s} '
            f'count={result["count"]:7d} PASS'
        )

    manifest_path = args.output_dir / 'manifest.json'
    with manifest_path.open('w', encoding='utf-8') as file:
        json.dump(manifest, file, ensure_ascii=False, indent=2)
        file.write('\n')

    print('All full-image HEX files verified.')
    print('Manifest:', manifest_path.resolve())


if __name__ == '__main__':
    main()
