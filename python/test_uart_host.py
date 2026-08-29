import unittest

import numpy as np

from uart_host import MockTransport, read_frame, run_session
from uart_mock import MockZybo
from uart_protocol import decode_packet, encode_tile_result


class ChunkedSerial:
    def __init__(self, data: bytes, chunk_size: int = 1):
        self.data = bytearray(data)
        self.chunk_size = chunk_size

    def read(self, size: int) -> bytes:
        if not self.data:
            return b''
        count = min(size, self.chunk_size, len(self.data))
        result = bytes(self.data[:count])
        del self.data[:count]
        return result


class UartHostTest(unittest.TestCase):
    def test_read_frame_handles_noise_and_partial_reads(self):
        pixels = np.arange(256, dtype=np.int16).reshape(1, 16, 16)
        expected = encode_tile_result(7, pixels, cycle_count=123456)
        serial = ChunkedSerial(b'noise-before-magic' + expected, chunk_size=3)

        actual = read_frame(serial)

        self.assertEqual(actual, expected)
        packet = decode_packet(actual)
        self.assertEqual(packet.tile_id, 7)
        self.assertEqual(packet.cycle_count, 123456)
        self.assertEqual(packet.npu_status, 0x00000002)

    def test_read_frame_timeout(self):
        with self.assertRaises(TimeoutError):
            read_frame(ChunkedSerial(b'SRS', chunk_size=1))

    def test_complete_mock_session_matches_golden(self):
        input_tiles = np.zeros((256, 1, 32, 32), dtype=np.int16)
        output_tiles = np.zeros((256, 1, 32, 32), dtype=np.int16)
        for tile_id in range(256):
            output_tiles[tile_id, :, 8:24, 8:24] = tile_id

        golden_valid = output_tiles[:, :, 8:24, 8:24]
        expected_merged = np.empty((1, 256, 256), dtype=np.int16)
        for tile_id in range(256):
            x0 = (tile_id % 16) * 16
            y0 = (tile_id // 16) * 16
            expected_merged[:, y0:y0 + 16, x0:x0 + 16] = tile_id

        transport = MockTransport(MockZybo(input_tiles, golden_valid, cycle_count=10))
        merged, summary, mismatch_log = run_session(
            transport,
            input_tiles,
            golden_output_tiles=output_tiles,
            merged_expected=expected_merged,
            retries=0,
            progress_interval=0,
        )

        np.testing.assert_array_equal(merged, expected_merged)
        self.assertEqual(summary['mismatched_tile_count'], 0)
        self.assertEqual(summary['merged_mismatch_count'], 0)
        self.assertEqual(summary['merged_max_error_lsb'], 0)
        self.assertEqual(summary['total_cycle_count'], 2560)
        self.assertEqual(summary['tx_bytes'], 2068 * 256)
        self.assertEqual(summary['rx_bytes'], 540 * 256)
        self.assertEqual(mismatch_log, [])


if __name__ == '__main__':
    unittest.main()
