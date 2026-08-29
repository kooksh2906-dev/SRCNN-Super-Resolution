"""256개 32x32 Tile의 Python INT16 Golden 출력과 병합 영상을 생성한다."""

from __future__ import annotations

import argparse
import hashlib
import json
import time
from pathlib import Path

import numpy as np
from PIL import Image

from srcnn_int16_core import load_parameters, run_srcnn_int16
from tile_halo import merge_valid_regions


def sha256_array(array: np.ndarray) -> str:
    return hashlib.sha256(np.ascontiguousarray(array).tobytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(
        description='Generate Python INT16 Golden outputs for all Halo Tiles.'
    )
    parser.add_argument(
        '--tiles-npy',
        type=Path,
        default=Path('full_image_data/input_tiles_int16.npy'),
    )
    parser.add_argument(
        '--parameter-dir',
        type=Path,
        default=Path('dump_int16'),
    )
    parser.add_argument(
        '--valid-masks',
        type=Path,
        default=Path('full_image_data/tile_valid_masks.npy'),
        help='전체 이미지 경계의 Layer별 zero padding을 재현하는 mask',
    )
    parser.add_argument(
        '--output-dir',
        type=Path,
        default=Path('full_image_golden'),
    )
    parser.add_argument(
        '--batch-size',
        type=int,
        default=1,
        help='메모리 사용량을 제한하기 위한 동시 처리 Tile 수',
    )
    parser.add_argument(
        '--limit',
        type=int,
        help='Smoke test용 처리 Tile 수. 생략하면 전체 Tile을 처리한다.',
    )
    args = parser.parse_args()

    if args.batch_size <= 0:
        raise ValueError('--batch-size must be positive')

    tiles = np.load(args.tiles_npy)
    if tiles.ndim != 4 or tiles.shape[1:] != (1, 32, 32):
        raise ValueError(f'expected Tiles [N, 1, 32, 32], got {tiles.shape}')

    process_count = tiles.shape[0] if args.limit is None else min(args.limit, tiles.shape[0])
    valid_masks = np.load(args.valid_masks)
    if valid_masks.shape != tiles.shape:
        raise ValueError(
            f'valid masks must have shape {tiles.shape}, got {valid_masks.shape}'
        )
    parameters = load_parameters(args.parameter_dir)
    outputs = np.empty((process_count, 1, 32, 32), dtype=np.int16)

    started = time.perf_counter()
    for start in range(0, process_count, args.batch_size):
        end = min(start + args.batch_size, process_count)
        outputs[start:end] = run_srcnn_int16(
            tiles[start:end],
            parameters,
            valid_mask=valid_masks[start:end],
        )
        elapsed = time.perf_counter() - started
        print(
            f'Tiles {end:3d}/{process_count:3d} '
            f'({end / process_count * 100:6.2f}%) elapsed={elapsed:8.2f}s',
            flush=True,
        )

    elapsed = time.perf_counter() - started
    args.output_dir.mkdir(parents=True, exist_ok=True)
    output_tiles_path = args.output_dir / 'output_tiles_int16.npy'
    np.save(output_tiles_path, outputs)

    manifest = {
        'input_tiles': str(args.tiles_npy.resolve()),
        'parameter_dir': str(args.parameter_dir.resolve()),
        'valid_masks': str(args.valid_masks.resolve()),
        'layer_boundary_masking': True,
        'processed_tile_count': process_count,
        'complete': process_count == tiles.shape[0],
        'output_shape': list(outputs.shape),
        'output_dtype': str(outputs.dtype),
        'output_sha256': sha256_array(outputs),
        'elapsed_seconds': elapsed,
    }

    if process_count == 256:
        merged = merge_valid_regions(outputs, (256, 256))
        merged_path = args.output_dir / 'output_merged_int16.npy'
        np.save(merged_path, merged)

        preview = np.rint(
            np.clip(merged[0].astype(np.float64) / 32767.0, 0.0, 1.0) * 255.0
        ).astype(np.uint8)
        Image.fromarray(preview, mode='L').save(args.output_dir / 'output_merged_256.png')

        manifest['merged_shape'] = list(merged.shape)
        manifest['merged_sha256'] = sha256_array(merged)

    with (args.output_dir / 'manifest.json').open('w', encoding='utf-8') as file:
        json.dump(manifest, file, ensure_ascii=False, indent=2)
        file.write('\n')

    print('Golden Tiles saved:', output_tiles_path.resolve())
    print('Elapsed seconds   :', f'{elapsed:.3f}')


if __name__ == '__main__':
    main()
