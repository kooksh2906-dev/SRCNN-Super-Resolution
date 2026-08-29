import unittest

import numpy as np

from tile_halo import (
    create_tile_valid_masks,
    merge_valid_regions,
    split_halo_tiles,
    tile_xy,
)


class TileHaloTest(unittest.TestCase):
    def setUp(self):
        self.image = np.arange(256 * 256, dtype=np.int32).reshape(256, 256)
        self.tiles = split_halo_tiles(self.image)

    def test_tile_count_and_shape(self):
        self.assertEqual(self.tiles.shape, (256, 32, 32))

    def test_first_tile_has_zero_padding_and_correct_center(self):
        first = self.tiles[0]

        np.testing.assert_array_equal(first[:8, :], 0)
        np.testing.assert_array_equal(first[:, :8], 0)
        np.testing.assert_array_equal(first[8:24, 8:24], self.image[:16, :16])

    def test_internal_tile_uses_real_neighbor_pixels(self):
        tile_id = 1 * 16 + 1
        internal = self.tiles[tile_id]

        np.testing.assert_array_equal(internal, self.image[8:40, 8:40])
        np.testing.assert_array_equal(
            internal[8:24, 8:24],
            self.image[16:32, 16:32],
        )

    def test_last_tile_has_zero_padding_and_correct_center(self):
        last = self.tiles[-1]

        np.testing.assert_array_equal(last[-8:, :], 0)
        np.testing.assert_array_equal(last[:, -8:], 0)
        np.testing.assert_array_equal(last[8:24, 8:24], self.image[240:256, 240:256])

    def test_identity_output_merges_exactly(self):
        merged = merge_valid_regions(self.tiles, self.image.shape)

        np.testing.assert_array_equal(merged, self.image)

    def test_chw_image_round_trip(self):
        chw = np.stack((self.image, self.image + 1), axis=0)
        tiles = split_halo_tiles(chw)
        merged = merge_valid_regions(tiles, self.image.shape)

        self.assertEqual(tiles.shape, (256, 2, 32, 32))
        np.testing.assert_array_equal(merged, chw)

    def test_tile_id_mapping(self):
        self.assertEqual(tile_xy(0, self.image.shape), (0, 0))
        self.assertEqual(tile_xy(17, self.image.shape), (1, 1))
        self.assertEqual(tile_xy(255, self.image.shape), (15, 15))

    def test_global_boundary_masks(self):
        masks = create_tile_valid_masks(self.image.shape)

        self.assertEqual(masks.shape, (256, 1, 32, 32))
        np.testing.assert_array_equal(masks[0, 0, :8, :], 0)
        np.testing.assert_array_equal(masks[0, 0, :, :8], 0)
        np.testing.assert_array_equal(masks[0, 0, 8:, 8:], 1)
        np.testing.assert_array_equal(masks[17], 1)
        np.testing.assert_array_equal(masks[-1, 0, -8:, :], 0)
        np.testing.assert_array_equal(masks[-1, 0, :, -8:], 0)

    def test_invalid_size_is_rejected(self):
        with self.assertRaises(ValueError):
            split_halo_tiles(np.zeros((255, 256), dtype=np.int16))


if __name__ == '__main__':
    unittest.main()
