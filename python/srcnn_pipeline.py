"""UI에 의존하지 않는 SRCNN 256-Tile 실행 파이프라인."""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Callable

import numpy as np

from srcnn_backend import (
    TILE_COUNT,
    SrcnnBackend,
    TileResult,
    validate_output_tile,
)


ProgressCallback = Callable[[int, int, TileResult], None]
CancelCallback = Callable[[], bool]


class PipelineCancelled(RuntimeError):
    pass


@dataclass(frozen=True)
class PipelineResult:
    backend_name: str
    valid_tiles: np.ndarray
    merged_output: np.ndarray
    elapsed_seconds: float
    total_cycle_count: int


@dataclass(frozen=True)
class Int16Comparison:
    mismatch_count: int
    max_error_lsb: int
    mean_error_lsb: float
    exact_percent: float


def validate_input_tiles(input_tiles: np.ndarray) -> np.ndarray:
    tiles = np.asarray(input_tiles)
    expected_shape = (TILE_COUNT, 1, 32, 32)
    if tiles.shape != expected_shape:
        raise ValueError(f'expected input shape {expected_shape}, got {tiles.shape}')
    if tiles.dtype != np.int16:
        raise TypeError(f'expected input dtype int16, got {tiles.dtype}')
    return np.ascontiguousarray(tiles)


def merge_valid_tiles(valid_tiles: np.ndarray) -> np.ndarray:
    tiles = np.asarray(valid_tiles)
    expected_shape = (TILE_COUNT, 1, 16, 16)
    if tiles.shape != expected_shape:
        raise ValueError(f'expected valid output shape {expected_shape}, got {tiles.shape}')

    merged = np.empty((1, 256, 256), dtype=tiles.dtype)
    for tile_id in range(TILE_COUNT):
        tile_x = tile_id % 16
        tile_y = tile_id // 16
        x0 = tile_x * 16
        y0 = tile_y * 16
        merged[:, y0:y0 + 16, x0:x0 + 16] = tiles[tile_id]
    return merged


def run_pipeline(
    backend: SrcnnBackend,
    input_tiles: np.ndarray,
    *,
    progress_callback: ProgressCallback | None = None,
    cancel_callback: CancelCallback | None = None,
) -> PipelineResult:
    """동일한 입력 타일을 Python 또는 ZYBO Backend로 처리한다."""
    tiles = validate_input_tiles(input_tiles)
    valid_outputs = np.empty((TILE_COUNT, 1, 16, 16), dtype=np.int16)
    total_cycles = 0
    started = time.perf_counter()

    for tile_id in range(TILE_COUNT):
        if cancel_callback is not None and cancel_callback():
            raise PipelineCancelled(f'cancelled before Tile {tile_id}')

        result = backend.run_tile(tile_id, tiles[tile_id])
        if result.tile_id != tile_id:
            raise RuntimeError(
                f'Backend returned Tile {result.tile_id} while processing {tile_id}'
            )
        valid_outputs[tile_id] = validate_output_tile(result.output)
        total_cycles += int(result.cycle_count)

        if progress_callback is not None:
            progress_callback(tile_id + 1, TILE_COUNT, result)

    elapsed = time.perf_counter() - started
    return PipelineResult(
        backend_name=backend.name,
        valid_tiles=valid_outputs,
        merged_output=merge_valid_tiles(valid_outputs),
        elapsed_seconds=elapsed,
        total_cycle_count=total_cycles,
    )


def compare_int16(actual: np.ndarray, expected: np.ndarray) -> Int16Comparison:
    actual_array = np.asarray(actual)
    expected_array = np.asarray(expected)
    if actual_array.shape != expected_array.shape:
        raise ValueError(
            f'comparison shape mismatch: {actual_array.shape} != {expected_array.shape}'
        )
    if actual_array.size == 0:
        raise ValueError('cannot compare empty arrays')

    difference = actual_array.astype(np.int64) - expected_array.astype(np.int64)
    absolute = np.abs(difference)
    mismatch_count = int(np.count_nonzero(difference))
    return Int16Comparison(
        mismatch_count=mismatch_count,
        max_error_lsb=int(absolute.max()),
        mean_error_lsb=float(absolute.mean()),
        exact_percent=float((difference == 0).mean() * 100.0),
    )
