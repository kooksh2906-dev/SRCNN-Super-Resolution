"""32x32 Halo Tile 생성과 중앙 16x16 Valid 영역 병합.

SRCNN의 전체 receptive field radius가 8이므로, 16x16 출력 영역 하나를
정확히 계산하려면 상하좌우 8픽셀을 포함한 32x32 입력 Tile이 필요하다.

Tile 순서는 row-major이다.

    tile_id = tile_y * tiles_x + tile_x

전체 이미지 바깥만 0으로 padding하며, 내부 Tile 경계에는 실제 이웃 픽셀이
들어간다.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np


DEFAULT_VALID_SIZE = 16
DEFAULT_HALO = 8
DEFAULT_TILE_SIZE = DEFAULT_VALID_SIZE + 2 * DEFAULT_HALO


def _validate_image(image: np.ndarray, valid_size: int, halo: int) -> tuple[int, int]:
    if image.ndim not in (2, 3):
        raise ValueError(
            'image must have shape [H, W] or [C, H, W], '
            f'got {image.shape}'
        )

    if valid_size <= 0:
        raise ValueError('valid_size must be positive')

    if halo < 0:
        raise ValueError('halo must be non-negative')

    height, width = image.shape[-2:]

    if height % valid_size != 0 or width % valid_size != 0:
        raise ValueError(
            f'image size {height}x{width} must be divisible by '
            f'valid_size={valid_size}'
        )

    return height, width


def split_halo_tiles(
    image: np.ndarray,
    valid_size: int = DEFAULT_VALID_SIZE,
    halo: int = DEFAULT_HALO,
) -> np.ndarray:
    """이미지를 row-major Halo Tile 배열로 분할한다.

    Args:
        image: [H, W] 또는 [C, H, W].
        valid_size: Tile 하나가 최종 이미지에 제공하는 중앙 영역 크기.
        halo: 중앙 Valid 영역의 각 방향에 추가할 주변 픽셀 수.

    Returns:
        입력이 [H, W]이면 [N, T, T], [C, H, W]이면 [N, C, T, T].
        여기서 T = valid_size + 2 * halo이다.
    """
    image = np.asarray(image)
    height, width = _validate_image(image, valid_size, halo)
    tile_size = valid_size + 2 * halo

    if image.ndim == 2:
        padded = np.pad(image, ((halo, halo), (halo, halo)), mode='constant')
    else:
        padded = np.pad(
            image,
            ((0, 0), (halo, halo), (halo, halo)),
            mode='constant',
        )

    tiles = []
    for tile_y in range(height // valid_size):
        y0 = tile_y * valid_size
        for tile_x in range(width // valid_size):
            x0 = tile_x * valid_size
            tile = padded[..., y0:y0 + tile_size, x0:x0 + tile_size]
            tiles.append(tile.copy())

    return np.stack(tiles, axis=0)


def create_tile_valid_masks(
    image_shape: tuple[int, int],
    valid_size: int = DEFAULT_VALID_SIZE,
    halo: int = DEFAULT_HALO,
) -> np.ndarray:
    """각 Tile 위치가 전체 이미지 안인지 나타내는 [N,1,T,T] uint8 mask.

    입력 0-padding만으로는 bias가 있는 다층 CNN의 전체 이미지 경계를 정확히
    재현할 수 없다. Conv1/Conv2 후 이 mask를 적용해 전체 이미지 바깥의 중간
    Feature를 0으로 만들어야 한다.
    """
    height, width = image_shape
    if height % valid_size != 0 or width % valid_size != 0:
        raise ValueError('image size must be divisible by valid_size')

    tile_size = valid_size + 2 * halo
    masks = []
    for tile_y in range(height // valid_size):
        global_y = tile_y * valid_size - halo + np.arange(tile_size)
        valid_y = (global_y >= 0) & (global_y < height)
        for tile_x in range(width // valid_size):
            global_x = tile_x * valid_size - halo + np.arange(tile_size)
            valid_x = (global_x >= 0) & (global_x < width)
            mask = valid_y[:, None] & valid_x[None, :]
            masks.append(mask[np.newaxis, ...].astype(np.uint8))

    return np.stack(masks, axis=0)


def merge_valid_regions(
    output_tiles: np.ndarray,
    image_shape: tuple[int, int],
    valid_size: int = DEFAULT_VALID_SIZE,
    halo: int = DEFAULT_HALO,
) -> np.ndarray:
    """각 NPU 출력 Tile의 중앙 Valid 영역을 전체 이미지로 병합한다.

    Args:
        output_tiles: [N, T, T] 또는 [N, C, T, T].
        image_shape: 병합할 전체 이미지의 (height, width).
        valid_size: 중앙 Valid 영역 크기.
        halo: 출력 Tile에서 잘라낼 바깥쪽 영역 크기.

    Returns:
        입력이 [N, T, T]이면 [H, W], [N, C, T, T]이면 [C, H, W].
    """
    output_tiles = np.asarray(output_tiles)

    if output_tiles.ndim not in (3, 4):
        raise ValueError(
            'output_tiles must have shape [N, T, T] or [N, C, T, T], '
            f'got {output_tiles.shape}'
        )

    if valid_size <= 0:
        raise ValueError('valid_size must be positive')

    if halo < 0:
        raise ValueError('halo must be non-negative')

    height, width = image_shape
    if height % valid_size != 0 or width % valid_size != 0:
        raise ValueError(
            f'image size {height}x{width} must be divisible by '
            f'valid_size={valid_size}'
        )

    tile_size = valid_size + 2 * halo
    if output_tiles.shape[-2:] != (tile_size, tile_size):
        raise ValueError(
            f'output Tile size must be {tile_size}x{tile_size}, '
            f'got {output_tiles.shape[-2:]}'
        )

    tiles_y = height // valid_size
    tiles_x = width // valid_size
    expected_count = tiles_y * tiles_x
    if output_tiles.shape[0] != expected_count:
        raise ValueError(
            f'expected {expected_count} Tiles for {height}x{width}, '
            f'got {output_tiles.shape[0]}'
        )

    if output_tiles.ndim == 3:
        merged = np.empty((height, width), dtype=output_tiles.dtype)
    else:
        channels = output_tiles.shape[1]
        merged = np.empty((channels, height, width), dtype=output_tiles.dtype)

    tile_id = 0
    for tile_y in range(tiles_y):
        y0 = tile_y * valid_size
        for tile_x in range(tiles_x):
            x0 = tile_x * valid_size
            valid = output_tiles[
                tile_id,
                ...,
                halo:halo + valid_size,
                halo:halo + valid_size,
            ]
            merged[..., y0:y0 + valid_size, x0:x0 + valid_size] = valid
            tile_id += 1

    return merged


def tile_xy(tile_id: int, image_shape: tuple[int, int], valid_size: int = 16) -> tuple[int, int]:
    """row-major tile_id를 (tile_x, tile_y)로 변환한다."""
    height, width = image_shape
    if height % valid_size != 0 or width % valid_size != 0:
        raise ValueError('image size must be divisible by valid_size')

    tiles_x = width // valid_size
    tile_count = (height // valid_size) * tiles_x
    if not 0 <= tile_id < tile_count:
        raise ValueError(f'tile_id must be in [0, {tile_count - 1}]')

    return tile_id % tiles_x, tile_id // tiles_x


def main() -> None:
    parser = argparse.ArgumentParser(
        description='Split a 2-D/CHW NPY image into 32x32 Halo Tiles.'
    )
    parser.add_argument('--input-npy', type=Path, required=True)
    parser.add_argument('--output-npy', type=Path, required=True)
    parser.add_argument('--valid-size', type=int, default=DEFAULT_VALID_SIZE)
    parser.add_argument('--halo', type=int, default=DEFAULT_HALO)
    args = parser.parse_args()

    image = np.load(args.input_npy)
    tiles = split_halo_tiles(image, args.valid_size, args.halo)

    args.output_npy.parent.mkdir(parents=True, exist_ok=True)
    np.save(args.output_npy, tiles)

    print('input shape :', image.shape)
    print('tiles shape :', tiles.shape)
    print('tiles saved :', args.output_npy.resolve())


if __name__ == '__main__':
    main()
