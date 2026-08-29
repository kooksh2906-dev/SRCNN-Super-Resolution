"""SRCNN NPU Rev5 PC<->Vitis UART binary packet codec.

All multi-byte integers and INT16 pixels use little-endian byte order. Rev5
stores the CRC32 of the payload in each header; it does not append a trailing
CRC field.
"""
from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass
from enum import IntEnum

import numpy as np


REQUEST_MAGIC = b"SRQ1"
RESPONSE_MAGIC = b"SRS1"
VERSION = 1
GRID_SIZE = 16
INPUT_PIXEL_COUNT = 32 * 32
RESULT_PIXEL_COUNT = 16 * 16
INPUT_PAYLOAD_BYTES = INPUT_PIXEL_COUNT * 2
RESULT_PAYLOAD_BYTES = RESULT_PIXEL_COUNT * 2
MAX_PAYLOAD_BYTES = INPUT_PAYLOAD_BYTES

COMMAND_PROCESS_TILE = 1

# request: magic, version, command, packed tile coordinates, sequence,
# payload_length, payload_crc32
REQUEST_HEADER = struct.Struct("<4sBBHIII")

# response: magic, version, status, returned_command, reserved, sequence,
# payload_length, payload_crc32, cycle_count, npu_status
RESPONSE_HEADER = struct.Struct("<4sBBBBIIIII")

class PacketType(IntEnum):
    RUN_TILE = 0x01
    TILE_RESULT = 0x81
    ERROR = 0xE0


class Status(IntEnum):
    OK = 0
    BAD_VERSION = 1
    BAD_COMMAND = 2
    BAD_LENGTH = 3
    BAD_CRC = 4
    RX_TIMEOUT = 5
    NPU_TIMEOUT = 6
    NPU_ERROR = 7
    HW_VERSION = 8
    BAD_TILE_POSITION = 9
    TILE_POS_IO = 10


# Kept only for source compatibility. Rev5 has no last-tile field on the wire.
FLAG_LAST_TILE = 1 << 0


class ProtocolError(ValueError):
    pass


@dataclass(frozen=True)
class Packet:
    packet_type: PacketType
    tile_id: int
    tile_x: int
    tile_y: int
    status: Status
    flags: int
    payload: bytes
    cycle_count: int
    npu_status: int = 0


def tile_id_to_xy(tile_id: int) -> tuple[int, int]:
    if not 0 <= tile_id < GRID_SIZE * GRID_SIZE:
        raise ProtocolError(f"tile_id must be in [0, 255], got {tile_id}")
    return tile_id % GRID_SIZE, tile_id // GRID_SIZE


def _validate_uint(name: str, value: int, bits: int) -> None:
    if not 0 <= value < (1 << bits):
        raise ProtocolError(f"{name} must fit uint{bits}, got {value}")


def _payload_crc32(payload: bytes) -> int:
    return zlib.crc32(payload) & 0xFFFFFFFF


def encode_packet(
    packet_type: PacketType,
    tile_id: int,
    payload: bytes = b"",
    *,
    status: Status = Status.OK,
    flags: int = 0,
    cycle_count: int = 0,
    npu_status: int = 0,
) -> bytes:
    packet_type = PacketType(packet_type)
    status = Status(status)
    tile_x, tile_y = tile_id_to_xy(tile_id)
    payload = bytes(payload)

    if len(payload) > MAX_PAYLOAD_BYTES:
        raise ProtocolError(
            f"payload is too large: {len(payload)} > {MAX_PAYLOAD_BYTES}"
        )
    _validate_uint("flags", flags, 8)
    _validate_uint("cycle_count", cycle_count, 32)
    _validate_uint("npu_status", npu_status, 32)

    if packet_type == PacketType.RUN_TILE:
        if status != Status.OK or cycle_count != 0 or npu_status != 0:
            raise ProtocolError(
                "RUN_TILE must have status=OK, cycle_count=0, and npu_status=0"
            )
        if flags & ~FLAG_LAST_TILE:
            raise ProtocolError(f"unsupported Rev5 request flags: 0x{flags:02X}")

        packed_coordinates = ((tile_y & 0xFF) << 8) | (tile_x & 0xFF)
        header = REQUEST_HEADER.pack(
            REQUEST_MAGIC,
            VERSION,
            COMMAND_PROCESS_TILE,
            packed_coordinates,
            tile_id,
            len(payload),
            _payload_crc32(payload) if payload else 0,
        )
        return header + payload

    if packet_type not in (PacketType.TILE_RESULT, PacketType.ERROR):
        raise ProtocolError(f"unsupported packet type: {packet_type.name}")
    if flags != 0:
        raise ProtocolError("Rev5 responses do not carry flags")

    header = RESPONSE_HEADER.pack(
        RESPONSE_MAGIC,
        VERSION,
        int(status),
        COMMAND_PROCESS_TILE,
        0,
        tile_id,
        len(payload),
        _payload_crc32(payload) if payload else 0,
        cycle_count,
        npu_status,
    )
    return header + payload


