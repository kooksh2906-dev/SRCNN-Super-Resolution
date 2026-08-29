import unittest

import numpy as np
from PIL import Image

from srcnn_demo_image import calculate_y_psnr, prepare_demo_image, reconstruct_sr_rgb


class SrcnnDemoImageTest(unittest.TestCase):
    def test_lr_input_prepares_expected_tiles(self):
        source = Image.new('RGB', (128, 128), (80, 120, 160))
        demo = prepare_demo_image(source)
        self.assertEqual(demo.source_mode, 'LR 128×128')
        self.assertIsNone(demo.reference_hr_rgb)
        self.assertEqual(demo.bicubic_rgb.size, (256, 256))
        self.assertEqual(demo.input_tiles_int16.shape, (256, 1, 32, 32))
        self.assertEqual(demo.input_tiles_int16.dtype, np.int16)

    def test_hr_input_keeps_reference_and_creates_lr(self):
        source = Image.new('RGB', (256, 256), (30, 60, 90))
        demo = prepare_demo_image(source)
        self.assertEqual(demo.source_mode, 'HR 256×256 (평가용)')
        self.assertIsNotNone(demo.reference_hr_rgb)
        self.assertEqual(demo.lr_rgb.size, (128, 128))

    def test_invalid_size_is_rejected(self):
        with self.assertRaises(ValueError):
            prepare_demo_image(Image.new('RGB', (200, 100)))

    def test_reconstruct_output(self):
        demo = prepare_demo_image(Image.new('RGB', (128, 128), (90, 100, 110)))
        output = np.full((1, 256, 256), 16384, dtype=np.int16)
        result = reconstruct_sr_rgb(demo, output)
        self.assertEqual(result.size, (256, 256))
        self.assertEqual(result.mode, 'RGB')

    def test_identical_images_have_infinite_psnr(self):
        image = Image.new('RGB', (256, 256), (10, 20, 30))
        self.assertEqual(calculate_y_psnr(image, image), float('inf'))


if __name__ == '__main__':
    unittest.main()
