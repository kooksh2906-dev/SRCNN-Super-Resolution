from pathlib import Path
import numpy as np

input_dir = Path('dump_fp32')
output_dir = Path('dump_int16')
output_dir.mkdir(exist_ok=True)

formats = {
    'input_y.npy':       (15, np.int16),

    'conv1_weight.npy':  (14, np.int16),
    'conv1_bias.npy':    (29, np.int32),
    'relu1_output.npy':  (15, np.int16),

    'conv2_weight.npy':  (15, np.int16),
    'conv2_bias.npy':    (30, np.int32),
    'relu2_output.npy':  (14, np.int16),

    'conv3_weight.npy':  (15, np.int16),
    'conv3_bias.npy':    (29, np.int32),
    'output_fp32.npy':   (15, np.int16),
}


def quantize(data, fraction_bits, dtype):
    scale = 1 << fraction_bits
    scaled = np.rint(data * scale)

    limits = np.iinfo(dtype)

    saturation_count = np.count_nonzero(
        (scaled < limits.min) | (scaled > limits.max)
    )

    quantized = np.clip(
        scaled,
        limits.min,
        limits.max
    ).astype(dtype)

    return quantized, saturation_count


for filename, (fraction_bits, dtype) in formats.items():
    data = np.load(input_dir / filename)

    quantized, saturation_count = quantize(
        data,
        fraction_bits,
        dtype
    )

    np.save(output_dir / filename, quantized)

    reconstructed = quantized.astype(np.float64) / (1 << fraction_bits)
    error = np.max(np.abs(data - reconstructed))

    print(
        f'{filename:25s}',
        f'F={fraction_bits:2d}',
        f'dtype={dtype.__name__:5s}',
        f'saturation={saturation_count:4d}',
        f'max_error={error:.10f}'
    )