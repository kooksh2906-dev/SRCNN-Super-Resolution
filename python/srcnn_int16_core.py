"""RTL과 bit-accurate 비교하기 위한 재사용 가능한 SRCNN INT16 Golden Core."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view


@dataclass(frozen=True)
class SrcnnInt16Parameters:
    w1: np.ndarray
    b1: np.ndarray
    w2: np.ndarray
    b2: np.ndarray
    w3: np.ndarray
    b3: np.ndarray


def load_parameters(data_dir: Path) -> SrcnnInt16Parameters:
    return SrcnnInt16Parameters(
        w1=np.load(data_dir / 'conv1_weight.npy'),
        b1=np.load(data_dir / 'conv1_bias.npy'),
        w2=np.load(data_dir / 'conv2_weight.npy'),
        b2=np.load(data_dir / 'conv2_bias.npy'),
        w3=np.load(data_dir / 'conv3_weight.npy'),
        b3=np.load(data_dir / 'conv3_bias.npy'),
    )


def conv2d_int(
    x: np.ndarray,
    weight: np.ndarray,
    bias: np.ndarray,
    padding: int,
) -> np.ndarray:
    """NCHW signed integer convolution. 반환형은 INT64 accumulator이다."""
    x64 = x.astype(np.int64, copy=False)
    weight64 = weight.astype(np.int64, copy=False)
    bias64 = bias.astype(np.int64, copy=False)

    n = x64.shape[0]
    out_channels, _, kernel_h, kernel_w = weight64.shape
    padded = np.pad(
        x64,
        ((0, 0), (0, 0), (padding, padding), (padding, padding)),
        mode='constant',
    )
    windows = sliding_window_view(
        padded,
        (kernel_h, kernel_w),
        axis=(2, 3),
    )
    _, _, out_h, out_w, _, _ = windows.shape
    columns = windows.transpose(0, 2, 3, 1, 4, 5).reshape(
        n,
        out_h,
        out_w,
        -1,
    )
    weight_matrix = weight64.reshape(out_channels, -1)
    accumulator = columns @ weight_matrix.T
    accumulator = accumulator.transpose(0, 3, 1, 2)
    accumulator += bias64.reshape(1, out_channels, 1, 1)
    return accumulator


def round_shift(value: np.ndarray, shift: int) -> np.ndarray:
    """Round-to-nearest, ties-away-from-zero 후 arithmetic right shift."""
    if shift <= 0:
        raise ValueError('shift must be positive')

    half = 1 << (shift - 1)
    return np.where(
        value >= 0,
        (value + half) >> shift,
        -(((-value) + half) >> shift),
    )


def saturate_int16(value: np.ndarray) -> np.ndarray:
    return np.clip(value, -32768, 32767).astype(np.int16)


def run_srcnn_int16(
    input_q: np.ndarray,
    parameters: SrcnnInt16Parameters,
    return_layers: bool = False,
    valid_mask: np.ndarray | None = None,
) -> np.ndarray | dict[str, np.ndarray]:
    """한 개 이상의 32x32 NCHW Tile을 RTL과 같은 규칙으로 추론한다."""
    input_q = np.asarray(input_q)
    if input_q.ndim != 4 or input_q.shape[1] != 1:
        raise ValueError(f'input_q must have shape [N, 1, H, W], got {input_q.shape}')

    if valid_mask is not None:
        valid_mask = np.asarray(valid_mask)
        expected_mask_shape = (input_q.shape[0], 1, input_q.shape[2], input_q.shape[3])
        if valid_mask.shape != expected_mask_shape:
            raise ValueError(
                f'valid_mask must have shape {expected_mask_shape}, got {valid_mask.shape}'
            )
        valid_mask = valid_mask.astype(bool, copy=False)

    acc1 = conv2d_int(input_q, parameters.w1, parameters.b1, padding=4)
    relu1_q = saturate_int16(round_shift(np.maximum(acc1, 0), 14))
    if valid_mask is not None:
        relu1_q = np.where(valid_mask, relu1_q, 0).astype(np.int16)

    acc2 = conv2d_int(relu1_q, parameters.w2, parameters.b2, padding=2)
    relu2_q = saturate_int16(round_shift(np.maximum(acc2, 0), 16))
    if valid_mask is not None:
        relu2_q = np.where(valid_mask, relu2_q, 0).astype(np.int16)

    acc3 = conv2d_int(relu2_q, parameters.w3, parameters.b3, padding=2)
    output_q = np.clip(round_shift(acc3, 14), 0, 32767).astype(np.int16)

    if not return_layers:
        return output_q

    return {
        'conv1_acc': acc1,
        'relu1_q': relu1_q,
        'conv2_acc': acc2,
        'relu2_q': relu2_q,
        'conv3_acc': acc3,
        'output_q': output_q,
    }
