import unittest
from pathlib import Path

import numpy as np

from srcnn_backend import PythonInt16Backend, TileResult, ZyboUartBackend
from srcnn_pipeline import compare_int16, run_pipeline
from uart_host import MockTransport
from uart_mock import MockZybo


class ConstantBackend:
    name = 'constant-test'

    def run_tile(self, tile_id, input_tile):
        output = np.full((1, 16, 16), tile_id, dtype=np.int16)
        return TileResult(tile_id, output, 10, 0.0, self.name)

    def close(self):
        pass


class SrcnnBackendTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.input_tiles = np.load('full_image_data/input_tiles_int16.npy')
        cls.output_tiles = np.load('full_image_golden/output_tiles_int16.npy')
        cls.golden_valid = cls.output_tiles[:, :, 8:24, 8:24]

    def test_python_backend_matches_boundary_and_interior_tiles(self):
        backend = PythonInt16Backend()
        try:
            for tile_id in (0, 17, 255):
                result = backend.run_tile(tile_id, self.input_tiles[tile_id])
                self.assertEqual(result.tile_id, tile_id)
                self.assertEqual(result.output.shape, (1, 16, 16))
                self.assertEqual(result.output.dtype, np.int16)
                np.testing.assert_array_equal(
                    result.output,
                    self.golden_valid[tile_id],
                )
        finally:
            backend.close()

    def test_zybo_backend_contract_with_mock_transport(self):
        board = MockZybo(self.input_tiles, self.golden_valid)
        backend = ZyboUartBackend(transport=MockTransport(board))
        try:
            result = backend.run_tile(255, self.input_tiles[255])
            np.testing.assert_array_equal(result.output, self.golden_valid[255])
            self.assertGreater(result.cycle_count, 0)
            self.assertEqual(result.backend_name, 'zybo-uart')
        finally:
            backend.close()

    def test_common_pipeline_is_backend_independent(self):
        progress = []
        result = run_pipeline(
            ConstantBackend(),
            np.zeros((256, 1, 32, 32), dtype=np.int16),
            progress_callback=lambda done, total, tile: progress.append(
                (done, total, tile.tile_id)
            ),
        )

        self.assertEqual(result.backend_name, 'constant-test')
        self.assertEqual(result.total_cycle_count, 2560)
        self.assertEqual(result.merged_output.shape, (1, 256, 256))
        self.assertEqual(int(result.merged_output[0, 0, 0]), 0)
        self.assertEqual(int(result.merged_output[0, 255, 255]), 255)
        self.assertEqual(progress[0], (1, 256, 0))
        self.assertEqual(progress[-1], (256, 256, 255))

    def test_int16_comparison(self):
        expected = np.array([0, 10, -10], dtype=np.int16)
        actual = np.array([0, 12, -11], dtype=np.int16)
        result = compare_int16(actual, expected)
        self.assertEqual(result.mismatch_count, 2)
        self.assertEqual(result.max_error_lsb, 2)
        self.assertAlmostEqual(result.mean_error_lsb, 1.0)
        self.assertAlmostEqual(result.exact_percent, 100.0 / 3.0)

    def test_rejects_bad_input_shape_and_dtype(self):
        backend = PythonInt16Backend()
        try:
            with self.assertRaises(ValueError):
                backend.run_tile(0, np.zeros((32, 32), dtype=np.int16))
            with self.assertRaises(TypeError):
                backend.run_tile(0, np.zeros((1, 32, 32), dtype=np.float32))
        finally:
            backend.close()


if __name__ == '__main__':
    unittest.main()
