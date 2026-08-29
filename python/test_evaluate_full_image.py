import math
import unittest

import numpy as np

from evaluate_full_image import calculate_lsb_metrics, calculate_metrics, crop_border


class EvaluateFullImageTest(unittest.TestCase):
    def test_identical_arrays_have_infinite_psnr(self):
        image = np.ones((4, 4), dtype=np.float32) * 0.5
        metrics = calculate_metrics(image, image)

        self.assertEqual(metrics['maximum_absolute_error'], 0.0)
        self.assertEqual(metrics['rmse'], 0.0)
        self.assertTrue(math.isinf(metrics['psnr_db']))

    def test_known_error_metrics(self):
        reference = np.zeros((2, 2), dtype=np.float32)
        actual = np.ones((2, 2), dtype=np.float32) * 0.5
        metrics = calculate_metrics(reference, actual)

        self.assertEqual(metrics['maximum_absolute_error'], 0.5)
        self.assertEqual(metrics['mean_absolute_error'], 0.5)
        self.assertEqual(metrics['mse'], 0.25)
        self.assertEqual(metrics['rmse'], 0.5)
        self.assertAlmostEqual(metrics['psnr_db'], 6.020599913, places=8)

    def test_crop_border(self):
        image = np.arange(36).reshape(6, 6)
        np.testing.assert_array_equal(crop_border(image, 2), image[2:-2, 2:-2])

    def test_lsb_metrics(self):
        fp32 = np.array([[0.0, 0.5], [0.25, 1.0]], dtype=np.float64)
        int16_output = np.array([[0, 16385], [8192, 32767]], dtype=np.int16)
        metrics = calculate_lsb_metrics(fp32, int16_output)

        self.assertEqual(metrics['maximum_error_lsb'], 1)
        self.assertEqual(metrics['mean_error_lsb'], 0.25)
        self.assertEqual(metrics['exact_percent'], 75.0)


if __name__ == '__main__':
    unittest.main()
