"""OIHW INT16 Weight를 4-PE용 64-bit ROM word로 패킹한다.

주소 순서: output_channel_group -> input_channel -> kernel_y -> kernel_x

64-bit lane 배치:
    [63:48] PE3, [47:32] PE2, [31:16] PE1, [15:0] PE0
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


PE_COUNT = 4
LANE_BITS = 16
WORD_BITS = PE_COUNT * LANE_BITS


def pack_weights_pe4(weight: np.ndarray) -> np.ndarray:
    """OIHW signed INT16 Weight를 uint64 PE4 word 배열로 변환한다."""
    weight = np.asarray(weight)
    if weight.ndim != 4:
        raise ValueError(f'weight must have OIHW shape, got {weight.shape}')
    if weight.dtype != np.int16:
        raise ValueError(f'weight dtype must be int16, got {weight.dtype}')

    out_channels, in_channels, kernel_h, kernel_w = weight.shape
    group_count = (out_channels + PE_COUNT - 1) // PE_COUNT
    packed = np.zeros(
        (group_count, in_channels, kernel_h, kernel_w),
        dtype=np.uint64,
    )

    for group in range(group_count):
        for lane in range(PE_COUNT):
            output_channel = group * PE_COUNT + lane
            if output_channel >= out_channels:
                continue

            lane_values = weight[output_channel].astype(np.int64) & 0xFFFF
            packed[group] |= lane_values.astype(np.uint64) << (lane * LANE_BITS)

    return packed.reshape(-1, order='C')


def unpack_weights_pe4(
    packed: np.ndarray,
    original_shape: tuple[int, int, int, int],
) -> np.ndarray:
    """검증용: PE4 word를 원래 OIHW signed INT16 배열로 복원한다."""
    out_channels, in_channels, kernel_h, kernel_w = original_shape
    group_count = (out_channels + PE_COUNT - 1) // PE_COUNT
    expected_words = group_count * in_channels * kernel_h * kernel_w

    packed = np.asarray(packed, dtype=np.uint64).reshape(-1)
    if packed.size != expected_words:
        raise ValueError(f'expected {expected_words} words, got {packed.size}')

    words = packed.reshape(group_count, in_channels, kernel_h, kernel_w)
    restored = np.empty(original_shape, dtype=np.int16)

    for output_channel in range(out_channels):
        group, lane = divmod(output_channel, PE_COUNT)
        encoded = ((words[group] >> (lane * LANE_BITS)) & 0xFFFF).astype(np.uint16)
        restored[output_channel] = encoded.view(np.int16)

    return restored


def verify_unused_lanes_are_zero(
    packed: np.ndarray,
    original_shape: tuple[int, int, int, int],
) -> None:
    out_channels, in_channels, kernel_h, kernel_w = original_shape
    remainder = out_channels % PE_COUNT
    if remainder == 0:
        return

    group_count = (out_channels + PE_COUNT - 1) // PE_COUNT
    words = np.asarray(packed, dtype=np.uint64).reshape(
        group_count,
        in_channels,
        kernel_h,
        kernel_w,
    )
    for lane in range(remainder, PE_COUNT):
        encoded = (words[-1] >> (lane * LANE_BITS)) & 0xFFFF
        if np.any(encoded != 0):
            raise RuntimeError(f'unused PE{lane} lane is not zero')


def write_uint64_hex(path: Path, packed: np.ndarray) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w', encoding='ascii', newline='\n') as file:
        for word in np.asarray(packed, dtype=np.uint64).reshape(-1):
            file.write(f'{int(word):016X}\n')
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_uint64_hex(path: Path) -> np.ndarray:
    words = [
        int(line.strip(), 16)
        for line in path.read_text(encoding='ascii').splitlines()
        if line.strip()
    ]
    return np.asarray(words, dtype=np.uint64)


def export_layer(source: Path, output_dir: Path, layer_name: str) -> dict:
    weight = np.load(source)
    packed = pack_weights_pe4(weight)
    verify_unused_lanes_are_zero(packed, weight.shape)

    restored = unpack_weights_pe4(packed, weight.shape)
    if not np.array_equal(restored, weight):
        mismatch = tuple(int(v) for v in np.argwhere(restored != weight)[0])
        raise RuntimeError(f'{layer_name} in-memory round trip failed at {mismatch}')

    npy_path = output_dir / f'{layer_name}_weight_pe4.npy'
    hex_path = output_dir / f'{layer_name}_weight_pe4.hex'
    np.save(npy_path, packed)
    digest = write_uint64_hex(hex_path, packed)

    from_hex = read_uint64_hex(hex_path)
    if not np.array_equal(from_hex, packed):
        raise RuntimeError(f'{layer_name} HEX round trip failed')
    if not np.array_equal(unpack_weights_pe4(from_hex, weight.shape), weight):
        raise RuntimeError(f'{layer_name} HEX unpack failed')

    out_channels, in_channels, kernel_h, kernel_w = weight.shape
    group_count = (out_channels + PE_COUNT - 1) // PE_COUNT
    return {
        'layer': layer_name,
        'source': str(source.resolve()),
        'source_shape_oihw': list(weight.shape),
        'output_npy': str(npy_path.resolve()),
        'output_hex': str(hex_path.resolve()),
        'word_bits': WORD_BITS,
        'hex_digits': 16,
        'word_count': int(packed.size),
        'output_channel_groups': group_count,
        'address_order': 'oc_group -> input_channel -> kernel_y -> kernel_x',
        'lane_order': {
            'bits_15_0': 'PE0 / oc_group*4+0',
            'bits_31_16': 'PE1 / oc_group*4+1',
            'bits_47_32': 'PE2 / oc_group*4+2',
            'bits_63_48': 'PE3 / oc_group*4+3'
        },
        'address_formula': (
            '(((oc_group * input_channels) + ic) * kernel_h + ky) '
            '* kernel_w + kx'
        ),
        'sha256': digest,
        'round_trip_verified': True,
        'unused_lanes_zero': True,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description='Pack SRCNN weights for a 4-PE ROM.')
    parser.add_argument('--input-dir', type=Path, default=Path('dump_int16'))
    parser.add_argument('--output-dir', type=Path, default=Path('packed_weights'))
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest = []
    for layer_name in ('conv1', 'conv2', 'conv3'):
        result = export_layer(
            args.input_dir / f'{layer_name}_weight.npy',
            args.output_dir,
            layer_name,
        )
        manifest.append(result)
        print(
            f'{layer_name}: source={tuple(result["source_shape_oihw"])} '
            f'groups={result["output_channel_groups"]} '
            f'words={result["word_count"]} PASS'
        )

    manifest_path = args.output_dir / 'manifest.json'
    with manifest_path.open('w', encoding='utf-8') as file:
        json.dump(manifest, file, ensure_ascii=False, indent=2)
        file.write('\n')

    print('All PE4 weights verified.')
    print('Manifest:', manifest_path.resolve())


if __name__ == '__main__':
    main()
