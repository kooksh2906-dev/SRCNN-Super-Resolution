from pathlib import Path
import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

data_dir = Path('dump_int16')
output_dir = Path('golden_int16')
output_dir.mkdir(exist_ok=True)


def load(name):
    return np.load(data_dir / name)


def conv2d_int(x, weight, bias, padding):
    """
    x      : [N, C, H, W] INT16
    weight : [O, C, KH, KW] INT16
    bias   : [O] INT32
    return : [N, O, H, W] INT64 accumulator
    """
    x64 = x.astype(np.int64)
    weight64 = weight.astype(np.int64)
    bias64 = bias.astype(np.int64)

    n, _, _, _ = x64.shape
    out_channels, _, kh, kw = weight64.shape

    padded = np.pad(
        x64,
        ((0, 0), (0, 0), (padding, padding), (padding, padding)),
        mode='constant'
    )

    windows = sliding_window_view(
        padded,
        (kh, kw),
        axis=(2, 3)
    )

    # [N, C, H, W, KH, KW]
    _, _, out_h, out_w, _, _ = windows.shape

    # [N, H, W, C*KH*KW]
    columns = windows.transpose(0, 2, 3, 1, 4, 5)
    columns = columns.reshape(n, out_h, out_w, -1)

    # [O, C*KH*KW]
    weight_matrix = weight64.reshape(out_channels, -1)

    # [N, H, W, O]
    accumulator = columns @ weight_matrix.T

    # [N, O, H, W]
    accumulator = accumulator.transpose(0, 3, 1, 2)

    accumulator += bias64.reshape(1, out_channels, 1, 1)

    return accumulator


def round_shift(value, shift):
    """부호를 고려한 반올림 후 오른쪽 shift."""
    half = 1 << (shift - 1)

    return np.where(
        value >= 0,
        (value + half) >> shift,
        -(((-value) + half) >> shift)
    )


def saturate_int16(value):
    return np.clip(value, -32768, 32767).astype(np.int16)


def accumulator_bits(value):
    max_abs = int(np.max(np.abs(value)))
    return max_abs.bit_length() + 1


def compare(name, actual, reference):
    difference = (
        actual.astype(np.int64) -
        reference.astype(np.int64)
    )

    print(
        f'{name:10s}',
        f'max_error={np.max(np.abs(difference)):5d} LSB',
        f'mean_error={np.mean(np.abs(difference)):.4f} LSB',
        f'exact={np.mean(difference == 0) * 100:.2f}%'
    )


# 입력 및 Weight
input_q = load('input_y.npy')

w1 = load('conv1_weight.npy')
b1 = load('conv1_bias.npy')

w2 = load('conv2_weight.npy')
b2 = load('conv2_bias.npy')

w3 = load('conv3_weight.npy')
b3 = load('conv3_bias.npy')


# Conv1: F15 × F14 = F29
acc1 = conv2d_int(input_q, w1, b1, padding=4)
relu1_acc = np.maximum(acc1, 0)
relu1_q = saturate_int16(round_shift(relu1_acc, 14))


# Conv2: F15 × F15 = F30
acc2 = conv2d_int(relu1_q, w2, b2, padding=2)
relu2_acc = np.maximum(acc2, 0)
relu2_q = saturate_int16(round_shift(relu2_acc, 16))


# Conv3: F14 × F15 = F29
acc3 = conv2d_int(relu2_q, w3, b3, padding=2)
output_q = round_shift(acc3, 14)

# FP32의 clamp(0, 1)과 동일하게 처리
output_q = np.clip(output_q, 0, 32767).astype(np.int16)


# 레이어별 FP32 양자화 결과와 비교
compare('ReLU1', relu1_q, load('relu1_output.npy'))
compare('ReLU2', relu2_q, load('relu2_output.npy'))
compare('Output', output_q, load('output_fp32.npy'))


# 48-bit accumulator로 충분한지 확인
print()
print('Conv1 accumulator bits:', accumulator_bits(acc1))
print('Conv2 accumulator bits:', accumulator_bits(acc2))
print('Conv3 accumulator bits:', accumulator_bits(acc3))


# RTL 비교용 결과 저장
np.save(output_dir / 'conv1_acc.npy', acc1)
np.save(output_dir / 'relu1_q.npy', relu1_q)

np.save(output_dir / 'conv2_acc.npy', acc2)
np.save(output_dir / 'relu2_q.npy', relu2_q)

np.save(output_dir / 'conv3_acc.npy', acc3)
np.save(output_dir / 'output_q.npy', output_q)

print('INT16 Golden Data saved:', output_dir)