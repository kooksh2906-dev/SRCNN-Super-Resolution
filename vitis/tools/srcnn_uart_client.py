#!/usr/bin/env python3
"""Dependency-free Linux UART client for the Team A final firmware."""

from __future__ import annotations

import argparse
import os
import select
import struct
import sys
import termios
import time
import zlib
from pathlib import Path


DEFAULT_PORT = (
    "/dev/serial/by-id/"
    "usb-Digilent_Digilent_Adept_USB_Device_210351BD7302-if01-port0"
)
REQUEST = struct.Struct("<4sBBHIII")
RESPONSE = struct.Struct("<4sBBBBIIIII")
REQUEST_MAGIC = b"SRQ1"
RESPONSE_MAGIC = b"SRS1"
VERSION = 1
CMD_PROCESS_TILE = 1
CMD_PING = 2
INPUT_BYTES = 2048
OUTPUT_BYTES = 512

STATUS_NAMES = {
    0: "OK",
    1: "BAD_VERSION",
    2: "BAD_COMMAND",
    3: "BAD_LENGTH",
    4: "BAD_CRC",
    5: "RX_TIMEOUT",
    6: "NPU_TIMEOUT",
    7: "NPU_ERROR",
    8: "HW_VERSION",
    9: "BAD_TILE_POSITION",
    10: "TILE_POS_IO",
}


class ProtocolError(RuntimeError):
    pass


class SerialPort:
    def __init__(self, path: str, baud: int):
        speed_name = f"B{baud}"
        if not hasattr(termios, speed_name):
            raise ValueError(f"unsupported baud rate: {baud}")
        self.fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        speed = getattr(termios, speed_name)
        attrs = termios.tcgetattr(self.fd)
        attrs[0] = 0
        attrs[1] = 0
        attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        attrs[3] = 0
        attrs[4] = speed
        attrs[5] = speed
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = 0
        termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
        termios.tcflush(self.fd, termios.TCIOFLUSH)

    def close(self) -> None:
        os.close(self.fd)

    def write_all(self, data: bytes, timeout: float) -> None:
        deadline = time.monotonic() + timeout
        offset = 0
        while offset < len(data):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("UART write timed out")
            _, writable, _ = select.select([], [self.fd], [], remaining)
            if writable:
                offset += os.write(self.fd, data[offset:])

    def read_exact(self, length: int, deadline: float) -> bytes:
        data = bytearray()
        while len(data) < length:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("UART response timed out")
            readable, _, _ = select.select([self.fd], [], [], remaining)
            if readable:
                block = os.read(self.fd, length - len(data))
                if block:
                    data.extend(block)
        return bytes(data)

    def find_magic(self, magic: bytes, deadline: float) -> None:
        matched = 0
        while matched < len(magic):
            byte = self.read_exact(1, deadline)[0]
            if byte == magic[matched]:
                matched += 1
            else:
                matched = 1 if byte == magic[0] else 0


def crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


def load_tile(path: Path) -> bytes:
    if path.suffix.lower() == ".bin":
        payload = path.read_bytes()
    else:
        values: list[int] = []
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.split("//", 1)[0].split("#", 1)[0]
            for token in line.replace(",", " ").split():
                value = int(token, 0 if token.lower().startswith(("0x", "+0x", "-0x")) else 16)
                values.append(value & 0xFFFF)
        if len(values) != 1024:
            raise ValueError(f"hex input must contain 1024 INT16 values, got {len(values)}")
        payload = struct.pack("<1024H", *values)
    if len(payload) != INPUT_BYTES:
        raise ValueError(f"input must be exactly {INPUT_BYTES} bytes, got {len(payload)}")
    return payload


