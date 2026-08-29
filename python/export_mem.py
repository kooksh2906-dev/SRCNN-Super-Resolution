from pathlib import Path
import hashlib
import json

import numpy as np

# export_mem.py 파일이 있는 폴더
BASE_DIR = Path(__file__).resolve().parent

INPUT_DIR = BASE_DIR / 'dump_int16'
GOLDEN_DIR = BASE_DIR / 'golden_int16'
OUTPUT_DIR = BASE_DIR / 'rtl_data'

OUTPUT_DIR.mkdir(exist_ok=True)

FILES = [
    # RTL 입력 데이터
    {
        'source': INPUT_DIR / 'input_y.npy',
        'output': OUTPUT_DIR / 'input_y.hex',
        'bits': 16,
        'role': 'RTL input activation',
    },
    {
        'source': INPUT_DIR / 'conv1_weight.npy',
        'output': OUTPUT_DIR / 'conv1_weight.hex',
        'bits': 16,
        'role': 'Conv1 weight',
    },
    {
        'source': INPUT_DIR / 'conv1_bias.npy',
        'output': OUTPUT_DIR / 'conv1_bias.hex',
        'bits': 32,
        'role': 'Conv1 bias',
    },
    {
        'source': INPUT_DIR / 'conv2_weight.npy',
        'output': OUTPUT_DIR / 'conv2_weight.hex',
        'bits': 16,
        'role': 'Conv2 weight',
    },
    {
        'source': INPUT_DIR / 'conv2_bias.npy',
        'output': OUTPUT_DIR / 'conv2_bias.hex',
        'bits': 32,
        'role': 'Conv2 bias',
    },
    {
        'source': INPUT_DIR / 'conv3_weight.npy',
        'output': OUTPUT_DIR / 'conv3_weight.hex',
        'bits': 16,
        'role': 'Conv3 weight',
    },
    {
        'source': INPUT_DIR / 'conv3_bias.npy',
        'output': OUTPUT_DIR / 'conv3_bias.hex',
        'bits': 32,
        'role': 'Conv3 bias',
    },

    # 테스트벤치 정답 데이터
    {
        'source': GOLDEN_DIR / 'conv1_acc.npy',
        'output': OUTPUT_DIR / 'conv1_acc_expected.hex',
        'bits': 48,
        'role': 'Conv1 accumulator expected',
    },
    {
        'source': GOLDEN_DIR / 'relu1_q.npy',
        'output': OUTPUT_DIR / 'relu1_expected.hex',
        'bits': 16,
        'role': 'Conv1 requantized output expected',
    },
    {
        'source': GOLDEN_DIR / 'conv2_acc.npy',
        'output': OUTPUT_DIR / 'conv2_acc_expected.hex',
        'bits': 48,
        'role': 'Conv2 accumulator expected',
    },
    {
        'source': GOLDEN_DIR / 'relu2_q.npy',
        'output': OUTPUT_DIR / 'relu2_expected.hex',
        'bits': 16,
        'role': 'Conv2 requantized output expected',
    },
    {
        'source': GOLDEN_DIR / 'conv3_acc.npy',
        'output': OUTPUT_DIR / 'conv3_acc_expected.hex',
        'bits': 48,
        'role': 'Conv3 accumulator expected',
    },
    {
        'source': GOLDEN_DIR / 'output_q.npy',
        'output': OUTPUT_DIR / 'output_expected.hex',
        'bits': 16,
        'role': 'Final output expected',
    },
]


def signed_limits(bits):
    return -(1 << (bits - 1)), (1 << (bits - 1)) - 1


def encode_twos_complement(value, bits):
    mask = (1 << bits) - 1
    return int(value) & mask


def decode_twos_complement(value, bits):
    sign_bit = 1 << (bits - 1)

    if value & sign_bit:
        return value - (1 << bits)

    return value


def export_hex(source_path, output_path, bits):
    if not source_path.exists():
        raise FileNotFoundError(
            f'Input file not found: {source_path}'
        )

    data = np.load(source_path)

    # NumPy C-order:
    # Activation: W → H → C → N
    # Weight: KW → KH → IN_C → OUT_C
    flattened = np.asarray(data).reshape(-1, order='C')
    flattened = flattened.astype(np.int64)

    minimum, maximum = signed_limits(bits)

    below = flattened < minimum
    above = flattened > maximum

    if np.any(below) or np.any(above):
        invalid_count = np.count_nonzero(below | above)

        raise ValueError(
            f'{source_path}: {invalid_count} values exceed '
            f'signed {bits}-bit range [{minimum}, {maximum}]'
        )

    hex_width = bits // 4

    with output_path.open(
        'w',
        encoding='ascii',
        newline='\n'
    ) as file:
        for value in flattened:
            encoded = encode_twos_complement(value, bits)

            file.write(
                f'{encoded:0{hex_width}X}\n'
            )

    # HEX 파일을 다시 읽어 원본과 비교
    decoded_values = []

    with output_path.open('r', encoding='ascii') as file:
        for line in file:
            line = line.strip()

            if not line:
                continue

            encoded = int(line, 16)

            decoded = decode_twos_complement(
                encoded,
                bits
            )

            decoded_values.append(decoded)

    decoded_array = np.asarray(
        decoded_values,
        dtype=np.int64
    )

    if not np.array_equal(flattened, decoded_array):
        difference = flattened - decoded_array
        mismatch = np.flatnonzero(difference != 0)[0]

        raise RuntimeError(
            f'Round-trip verification failed: {source_path}, '
            f'index={mismatch}, '
            f'original={flattened[mismatch]}, '
            f'decoded={decoded_array[mismatch]}'
        )

    digest = hashlib.sha256(
        output_path.read_bytes()
    ).hexdigest()

    return {
        'source': str(source_path),
        'output': str(output_path),
        'role': None,
        'bits': bits,
        'hex_digits': hex_width,
        'source_dtype': str(data.dtype),
        'shape': list(data.shape),
        'count': int(flattened.size),
        'minimum': int(flattened.min()),
        'maximum': int(flattened.max()),
        'sha256': digest,
        'round_trip_verified': True,
    }


def main():
    manifest = []

    print('NPY → HEX conversion')
    print('=' * 80)

    for item in FILES:
        result = export_hex(
            item['source'],
            item['output'],
            item['bits']
        )

        result['role'] = item['role']
        manifest.append(result)

        print(
            f"{item['output'].name:28s} "
            f"bits={item['bits']:2d} "
            f"shape={str(tuple(result['shape'])):22s} "
            f"count={result['count']:7d} "
            f"min={result['minimum']:12d} "
            f"max={result['maximum']:12d} "
            f"PASS"
        )

    manifest_path = OUTPUT_DIR / 'manifest.json'

    with manifest_path.open(
        'w',
        encoding='utf-8'
    ) as file:
        json.dump(
            manifest,
            file,
            ensure_ascii=False,
            indent=2
        )

    print('=' * 80)
    print('All HEX files verified.')
    print('Output directory:', OUTPUT_DIR)
    print('Manifest:', manifest_path)


if __name__ == '__main__':
    main()