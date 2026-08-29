import unittest

from generate_directed_vectors import (
    INT16_MAX,
    INT48_MAX,
    INT48_MIN,
    MODE_CLAMP_0_32767,
    MODE_RELU,
    build_mac_cases,
    build_requant_cases,
    round_shift_scalar,
)


class DirectedVectorTest(unittest.TestCase):
    def test_round_shift_ties_away_from_zero(self):
        self.assertEqual(round_shift_scalar(8, 4), 1)
        self.assertEqual(round_shift_scalar(7, 4), 0)
        self.assertEqual(round_shift_scalar(24, 4), 2)
        self.assertEqual(round_shift_scalar(-8, 4), -1)
        self.assertEqual(round_shift_scalar(-7, 4), 0)
        self.assertEqual(round_shift_scalar(-24, 4), -2)

    def test_known_mixed_mac_case(self):
        cases = {case['name']: case for case in build_mac_cases()}
        case = cases['mixed_sequence_with_negative_bias']

        self.assertEqual(case['expected_final_acc_int48'], -61534)
        self.assertEqual(case['expected_acc_after_each_mac_int48'], [19000, 4000, -61534])

    def test_mac_cases_fit_int48(self):
        for case in build_mac_cases():
            self.assertGreaterEqual(case['expected_final_acc_int48'], INT48_MIN)
            self.assertLessEqual(case['expected_final_acc_int48'], INT48_MAX)
            for value in case['expected_acc_after_each_mac_int48']:
                self.assertGreaterEqual(value, INT48_MIN)
                self.assertLessEqual(value, INT48_MAX)

    def test_requant_half_lsb_and_saturation(self):
        cases = build_requant_cases()
        by_key = {(case['layer'], case['name']): case for case in cases}

        for layer in ('conv1', 'conv2', 'conv3'):
            positive = by_key[(layer, 'positive_exact_half_lsb')]
            negative = by_key[(layer, 'negative_exact_half_lsb')]
            overflow = by_key[(layer, 'positive_int16_overflow')]

            self.assertEqual(positive['rounder_expected_before_activation'], 1)
            self.assertEqual(positive['expected_output_int16'], 1)
            self.assertEqual(negative['rounder_expected_before_activation'], -1)
            self.assertEqual(negative['expected_output_int16'], 0)
            self.assertEqual(overflow['expected_output_int16'], INT16_MAX)

    def test_layer_modes(self):
        cases = build_requant_cases()
        modes = {case['layer']: case['mode'] for case in cases}
        self.assertEqual(modes['conv1'], MODE_RELU)
        self.assertEqual(modes['conv2'], MODE_RELU)
        self.assertEqual(modes['conv3'], MODE_CLAMP_0_32767)


if __name__ == '__main__':
    unittest.main()
