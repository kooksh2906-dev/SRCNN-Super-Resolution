"""임시 UI에서 사용하는 이미지 전처리와 SRCNN 출력 복원."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

from prepare_full_image import HR_SIZE, INPUT_FRACTION_BITS, LR_SIZE, quantize_input_y
from tile_halo import split_halo_tiles
from utils import convert_rgb_to_ycbcr, convert_ycbcr_to_rgb


@dataclass(frozen=True)
class DemoImage:
    source_mode: str
    source_rgb: Image.Image
    reference_hr_rgb: Image.Image | None
    lr_rgb: Image.Image
    bicubic_rgb: Image.Image
    bicubic_ycbcr: np.ndarray
    input_tiles_int16: np.ndarray


def prepare_demo_image(image: Image.Image) -> DemoImage:
    """128×128 LR 또는 256×256 HR를 UI/Backend용 데이터로 변환한다."""
    source = image.convert('RGB')
    if source.size == LR_SIZE:
        source_mode = 'LR 128×128'
        reference_hr = None
        lr = source.copy()
    elif source.size == HR_SIZE:
        source_mode = 'HR 256×256 (평가용)'
        reference_hr = source.copy()
        lr = source.resize(LR_SIZE, resample=Image.Resampling.BICUBIC)
    else:
        raise ValueError(
            f'이미지는 128×128 LR 또는 256×256 HR이어야 합니다. '
            f'선택한 크기: {source.width}×{source.height}'
        )

    bicubic = lr.resize(HR_SIZE, resample=Image.Resampling.BICUBIC)
    bicubic_ycbcr = convert_rgb_to_ycbcr(
        np.asarray(bicubic, dtype=np.float32)
    ).astype(np.float32)
    input_y = (bicubic_ycbcr[..., 0] / 255.0)[np.newaxis, ...]
    input_y_int16 = quantize_input_y(input_y)
    input_tiles = split_halo_tiles(input_y_int16)

    return DemoImage(
        source_mode=source_mode,
        source_rgb=source,
        reference_hr_rgb=reference_hr,
        lr_rgb=lr,
        bicubic_rgb=bicubic,
        bicubic_ycbcr=bicubic_ycbcr,
        input_tiles_int16=np.ascontiguousarray(input_tiles),
    )


def load_demo_image(path: Path | str) -> DemoImage:
    with Image.open(path) as image:
        return prepare_demo_image(image)


def reconstruct_sr_rgb(demo: DemoImage, output_y_int16: np.ndarray) -> Image.Image:
    """SRCNN의 Q15 Y 출력을 Bicubic Cb/Cr과 결합해 RGB 이미지로 만든다."""
    output = np.asarray(output_y_int16)
    if output.shape != (1, 256, 256):
        raise ValueError(f'expected output shape (1, 256, 256), got {output.shape}')
    if output.dtype != np.int16:
        raise TypeError(f'expected output dtype int16, got {output.dtype}')

    ycbcr = demo.bicubic_ycbcr.copy()
    y_normalized = np.clip(
        output[0].astype(np.float32) / float(1 << INPUT_FRACTION_BITS),
        0.0,
        1.0,
    )
    ycbcr[..., 0] = y_normalized * 255.0
    rgb = convert_ycbcr_to_rgb(ycbcr)
    rgb_u8 = np.clip(np.rint(rgb), 0, 255).astype(np.uint8)
    return Image.fromarray(rgb_u8, mode='RGB')


def calculate_y_psnr(reference: Image.Image, actual: Image.Image) -> float:
    """두 RGB 이미지의 Y 채널 PSNR을 계산한다."""
    if reference.size != actual.size:
        raise ValueError(f'image size mismatch: {reference.size} != {actual.size}')
    reference_y = convert_rgb_to_ycbcr(
        np.asarray(reference.convert('RGB'), dtype=np.float32)
    )[..., 0] / 255.0
    actual_y = convert_rgb_to_ycbcr(
        np.asarray(actual.convert('RGB'), dtype=np.float32)
    )[..., 0] / 255.0
    mse = float(np.mean((reference_y - actual_y) ** 2))
    if mse == 0.0:
        return float('inf')
    return float(10.0 * np.log10(1.0 / mse))
