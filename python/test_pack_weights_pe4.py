import unittest
from pathlib import Path

import numpy as np

from pack_weights_pe4 import (
    pack_weights_pe4,
    read_uint64_hex,
    unpack_weights_pe4,
    verify_unused_lanes_are_zero,
    write_uint64_hex,
)


class PackWeightsPe4Test(unittest.TestCase):
    def test_lane_bit_order(self):
        weight = np.array([-32768, -1, 0, 32767], dtype=np.int16).reshape(4, 1, 1, 1)
        packed = pack_weights_pe4(weight)

        self.assertEqual(packed.shape, (1,))
        self.assertEqual(int(packed[0]), 0x7FFF0000FFFF8000)

    def test_round_trip_with_incomplete_group(self):
        weight = np.arange(5 * 2 * 3 * 3, dtype=np.int16).reshape(5, 2, 3, 3) - 40
        packed = pack_weights_pe4(weight)
        restored = unpack_weights_pe4(packed, weight.shape)

        verify_unused_lanes_are_zero(packed, weight.shape)
        np.testing.assert_array_equal(restored, weight)

    def test_hex_round_trip(self):
        weight = np.arange(4 * 2 * 2 * 2, dtype=np.int16).reshape(4, 2, 2, 2) - 16
        packed = pack_weights_pe4(weight)
        path = Path('packed_weights_test.hex')
        try:
            write_uint64_hex(path, packed)
            restored_words = read_uint64_hex(path)
            np.testing.assert_array_equal(restored_words, packed)
        finally:
            path.unlink(missing_ok=True)


if __name__ == '__main__':
    unittest.main()
