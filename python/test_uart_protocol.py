import unittest
import zlib

import numpy as np
from uart_protocol import (
    REQUEST_HEADER,
    RESPONSE_HEADER,
    ProtocolError,
    Status,
    decode_run_tile,
    decode_tile_result,
    encode_run_tile,
    encode_tile_result,
)


class UartProtocolTest(unittest.TestCase):
    def test_run_tile_round_trip(self):
        pixels = np.arange(1024, dtype=np.int16).reshape(1, 32, 32) - 512
        encoded = encode_run_tile(17, pixels, last_tile=True)
        packet, decoded = decode_run_tile(encoded)
        fields = REQUEST_HEADER.unpack_from(encoded)

        self.assertEqual(fields[0], b"SRQ1")
        self.assertEqual(fields[1], 1)
        self.assertEqual(fields[2], 1)
        self.assertEqual(fields[3], 0x0101)
        self.assertEqual(fields[4], 17)
        self.assertEqual(fields[5], 2048)
        self.assertEqual(
            fields[6],
            zlib.crc32(encoded[REQUEST_HEADER.size:]) & 0xFFFFFFFF,
        )
        self.assertEqual((packet.tile_x, packet.tile_y), (1, 1))
        self.assertEqual(packet.flags, 0)
        self.assertEqual(len(encoded), 2068)
        self.assertEqual(encoded, encode_run_tile(17, pixels, last_tile=False))
        np.testing.assert_array_equal(decoded, pixels)

    def test_tile_result_round_trip(self):
        pixels = np.arange(256, dtype=np.int16).reshape(1, 16, 16) - 128
        encoded = encode_tile_result(
            255,
            pixels,
            cycle_count=30_839_827,
        )
        packet, decoded = decode_tile_result(encoded)
        fields = RESPONSE_HEADER.unpack_from(encoded)

        self.assertEqual(fields[0], b"SRS1")
        self.assertEqual(fields[1], 1)
        self.assertEqual(fields[2], 0)
        self.assertEqual(fields[3], 1)
        self.assertEqual(fields[4], 0)
        self.assertEqual(fields[5], 255)
        self.assertEqual(fields[6], 512)
        self.assertEqual(
            fields[7],
            zlib.crc32(encoded[RESPONSE_HEADER.size:]) & 0xFFFFFFFF,
        )
        self.assertEqual(fields[8], 30_839_827)
        self.assertEqual(fields[9], 0x00000002)
        self.assertEqual((packet.tile_x, packet.tile_y), (15, 15))
        self.assertEqual(packet.cycle_count, 30_839_827)
        self.assertEqual(packet.npu_status, 0x00000002)
        self.assertEqual(packet.status, Status.OK)
        self.assertEqual(len(encoded), 540)
        np.testing.assert_array_equal(decoded, pixels)

    def test_all_required_tile_coordinate_mappings(self):
        pixels = np.zeros((1, 32, 32), dtype=np.int16)
        cases = (
            (0, 0, 0, 0x0000),
            (1, 1, 0, 0x0001),
            (15, 15, 0, 0x000F),
            (16, 0, 1, 0x0100),
            (240, 0, 15, 0x0F00),
            (255, 15, 15, 0x0F0F),
        )

        for tile_id, tile_x, tile_y, packed_coordinates in cases:
            with self.subTest(tile_id=tile_id):
                encoded = encode_run_tile(tile_id, pixels)
                packet, decoded = decode_run_tile(encoded)
                fields = REQUEST_HEADER.unpack_from(encoded)

                self.assertEqual(fields[3], packed_coordinates)
                self.assertEqual(fields[4], tile_id)
                self.assertEqual((packet.tile_x, packet.tile_y), (tile_x, tile_y))
                np.testing.assert_array_equal(decoded, pixels)

    def test_crc_corruption_is_detected(self):
        pixels = np.zeros((1, 32, 32), dtype=np.int16)
        corrupted = bytearray(encode_run_tile(0, pixels))
        corrupted[100] ^= 0x01

        with self.assertRaisesRegex(ProtocolError, "CRC32 mismatch"):
            decode_run_tile(corrupted)

    def test_invalid_pixel_count_is_rejected(self):
        with self.assertRaisesRegex(ProtocolError, "expected 1024 pixels"):
            encode_run_tile(0, np.zeros(1023, dtype=np.int16))

    def test_error_response_has_no_pixel_payload(self):
        encoded = encode_tile_result(
            3,
            np.empty(0, dtype=np.int16),
            cycle_count=0,
            status=Status.NPU_TIMEOUT,
        )
        packet, decoded = decode_tile_result(encoded)

        self.assertEqual(len(encoded), RESPONSE_HEADER.size)
        self.assertEqual(packet.status, Status.NPU_TIMEOUT)
        self.assertEqual(packet.npu_status, 0)
        self.assertIsNone(decoded)


if __name__ == "__main__":
    unittest.main()
