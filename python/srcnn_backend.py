"""UI와 SRCNN 연산 구현을 분리하는 공통 Tile Backend.

Python Golden과 실제 ZYBO UART는 동일한 ``run_tile()`` 계약을 사용한다.
UI는 어떤 구현이 선택되었는지 알 필요가 없다.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol, runtime_checkable

import numpy as np

from srcnn_int16_core import load_parameters, run_srcnn_int16
from uart_host import SerialTransport, Transport
from uart_protocol import ProtocolError, Status, decode_tile_result, encode_run_tile


TILE_COUNT = 256
INPUT_TILE_SHAPE = (1, 32, 32)
VALID_OUTPUT_SHAPE = (1, 16, 16)
VALID_SLICE = (slice(None), slice(8, 24), slice(8, 24))


@dataclass(frozen=True)
class TileResult:
    """Backend가 Tile 한 개를 처리한 결과."""

    tile_id: int
    output: np.ndarray
    cycle_count: int
    elapsed_seconds: float
    backend_name: str


@runtime_checkable
class SrcnnBackend(Protocol):
    """Python과 ZYBO Backend가 공통으로 지켜야 하는 계약."""

    name: str

    def run_tile(self, tile_id: int, input_tile: np.ndarray) -> TileResult:
        ...

    def close(self) -> None:
        ...


def validate_tile_id(tile_id: int) -> None:
    if not 0 <= tile_id < TILE_COUNT:
        raise ValueError(f'tile_id must be in [0, {TILE_COUNT - 1}], got {tile_id}')


def validate_input_tile(input_tile: np.ndarray) -> np.ndarray:
    tile = np.asarray(input_tile)
    if tile.shape != INPUT_TILE_SHAPE:
        raise ValueError(f'expected input Tile shape {INPUT_TILE_SHAPE}, got {tile.shape}')
    if tile.dtype != np.int16:
        raise TypeError(f'expected input Tile dtype int16, got {tile.dtype}')
    return np.ascontiguousarray(tile)


def validate_output_tile(output_tile: np.ndarray) -> np.ndarray:
    tile = np.asarray(output_tile)
    if tile.shape != VALID_OUTPUT_SHAPE:
        raise ValueError(
            f'expected output Tile shape {VALID_OUTPUT_SHAPE}, got {tile.shape}'
        )
    if tile.dtype != np.int16:
        raise TypeError(f'expected output Tile dtype int16, got {tile.dtype}')
    return np.ascontiguousarray(tile)


class PythonInt16Backend:
    """FPGA와 같은 고정소수점 규칙을 Python에서 계산하는 임시 Backend."""

    name = 'python-int16'

    def __init__(
        self,
        parameter_dir: Path | str = Path('dump_int16'),
        valid_masks: np.ndarray | Path | str = Path(
            'full_image_data/tile_valid_masks.npy'
        ),
    ):
        self.parameters = load_parameters(Path(parameter_dir))

        if isinstance(valid_masks, (str, Path)):
            valid_masks = np.load(Path(valid_masks))
        masks = np.asarray(valid_masks)
        expected_shape = (TILE_COUNT, 1, 32, 32)
        if masks.shape != expected_shape:
            raise ValueError(
                f'expected valid mask shape {expected_shape}, got {masks.shape}'
            )
        self.valid_masks = masks.astype(bool, copy=False)
        self._closed = False

    def run_tile(self, tile_id: int, input_tile: np.ndarray) -> TileResult:
        if self._closed:
            raise RuntimeError('PythonInt16Backend is closed')
        validate_tile_id(tile_id)
        tile = validate_input_tile(input_tile)

        started = time.perf_counter()
        output = run_srcnn_int16(
            tile[np.newaxis, ...],
            self.parameters,
            valid_mask=self.valid_masks[tile_id:tile_id + 1],
        )
        valid_output = validate_output_tile(output[0][VALID_SLICE].copy())
        elapsed = time.perf_counter() - started

        return TileResult(
            tile_id=tile_id,
            output=valid_output,
            cycle_count=0,
            elapsed_seconds=elapsed,
            backend_name=self.name,
        )

    def close(self) -> None:
        self._closed = True


class ZyboUartBackend:
    """RUN_TILE/TILE_RESULT UART Packet으로 실제 ZYBO를 실행하는 Backend.

    테스트에서는 ``transport``에 MockTransport를 주입할 수 있고, 실제 보드에서는
    ``port``를 지정하면 SerialTransport를 내부에서 생성한다.
    """

    name = 'zybo-uart'

    def __init__(
        self,
        port: str | None = None,
        *,
        baudrate: int = 115200,
        timeout: float = 10.0,
        retries: int = 0,
        transport: Transport | None = None,
    ):
        if retries < 0:
            raise ValueError('retries must be non-negative')
        if transport is None and not port:
            raise ValueError('port is required when transport is not supplied')
        if transport is not None and port is not None:
            raise ValueError('provide either port or transport, not both')

        self.transport = (
            transport
            if transport is not None
            else SerialTransport(port, baudrate, timeout)
        )
        self.retries = retries
        self._closed = False

    def run_tile(self, tile_id: int, input_tile: np.ndarray) -> TileResult:
        if self._closed:
            raise RuntimeError('ZyboUartBackend is closed')
        validate_tile_id(tile_id)
        tile = validate_input_tile(input_tile)
        request = encode_run_tile(
            tile_id,
            tile,
            last_tile=(tile_id == TILE_COUNT - 1),
        )

        started = time.perf_counter()
        last_error: Exception | None = None
        for attempt in range(self.retries + 1):
            try:
                response = self.transport.transact(request)
                packet, output = decode_tile_result(response)
                if packet.tile_id != tile_id:
                    raise ProtocolError(
                        f'response Tile ID mismatch: {packet.tile_id} != {tile_id}'
                    )
                if packet.status != Status.OK or output is None:
                    raise ProtocolError(
                        f'Tile {tile_id} failed: {packet.status.name}'
                    )
                valid_output = validate_output_tile(output)
                elapsed = time.perf_counter() - started
                return TileResult(
                    tile_id=tile_id,
                    output=valid_output,
                    cycle_count=int(packet.cycle_count),
                    elapsed_seconds=elapsed,
                    backend_name=self.name,
                )
            except (ProtocolError, TimeoutError, OSError) as error:
                last_error = error
                if attempt == self.retries:
                    break

        raise RuntimeError(
            f'Tile {tile_id} failed after {self.retries + 1} attempts'
        ) from last_error

    def close(self) -> None:
        if not self._closed:
            self.transport.close()
            self._closed = True

    def __enter__(self) -> 'ZyboUartBackend':
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        self.close()