def _decode_request(data: bytes) -> Packet:
    if len(data) < REQUEST_HEADER.size:
        raise ProtocolError(
            f"request is shorter than {REQUEST_HEADER.size} bytes"
        )

    (
        magic,
        version,
        command,
        packed_coordinates,
        sequence,
        payload_length,
        payload_crc32,
    ) = REQUEST_HEADER.unpack_from(data)

    if magic != REQUEST_MAGIC:
        raise ProtocolError(f"invalid request magic: {magic!r}")
    if version != VERSION:
        raise ProtocolError(f"unsupported request version: {version}")
    if command != COMMAND_PROCESS_TILE:
        raise ProtocolError(f"unsupported request command: {command}")
    if payload_length > MAX_PAYLOAD_BYTES:
        raise ProtocolError(f"payload_length is too large: {payload_length}")

    expected_size = REQUEST_HEADER.size + payload_length
    if len(data) != expected_size:
        raise ProtocolError(
            f"request length mismatch: expected {expected_size}, got {len(data)}"
        )

    tile_id = sequence
    tile_x = packed_coordinates & 0xFF
    tile_y = (packed_coordinates >> 8) & 0xFF
    expected_x, expected_y = tile_id_to_xy(tile_id)
    if (tile_x, tile_y) != (expected_x, expected_y):
        raise ProtocolError(
            f"Tile coordinate mismatch: id={tile_id} means "
            f"({expected_x}, {expected_y}), got ({tile_x}, {tile_y})"
        )

    payload = data[REQUEST_HEADER.size:]
    calculated_crc = _payload_crc32(payload) if payload else 0
    if payload_crc32 != calculated_crc:
        raise ProtocolError(
            f"CRC32 mismatch: received=0x{payload_crc32:08X}, "
            f"calculated=0x{calculated_crc:08X}"
        )

    return Packet(
        packet_type=PacketType.RUN_TILE,
        tile_id=tile_id,
        tile_x=tile_x,
        tile_y=tile_y,
        status=Status.OK,
        flags=0,
        payload=payload,
        cycle_count=0,
        npu_status=0,
    )


def _decode_response(data: bytes) -> Packet:
    if len(data) < RESPONSE_HEADER.size:
        raise ProtocolError(
            f"response is shorter than {RESPONSE_HEADER.size} bytes"
        )

    (
        magic,
        version,
        status_raw,
        returned_command,
        reserved,
        sequence,
        payload_length,
        payload_crc32,
        cycle_count,
        npu_status,
    ) = RESPONSE_HEADER.unpack_from(data)

    if magic != RESPONSE_MAGIC:
        raise ProtocolError(f"invalid response magic: {magic!r}")
    if version != VERSION:
        raise ProtocolError(f"unsupported response version: {version}")
    if returned_command != COMMAND_PROCESS_TILE:
        raise ProtocolError(
            f"unexpected response command: {returned_command}"
        )
    if reserved != 0:
        raise ProtocolError(f"response reserved field is nonzero: {reserved}")
    if payload_length > RESULT_PAYLOAD_BYTES:
        raise ProtocolError(
            f"response payload_length is too large: {payload_length}"
        )

    expected_size = RESPONSE_HEADER.size + payload_length
    if len(data) != expected_size:
        raise ProtocolError(
            f"response length mismatch: expected {expected_size}, got {len(data)}"
        )

    try:
        status = Status(status_raw)
    except ValueError as error:
        raise ProtocolError(f"unknown status: {status_raw}") from error

    tile_id = sequence
    tile_x, tile_y = tile_id_to_xy(tile_id)
    payload = data[RESPONSE_HEADER.size:]
    calculated_crc = _payload_crc32(payload) if payload else 0
    if payload_crc32 != calculated_crc:
        raise ProtocolError(
            f"CRC32 mismatch: received=0x{payload_crc32:08X}, "
            f"calculated=0x{calculated_crc:08X}"
        )

    return Packet(
        packet_type=PacketType.TILE_RESULT,
        tile_id=tile_id,
        tile_x=tile_x,
        tile_y=tile_y,
        status=status,
        flags=0,
        payload=payload,
        cycle_count=cycle_count,
        npu_status=npu_status,
    )


