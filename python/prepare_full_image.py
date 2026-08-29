"""C 역할용 128x128 LR -> 256x256 Bicubic -> INT16 Halo Tile 전처리."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from tile_halo import create_tile_valid_masks, split_halo_tiles
from utils import convert_rgb_to_ycbcr


LR_SIZE = (128, 128)
HR_SIZE = (256, 256)
INPUT_FRACTION_BITS = 15


def quantize_input_y(y_normalized: np.ndarray) -> np.ndarray:
    """정규화된 Y [0, 1]을 기존 quantize_int16.py와 같은 F15로 변환한다."""
    scaled = np.rint(y_normalized * (1 << INPUT_FRACTION_BITS))
    return np.clip(scaled, -32768, 32767).astype(np.int16)


def sha256_array(array: np.ndarray) -> str:
    contiguous = np.ascontiguousarray(array)
    return hashlib.sha256(contiguous.tobytes()).hexdigest()


def load_lr_and_optional_hr(
    lr_image: Path | None,
    hr_image: Path | None,
) -> tuple[Image.Image, Image.Image | None]:
    if (lr_image is None) == (hr_image is None):
        raise ValueError('exactly one of --lr-image or --hr-image must be provided')

    if lr_image is not None:
        lr = Image.open(lr_image).convert('RGB')
        if lr.size != LR_SIZE:
            raise ValueError(f'LR image must be 128x128, got {lr.size}')
        return lr, None

    hr = Image.open(hr_image).convert('RGB')
    if hr.size != HR_SIZE:
        raise ValueError(f'HR image must be 256x256, got {hr.size}')

    lr = hr.resize(LR_SIZE, resample=Image.Resampling.BICUBIC)
    return lr, hr


def prepare(
    output_dir: Path,
    lr_image: Path | None = None,
    hr_image: Path | None = None,
) -> dict:
    lr, hr = load_lr_and_optional_hr(lr_image, hr_image)
    bicubic = lr.resize(HR_SIZE, resample=Image.Resampling.BICUBIC)

    rgb = np.asarray(bicubic, dtype=np.float32)
    y = convert_rgb_to_ycbcr(rgb)[..., 0] / 255.0
    input_y_f32 = y[np.newaxis, np.newaxis, ...].astype(np.float32)
    input_y_int16 = quantize_input_y(input_y_f32)

    # [1, 256, 256] -> [256, 1, 32, 32]
    input_tiles_int16 = split_halo_tiles(input_y_int16[0])
    tile_valid_masks = create_tile_valid_masks(HR_SIZE)

    output_dir.mkdir(parents=True, exist_ok=True)
    lr.save(output_dir / 'lr_128.png')
    bicubic.save(output_dir / 'bicubic_256.png')
    if hr is not None:
        hr.save(output_dir / 'hr_256.png')

    np.save(output_dir / 'input_y_f32.npy', input_y_f32)
    np.save(output_dir / 'input_y_int16.npy', input_y_int16)
    np.save(output_dir / 'input_tiles_int16.npy', input_tiles_int16)
    np.save(output_dir / 'tile_valid_masks.npy', tile_valid_masks)

    metadata = {
        'source_mode': 'lr' if lr_image is not None else 'hr_for_evaluation',
        'source_path': str((lr_image or hr_image).resolve()),
        'lr_size': list(LR_SIZE),
        'bicubic_size': list(HR_SIZE),
        'input_q_format': 'signed INT16 F15',
        'tile_order': 'row-major: tile_id = tile_y * 16 + tile_x',
        'tile_shape': list(input_tiles_int16.shape),
        'valid_size': 16,
        'halo': 8,
        'tile_size': 32,
        'tile_count': int(input_tiles_int16.shape[0]),
        'input_y_min': int(input_y_int16.min()),
        'input_y_max': int(input_y_int16.max()),
        'input_y_sha256': sha256_array(input_y_int16),
        'input_tiles_sha256': sha256_array(input_tiles_int16),
        'tile_valid_masks_shape': list(tile_valid_masks.shape),
        'tile_valid_masks_sha256': sha256_array(tile_valid_masks),
        'boundary_rule': (
            'Apply mask after Conv1/ReLU/Requant and Conv2/ReLU/Requant so '
            'features outside the full image remain zero.'
        ),
    }

    with (output_dir / 'manifest.json').open('w', encoding='utf-8') as file:
        json.dump(metadata, file, ensure_ascii=False, indent=2)
        file.write('\n')

    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(
        description='Prepare a 128x128 LR image and 256 INT16 Halo Tiles.'
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument(
        '--lr-image',
        type=Path,
        help='실제 데모용 128x128 LR 이미지',
    )
    source.add_argument(
        '--hr-image',
        type=Path,
        help='평가용 256x256 HR 이미지. 내부에서 LR 128x128을 생성한다.',
    )
    parser.add_argument(
        '--output-dir',
        type=Path,
        default=Path('full_image_data'),
    )
    args = parser.parse_args()

    metadata = prepare(args.output_dir, args.lr_image, args.hr_image)

    print('LR image       :', args.output_dir / 'lr_128.png')
    print('Bicubic image  :', args.output_dir / 'bicubic_256.png')
    print('INT16 input    :', args.output_dir / 'input_y_int16.npy')
    print('INT16 Tiles    :', args.output_dir / 'input_tiles_int16.npy')
    print('Boundary Masks :', args.output_dir / 'tile_valid_masks.npy')
    print('Tile shape     :', tuple(metadata['tile_shape']))
    print('Tile count     :', metadata['tile_count'])
    print('Manifest       :', args.output_dir / 'manifest.json')


if __name__ == '__main__':
    main()