def receive_response(port: SerialPort, sequence: int, command: int, timeout: float):
    deadline = time.monotonic() + timeout
    while True:
        port.find_magic(RESPONSE_MAGIC, deadline)
        rest = port.read_exact(RESPONSE.size - 4, deadline)
        fields = RESPONSE.unpack(RESPONSE_MAGIC + rest)
        _, version, status, returned_command, _, returned_sequence, length, payload_crc, cycles, npu_status = fields
        if length > OUTPUT_BYTES:
            raise ProtocolError(f"response payload too large: {length}")
        payload = port.read_exact(length, deadline) if length else b""
        if payload_crc != (crc32(payload) if payload else 0):
            raise ProtocolError("response CRC mismatch")
        if returned_sequence != sequence or returned_command != command:
            continue
        if version != VERSION:
            raise ProtocolError(f"response protocol version {version}")
        return status, payload, cycles, npu_status


def transact(
    port: SerialPort,
    command: int,
    payload: bytes,
    timeout: float,
    retries: int,
    tile_x: int = 0,
    tile_y: int = 0,
):
    if not (0 <= tile_x < 16 and 0 <= tile_y < 16):
        raise ValueError(
            f"tile coordinates must be 0..15, got x={tile_x}, y={tile_y}"
        )

    tile_coordinates = ((tile_y & 0xFF) << 8) | (tile_x & 0xFF)
    sequence = time.time_ns() & 0xFFFFFFFF
    frame = REQUEST.pack(
        REQUEST_MAGIC,
        VERSION,
        command,
        tile_coordinates,
        sequence,
        len(payload),
        crc32(payload) if payload else 0,
    ) + payload

    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            port.write_all(frame, timeout)
            status, response, cycles, npu_status = receive_response(
                port, sequence, command, timeout
            )
            if status != 0:
                name = STATUS_NAMES.get(status, f"UNKNOWN_{status}")
                raise ProtocolError(
                    f"board status={name}, npu_status=0x{npu_status:08X}"
                )
            return response, cycles, npu_status
        except (TimeoutError, ProtocolError) as error:
            last_error = error
            print(f"attempt {attempt}/{retries} failed: {error}", file=sys.stderr)
    raise RuntimeError(f"UART transaction failed after {retries} attempts: {last_error}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default=DEFAULT_PORT)
    parser.add_argument("--baud", type=int, choices=(115200, 9600), default=115200)
    parser.add_argument("--timeout", type=float, default=None)
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--ping", action="store_true")
    parser.add_argument("--tile-x", type=int, choices=range(16), default=0)
    parser.add_argument("--tile-y", type=int, choices=range(16), default=0)
    parser.add_argument("--input", type=Path, help="32x32 INT16 .bin or .hex tile")
    parser.add_argument("--output", type=Path, help="16x16 INT16 little-endian .bin")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    timeout = args.timeout if args.timeout is not None else (5.0 if args.baud == 115200 else 15.0)
    if not args.ping and (args.input is None or args.output is None):
        print("ERROR: tile mode requires --input and --output", file=sys.stderr)
        return 2

    port = SerialPort(args.port, args.baud)
    try:
        if args.ping:
            payload, _, npu_status = transact(
                port, CMD_PING, b"", timeout, args.retries
            )
            if len(payload) != 4:
                raise ProtocolError(f"PING payload length is {len(payload)}, expected 4")
            version = struct.unpack("<I", payload)[0]
            print(f"PING PASS: NPU_VERSION=0x{version:08X} STATUS=0x{npu_status:08X}")
            return 0

        tile = load_tile(args.input)
        output, cycles, npu_status = transact(
            port,
            CMD_PROCESS_TILE,
            tile,
            timeout,
            args.retries,
            tile_x=args.tile_x,
            tile_y=args.tile_y,
        )
        if len(output) != OUTPUT_BYTES:
            raise ProtocolError(
                f"output length is {len(output)}, expected {OUTPUT_BYTES}"
            )
        args.output.write_bytes(output)
        print(
            f"TILE PASS: tile=({args.tile_x},{args.tile_y}) "
            f"output={args.output} bytes={len(output)} "
            f"pl_cycles={cycles} npu_status=0x{npu_status:08X}"
        )
        return 0
    finally:
        port.close()


if __name__ == "__main__":
    sys.exit(main())
