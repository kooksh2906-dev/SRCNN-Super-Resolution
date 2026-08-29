import unittest
from pathlib import Path

import numpy as np

from srcnn_int16_core import load_parameters, round_shift, run_srcnn_int16
from tile_halo import create_tile_valid_masks, merge_valid_regions, split_halo_tiles


class SrcnnInt16CoreTest(unittest.TestCase):
    def test_round_shift_ties_away_from_zero(self):
        values = np.array([24, 23, 8, 7, -7, -8, -23, -24], dtype=np.int64)
        actual = round_shift(values, 4)
        expected = np.array([2, 1, 1, 0, 0, -1, -1, -2], dtype=np.int64)
        np.testing.assert_array_equal(actual, expected)

    def test_refactored_core_matches_existing_golden(self):
        data_dir = Path('dump_int16')
        golden_dir = Path('golden_int16')

        input_q = np.load(data_dir / 'input_y.npy')
        parameters = load_parameters(data_dir)
        actual = run_srcnn_int16(input_q, parameters, return_layers=True)

        for name in (
            'conv1_acc',
            'relu1_q',
            'conv2_acc',
            'relu2_q',
            'conv3_acc',
            'output_q',
        ):
            with self.subTest(name=name):
                expected = np.load(golden_dir / f'{name}.npy')
                np.testing.assert_array_equal(actual[name], expected)

    def test_boundary_masked_tiles_match_direct_32x32_inference(self):
        data_dir = Path('dump_int16')
        input_q = np.load(data_dir / 'input_y.npy')
        parameters = load_parameters(data_dir)

        direct = run_srcnn_int16(input_q, parameters)
        tiles = split_halo_tiles(input_q[0], valid_size=16, halo=8)
        masks = create_tile_valid_masks((32, 32), valid_size=16, halo=8)
        tile_outputs = run_srcnn_int16(tiles, parameters, valid_mask=masks)
        merged = merge_valid_regions(tile_outputs, (32, 32), valid_size=16, halo=8)

        np.testing.assert_array_equal(merged, direct[0])


if __name__ == '__main__':
    unittest.main()