def decode_packet(data: bytes) -> Packet:
    data = bytes(data)
    if len(data) < 4:
        raise ProtocolError("Packet is shorter than the 4-byte magic")
    if data[:4] == REQUEST_MAGIC:
        return _decode_request(data)
    if data[:4] == RESPONSE_MAGIC:
        return _decode_response(data)
    raise ProtocolError(f"invalid magic: {data[:4]!r}")


def int16_to_payload(pixels: np.ndarray, expected_count: int) -> bytes:
    pixels = np.asarray(pixels)
    if pixels.size != expected_count:
        raise ProtocolError(f"expected {expected_count} pixels, got {pixels.size}")
    if not np.issubdtype(pixels.dtype, np.signedinteger):
        raise ProtocolError(f"pixels must be signed integer, got {pixels.dtype}")

    values = pixels.astype(np.int64, copy=False).reshape(-1, order="C")
    if np.any(values < -32768) or np.any(values > 32767):
        raise ProtocolError("pixel value exceeds signed INT16 range")
    return values.astype("<i2").tobytes(order="C")


def payload_to_int16(payload: bytes, expected_count: int) -> np.ndarray:
    expected_bytes = expected_count * 2
    if len(payload) != expected_bytes:
        raise ProtocolError(
            f"expected {expected_bytes} payload bytes, got {len(payload)}"
        )
    return np.frombuffer(payload, dtype="<i2").astype(np.int16, copy=True)


def encode_run_tile(
    tile_id: int,
    pixels: np.ndarray,
    *,
    last_tile: bool = False,
) -> bytes:
    payload = int16_to_payload(pixels, INPUT_PIXEL_COUNT)
    flags = FLAG_LAST_TILE if last_tile else 0
    return encode_packet(PacketType.RUN_TILE, tile_id, payload, flags=flags)


def decode_run_tile(data: bytes) -> tuple[Packet, np.ndarray]:
    packet = decode_packet(data)
    if packet.packet_type != PacketType.RUN_TILE:
        raise ProtocolError(f"expected RUN_TILE, got {packet.packet_type.name}")
    if packet.status != Status.OK or packet.cycle_count != 0:
        raise ProtocolError("RUN_TILE must have status=OK and cycle_count=0")
    pixels = payload_to_int16(packet.payload, INPUT_PIXEL_COUNT)
    return packet, pixels.reshape(1, 32, 32)


def encode_tile_result(
    tile_id: int,
    pixels: np.ndarray,
    *,
    cycle_count: int,
    status: Status = Status.OK,
    npu_status: int | None = None,
) -> bytes:
    status = Status(status)
    if status == Status.OK:
        payload = int16_to_payload(pixels, RESULT_PIXEL_COUNT)
    else:
        payload = b""

    if npu_status is None:
        npu_status = 0x00000002 if status == Status.OK else 0

    return encode_packet(
        PacketType.TILE_RESULT,
        tile_id,
        payload,
        status=status,
        cycle_count=cycle_count,
        npu_status=npu_status,
    )


def decode_tile_result(data: bytes) -> tuple[Packet, np.ndarray | None]:
    packet = decode_packet(data)
    if packet.packet_type != PacketType.TILE_RESULT:
        raise ProtocolError(
            f"expected TILE_RESULT, got {packet.packet_type.name}"
        )
    if packet.status != Status.OK:
        if packet.payload:
            raise ProtocolError("error TILE_RESULT must have an empty payload")
        return packet, None

    if packet.npu_status != 0x00000002:
        raise ProtocolError(
            f"successful TILE_RESULT lacks DONE status: "
            f"npu_status=0x{packet.npu_status:08X}"
        )

    pixels = payload_to_int16(packet.payload, RESULT_PIXEL_COUNT)
    return packet, pixels.reshape(1, 16, 16)
