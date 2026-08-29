"""256x256 SRCNN FP32, tiled INT16, Bicubic 품질과 수치 오차를 평가한다."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import statistics
import time
from pathlib import Path

import numpy as np
import torch
from PIL import Image

from models import SRCNN
from utils import convert_rgb_to_ycbcr


F15_SCALE = 1 << 15


def sha256_array(array: np.ndarray) -> str:
    return hashlib.sha256(np.ascontiguousarray(array).tobytes()).hexdigest()


def crop_border(array: np.ndarray, crop: int) -> np.ndarray:
    if crop < 0:
        raise ValueError('crop must be non-negative')
    if crop == 0:
        return array
    if array.shape[-2] <= crop * 2 or array.shape[-1] <= crop * 2:
        raise ValueError(f'crop={crop} is too large for shape {array.shape}')
    return array[..., crop:-crop, crop:-crop]


def calculate_metrics(reference: np.ndarray, actual: np.ndarray, crop: int = 0) -> dict:
    reference = np.asarray(reference, dtype=np.float64)
    actual = np.asarray(actual, dtype=np.float64)
    if reference.shape != actual.shape:
        raise ValueError(f'shape mismatch: {reference.shape} != {actual.shape}')

    reference = crop_border(reference, crop)
    actual = crop_border(actual, crop)
    difference = actual - reference
    absolute = np.abs(difference)
    mse = float(np.mean(difference ** 2))
    rmse = math.sqrt(mse)
    psnr = math.inf if mse == 0.0 else 10.0 * math.log10(1.0 / mse)
    return {
        'crop': crop,
        'sample_count': int(difference.size),
        'maximum_absolute_error': float(np.max(absolute)),
        'mean_absolute_error': float(np.mean(absolute)),
        'mse': mse,
        'rmse': rmse,
        'psnr_db': psnr,
    }


def calculate_lsb_metrics(fp32: np.ndarray, int16_output: np.ndarray, crop: int = 0) -> dict:
    fp32_q = np.clip(np.rint(fp32 * F15_SCALE), 0, 32767).astype(np.int64)
    int16_values = int16_output.astype(np.int64)
    fp32_q = crop_border(fp32_q, crop)
    int16_values = crop_border(int16_values, crop)
    difference = int16_values - fp32_q
    absolute = np.abs(difference)
    return {
        'crop': crop,
        'maximum_error_lsb': int(np.max(absolute)),
        'mean_error_lsb': float(np.mean(absolute)),
        'rmse_lsb': float(np.sqrt(np.mean(difference.astype(np.float64) ** 2))),
        'exact_percent': float(np.mean(difference == 0) * 100.0),
    }


def load_hr_y(path: Path) -> np.ndarray:
    rgb = np.asarray(Image.open(path).convert('RGB'), dtype=np.float32)
    return (convert_rgb_to_ycbcr(rgb)[..., 0] / 255.0).astype(np.float32)


def choose_device(name: str) -> torch.device:
    if name == 'auto':
        return torch.device('cuda:0' if torch.cuda.is_available() else 'cpu')
    if name == 'cuda' and not torch.cuda.is_available():
        raise RuntimeError('CUDA was requested but is not available')
    return torch.device(name)


def synchronize(device: torch.device) -> None:
    if device.type == 'cuda':
        torch.cuda.synchronize(device)


def run_fp32(
    input_y: np.ndarray,
    weights_path: Path,
    device: torch.device,
    warmup: int,
    repeats: int,
) -> tuple[np.ndarray, dict, dict]:
    if input_y.shape != (1, 1, 256, 256):
        raise ValueError(f'FP32 input must be (1, 1, 256, 256), got {input_y.shape}')
    if warmup < 0 or repeats <= 0:
        raise ValueError('warmup must be >= 0 and repeats must be > 0')

    model = SRCNN().to(device)
    checkpoint = torch.load(weights_path, map_location=device)
    model.load_state_dict(checkpoint)
    model.eval()

    tensor = torch.from_numpy(input_y.astype(np.float32, copy=False)).to(device)
    with torch.no_grad():
        for _ in range(warmup):
            model(tensor).clamp_(0.0, 1.0)
        synchronize(device)

        timings = []
        output = None
        for _ in range(repeats):
            synchronize(device)
            started = time.perf_counter()
            output = model(tensor).clamp_(0.0, 1.0)
            synchronize(device)
            timings.append(time.perf_counter() - started)

    with torch.no_grad():
        conv1 = model.conv1(tensor)
        relu1 = torch.relu(conv1)
        conv2 = model.conv2(relu1)
        relu2 = torch.relu(conv2)
        conv3 = model.conv3(relu2)

    result = output.detach().cpu().numpy()
    timing = {
        'device': str(device),
        'warmup_runs': warmup,
        'measured_runs': repeats,
        'minimum_seconds': min(timings),
        'maximum_seconds': max(timings),
        'mean_seconds': statistics.mean(timings),
        'median_seconds': statistics.median(timings),
        'all_seconds': timings,
    }
    layer_ranges = {
        'input': {
            'minimum': float(tensor.min()),
            'maximum': float(tensor.max()),
        },
        'relu1_f15': {
            'minimum': float(relu1.min()),
            'maximum': float(relu1.max()),
            'representable_maximum': 32767 / 32768,
            'values_above_representable_maximum': int(
                torch.count_nonzero(relu1 > (32767 / 32768)).item()
            ),
        },
        'relu2_f14': {
            'minimum': float(relu2.min()),
            'maximum': float(relu2.max()),
            'representable_maximum': 32767 / 16384,
            'values_above_representable_maximum': int(
                torch.count_nonzero(relu2 > (32767 / 16384)).item()
            ),
        },
        'conv3_before_clamp': {
            'minimum': float(conv3.min()),
            'maximum': float(conv3.max()),
            'values_below_zero': int(torch.count_nonzero(conv3 < 0).item()),
            'values_above_one': int(torch.count_nonzero(conv3 > 1).item()),
        },
    }
    return result, timing, layer_ranges


def save_gray(path: Path, normalized: np.ndarray) -> None:
    image = np.rint(np.clip(normalized, 0.0, 1.0) * 255.0).astype(np.uint8)
    Image.fromarray(image, mode='L').save(path)


def write_metrics_csv(path: Path, comparisons: dict) -> None:
    fields = [
        'comparison', 'crop', 'sample_count', 'maximum_absolute_error',
        'mean_absolute_error', 'mse', 'rmse', 'psnr_db',
    ]
    with path.open('w', encoding='utf-8-sig', newline='') as file:
        writer = csv.DictWriter(file, fieldnames=fields)
        writer.writeheader()
        for comparison, by_crop in comparisons.items():
            for metrics in by_crop.values():
                writer.writerow({'comparison': comparison, **metrics})


def main() -> None:
    parser = argparse.ArgumentParser(description='Evaluate full 256x256 SRCNN outputs.')
    parser.add_argument('--weights', type=Path, default=Path('weights/srcnn_x2.pth'))
    parser.add_argument(
        '--fp32-input',
        type=Path,
        default=Path('full_image_data/input_y_f32.npy'),
    )
    parser.add_argument(
        '--int16-output',
        type=Path,
        default=Path('full_image_golden/output_merged_int16.npy'),
    )
    parser.add_argument('--hr-image', type=Path, default=Path('full_image_data/hr_256.png'))
    parser.add_argument(
        '--int16-manifest',
        type=Path,
        default=Path('full_image_golden/manifest.json'),
    )
    parser.add_argument('--output-dir', type=Path, default=Path('full_image_evaluation'))
    parser.add_argument('--device', choices=('auto', 'cpu', 'cuda'), default='auto')
    parser.add_argument('--warmup', type=int, default=1)
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--crop', type=int, default=2)
    args = parser.parse_args()

    device = choose_device(args.device)
    input_y = np.load(args.fp32_input).astype(np.float32)
    int16_output = np.load(args.int16_output)
    if int16_output.shape != (1, 256, 256):
        raise ValueError(f'INT16 output must be (1, 256, 256), got {int16_output.shape}')
    int16_real = int16_output.astype(np.float64) / F15_SCALE

    fp32_output, fp32_timing, layer_ranges = run_fp32(
        input_y,
        args.weights,
        device,
        args.warmup,
        args.repeats,
    )
    fp32_image = fp32_output[0, 0]
    int16_image = int16_real[0]
    bicubic_image = input_y[0, 0]

    arrays = {
        'int16_vs_fp32': (fp32_image, int16_image),
    }
    hr_y = None
    if args.hr_image.exists():
        hr_y = load_hr_y(args.hr_image)
        if hr_y.shape != (256, 256):
            raise ValueError(f'HR Y must be 256x256, got {hr_y.shape}')
        arrays.update({
            'bicubic_vs_hr': (hr_y, bicubic_image),
            'fp32_vs_hr': (hr_y, fp32_image),
            'int16_vs_hr': (hr_y, int16_image),
        })

    # Full image, SRCNN 평가 관례의 2-pixel crop, Halo radius 8 crop을 항상 기록한다.
    crops = sorted({0, 2, 8, args.crop})
    comparisons = {
        name: {
            f'crop_{crop}': calculate_metrics(reference, actual, crop)
            for crop in crops
        }
        for name, (reference, actual) in arrays.items()
    }
    lsb_metrics = {
        f'crop_{crop}': calculate_lsb_metrics(fp32_image, int16_output[0], crop)
        for crop in crops
    }

    int16_golden_seconds = None
    if args.int16_manifest.exists():
        manifest = json.loads(args.int16_manifest.read_text(encoding='utf-8'))
        int16_golden_seconds = manifest.get('elapsed_seconds')

    args.output_dir.mkdir(parents=True, exist_ok=True)
    np.save(args.output_dir / 'fp32_output.npy', fp32_output)
    save_gray(args.output_dir / 'bicubic_y_256.png', bicubic_image)
    save_gray(args.output_dir / 'fp32_output_y_256.png', fp32_image)
    save_gray(args.output_dir / 'int16_output_y_256.png', int16_image)
    if hr_y is not None:
        save_gray(args.output_dir / 'hr_y_256.png', hr_y)

    absolute_difference = np.abs(fp32_image - int16_image)
    if np.max(absolute_difference) > 0:
        difference_preview = absolute_difference / np.max(absolute_difference)
    else:
        difference_preview = absolute_difference
    save_gray(args.output_dir / 'fp32_int16_abs_diff_normalized.png', difference_preview)

    quality_summary = None
    if hr_y is not None:
        bicubic_psnr = comparisons['bicubic_vs_hr']['crop_0']['psnr_db']
        fp32_psnr = comparisons['fp32_vs_hr']['crop_0']['psnr_db']
        int16_psnr = comparisons['int16_vs_hr']['crop_0']['psnr_db']
        quality_summary = {
            'bicubic_psnr_db': bicubic_psnr,
            'fp32_psnr_db': fp32_psnr,
            'int16_psnr_db': int16_psnr,
            'fp32_improvement_over_bicubic_db': fp32_psnr - bicubic_psnr,
            'int16_improvement_over_bicubic_db': int16_psnr - bicubic_psnr,
            'int16_quality_penalty_vs_fp32_db': fp32_psnr - int16_psnr,
        }

    report = {
        'model': 'SRCNN x2 9-5-5',
        'input_shape': list(input_y.shape),
        'int16_output_shape': list(int16_output.shape),
        'int16_scale': F15_SCALE,
        'hashes': {
            'input_y_f32': sha256_array(input_y),
            'fp32_output': sha256_array(fp32_output),
            'int16_output': sha256_array(int16_output),
        },
        'timing': {
            'fp32': fp32_timing,
            'python_int16_tiled_golden_seconds': int16_golden_seconds,
            'note': 'Python timing is not FPGA latency.',
        },
        'fp32_layer_ranges_and_quantization_risk': layer_ranges,
        'quality_summary_full_image': quality_summary,
        'comparisons': comparisons,
        'int16_vs_fp32_lsb': lsb_metrics,
    }

    with (args.output_dir / 'metrics.json').open('w', encoding='utf-8') as file:
        json.dump(report, file, ensure_ascii=False, indent=2, allow_nan=False)
        file.write('\n')
    write_metrics_csv(args.output_dir / 'metrics.csv', comparisons)

    print('Device:', device)
    print('FP32 median time:', f'{fp32_timing["median_seconds"]:.6f}s')
    for name, by_crop in comparisons.items():
        for label, metrics in by_crop.items():
            print(
                f'{name:16s} {label:7s} '
                f'PSNR={metrics["psnr_db"]:10.6f} dB '
                f'max={metrics["maximum_absolute_error"]:.10f} '
                f'RMSE={metrics["rmse"]:.10f}'
            )
    for label, metrics in lsb_metrics.items():
        print(
            f'INT16 vs FP32 LSB {label:7s} '
            f'max={metrics["maximum_error_lsb"]} '
            f'mean={metrics["mean_error_lsb"]:.6f} '
            f'exact={metrics["exact_percent"]:.4f}%'
        )
    print('Report:', (args.output_dir / 'metrics.json').resolve())


if __name__ == '__main__':
    main()
