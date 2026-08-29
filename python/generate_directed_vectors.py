"""MAC/INT48/Requant/ReLU/Clamp RTL용 Directed Golden Vector 생성기."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path


INT16_MIN = -(1 << 15)
INT16_MAX = (1 << 15) - 1
INT32_MIN = -(1 << 31)
INT32_MAX = (1 << 31) - 1
INT48_MIN = -(1 << 47)
INT48_MAX = (1 << 47) - 1

MODE_RELU = 1
MODE_CLAMP_0_32767 = 2


def round_shift_scalar(value: int, shift: int) -> int:
    """Round-to-nearest, ties-away-from-zero."""
    if shift <= 0:
        raise ValueError('shift must be positive')
    half = 1 << (shift - 1)
    if value >= 0:
        return (value + half) >> shift
    return -(((-value) + half) >> shift)


def build_mac_cases() -> list[dict]:
    definitions = [
        ('bias_zero_no_mac', 0, [], 'Bias load only, zero'),
        ('bias_negative_no_mac', -1, [], 'INT32 -1 sign extension to INT48'),
        ('bias_int32_min_no_mac', INT32_MIN, [], 'INT32 minimum sign extension'),
        ('bias_int32_max_no_mac', INT32_MAX, [], 'INT32 maximum sign extension'),
        ('positive_times_positive', 0, [(100, 200)], 'positive x positive'),
        ('positive_times_negative', 0, [(300, -50)], 'positive x negative'),
        ('negative_times_negative', 0, [(-300, -50)], 'negative x negative'),
        ('int16_max_times_max', 0, [(INT16_MAX, INT16_MAX)], 'INT16 maximum product'),
        ('int16_min_times_min', 0, [(INT16_MIN, INT16_MIN)], 'INT16 minimum squared'),
        ('int16_min_times_max', 0, [(INT16_MIN, INT16_MAX)], 'mixed INT16 boundaries'),
        (
            'mixed_sequence_with_negative_bias',
            -1000,
            [(100, 200), (-300, 50), (INT16_MAX, -2)],
            'Bias + three signed MAC operations',
        ),
        (
            'positive_acc_exceeds_int32',
            INT32_MAX,
            [(INT16_MAX, INT16_MAX)],
            'Result exceeds signed INT32 and must remain correct in INT48',
        ),
        (
            'cancellation_sequence',
            -123456,
            [(INT16_MAX, INT16_MAX), (INT16_MAX, -INT16_MAX), (-123, 456)],
            'Positive/negative accumulation and cancellation',
        ),
        (
            'conv1_worst_positive_81_terms',
            INT32_MAX,
            [(INT16_MAX, INT16_MAX)] * 81,
            '9x9 single-channel maximum positive stress',
        ),
        (
            'conv2_worst_positive_1600_terms',
            INT32_MAX,
            [(INT16_MAX, INT16_MAX)] * 1600,
            '64x5x5 maximum positive stress; verifies INT48 margin',
        ),
    ]

    cases = []
    term_offset = 0
    for case_id, (name, bias, terms, description) in enumerate(definitions):
        accumulator = int(bias)
        expected_steps = []
        for activation, weight in terms:
            if not INT16_MIN <= activation <= INT16_MAX:
                raise ValueError(f'{name}: activation out of INT16 range')
            if not INT16_MIN <= weight <= INT16_MAX:
                raise ValueError(f'{name}: weight out of INT16 range')
            accumulator += int(activation) * int(weight)
            if not INT48_MIN <= accumulator <= INT48_MAX:
                raise OverflowError(f'{name}: accumulator exceeds INT48')
            expected_steps.append(accumulator)

        cases.append({
            'case_id': case_id,
            'name': name,
            'description': description,
            'bias_int32': bias,
            'term_offset': term_offset,
            'term_count': len(terms),
            'activations_int16': [a for a, _ in terms],
            'weights_int16': [w for _, w in terms],
            'expected_acc_after_each_mac_int48': expected_steps,
            'expected_final_acc_int48': accumulator,
        })
        term_offset += len(terms)
    return cases


def build_requant_cases() -> list[dict]:
    layers = [
        ('conv1', 1, 14, MODE_RELU),
        ('conv2', 2, 16, MODE_RELU),
        ('conv3', 3, 14, MODE_CLAMP_0_32767),
    ]
    cases = []

    for layer_name, layer_code, shift, mode in layers:
        half = 1 << (shift - 1)
        one = 1 << shift
        values = [
            ('zero', 0),
            ('positive_below_half_lsb', half - 1),
            ('positive_exact_half_lsb', half),
            ('positive_above_half_lsb', half + 1),
            ('positive_one_below_half', one + half - 1),
            ('positive_one_exact_half', one + half),
            ('negative_below_half_lsb', -(half - 1)),
            ('negative_exact_half_lsb', -half),
            ('negative_above_half_lsb', -(half + 1)),
            ('negative_one_exact_half', -(one + half)),
            ('int16_max_exact', INT16_MAX << shift),
            ('int16_max_plus_half_saturate', (INT16_MAX << shift) + half),
            ('positive_int16_overflow', (INT16_MAX + 1) << shift),
            ('int48_maximum', INT48_MAX),
            ('int48_minimum', INT48_MIN),
        ]

        for local_id, (name, accumulator) in enumerate(values):
            rounded_raw = round_shift_scalar(accumulator, shift)

            if mode == MODE_RELU:
                activated_accumulator = max(accumulator, 0)
                rounded_for_output = round_shift_scalar(activated_accumulator, shift)
                output = min(max(rounded_for_output, INT16_MIN), INT16_MAX)
            elif mode == MODE_CLAMP_0_32767:
                rounded_for_output = rounded_raw
                output = min(max(rounded_for_output, 0), INT16_MAX)
            else:
                raise ValueError(f'unknown mode: {mode}')

            cases.append({
                'case_id': len(cases),
                'layer': layer_name,
                'layer_code': layer_code,
                'local_id': local_id,
                'name': name,
                'accumulator_int48': accumulator,
                'shift': shift,
                'mode': mode,
                'mode_name': 'relu' if mode == MODE_RELU else 'clamp_0_32767',
                'rounder_expected_before_activation': rounded_raw,
                'expected_output_int16': output,
            })
    return cases


def _encode(value: int, bits: int) -> int:
    return int(value) & ((1 << bits) - 1)


def _decode(value: int, bits: int, signed: bool) -> int:
    if signed and value & (1 << (bits - 1)):
        return value - (1 << bits)
    return value


def write_hex(
    path: Path,
    values: list[int],
    bits: int,
    *,
    signed: bool,
    role: str,
) -> dict:
    minimum = -(1 << (bits - 1)) if signed else 0
    maximum = (1 << (bits - 1)) - 1 if signed else (1 << bits) - 1
    for value in values:
        if not minimum <= int(value) <= maximum:
            raise ValueError(f'{path.name}: {value} exceeds {bits}-bit range')

    digits = (bits + 3) // 4
    with path.open('w', encoding='ascii', newline='\n') as file:
        for value in values:
            file.write(f'{_encode(value, bits):0{digits}X}\n')

    decoded = [
        _decode(int(line, 16), bits, signed)
        for line in path.read_text(encoding='ascii').splitlines()
        if line
    ]
    if decoded != [int(value) for value in values]:
        raise RuntimeError(f'{path.name}: HEX round-trip verification failed')

    return {
        'file': path.name,
        'role': role,
        'bits': bits,
        'signed': signed,
        'hex_digits': digits,
        'count': len(values),
        'minimum': min(values) if values else None,
        'maximum': max(values) if values else None,
        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'round_trip_verified': True,
    }


def export_mac_vectors(output_dir: Path, cases: list[dict]) -> list[dict]:
    biases = [case['bias_int32'] for case in cases]
    offsets = [case['term_offset'] for case in cases]
    counts = [case['term_count'] for case in cases]
    activations = [value for case in cases for value in case['activations_int16']]
    weights = [value for case in cases for value in case['weights_int16']]
    step_expected = [
        value
        for case in cases
        for value in case['expected_acc_after_each_mac_int48']
    ]
    final_expected = [case['expected_final_acc_int48'] for case in cases]

    files = [
        ('mac_bias.hex', biases, 32, True, 'One signed INT32 bias per MAC case'),
        ('mac_term_offset.hex', offsets, 32, False, 'First term address per MAC case'),
        ('mac_term_count.hex', counts, 16, False, 'MAC term count per case'),
        ('mac_activation.hex', activations, 16, True, 'Concatenated signed INT16 activations'),
        ('mac_weight.hex', weights, 16, True, 'Concatenated signed INT16 weights'),
        ('mac_step_expected.hex', step_expected, 48, True, 'INT48 accumulator after each MAC'),
        ('mac_final_expected.hex', final_expected, 48, True, 'Final INT48 accumulator per case'),
    ]
    manifest = [
        write_hex(output_dir / name, values, bits, signed=signed, role=role)
        for name, values, bits, signed, role in files
    ]

    with (output_dir / 'mac_cases.json').open('w', encoding='utf-8') as file:
        json.dump(cases, file, ensure_ascii=False, indent=2)
        file.write('\n')
    with (output_dir / 'mac_cases.csv').open('w', encoding='utf-8-sig', newline='') as file:
        writer = csv.DictWriter(
            file,
            fieldnames=(
                'case_id', 'name', 'bias_int32', 'term_offset', 'term_count',
                'expected_final_acc_int48', 'description',
            ),
        )
        writer.writeheader()
        for case in cases:
            writer.writerow({key: case[key] for key in writer.fieldnames})
    return manifest


def export_requant_vectors(output_dir: Path, cases: list[dict]) -> list[dict]:
    files = [
        (
            'requant_accumulator.hex',
            [case['accumulator_int48'] for case in cases],
            48, True, 'Signed INT48 requantizer input',
        ),
        (
            'requant_shift.hex',
            [case['shift'] for case in cases],
            8, False, 'Arithmetic right shift amount',
        ),
        (
            'requant_mode.hex',
            [case['mode'] for case in cases],
            8, False, '1=ReLU, 2=Clamp 0..32767',
        ),
        (
            'requant_round_expected.hex',
            [case['rounder_expected_before_activation'] for case in cases],
            48, True, 'Raw ties-away rounded result before activation/clamp',
        ),
        (
            'requant_output_expected.hex',
            [case['expected_output_int16'] for case in cases],
            16, True, 'Final INT16 output after activation and saturation',
        ),
    ]
    manifest = [
        write_hex(output_dir / name, values, bits, signed=signed, role=role)
        for name, values, bits, signed, role in files
    ]

    with (output_dir / 'requant_cases.json').open('w', encoding='utf-8') as file:
        json.dump(cases, file, ensure_ascii=False, indent=2)
        file.write('\n')
    with (output_dir / 'requant_cases.csv').open('w', encoding='utf-8-sig', newline='') as file:
        fieldnames = (
            'case_id', 'layer', 'name', 'accumulator_int48', 'shift', 'mode_name',
            'rounder_expected_before_activation', 'expected_output_int16',
        )
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        writer.writeheader()
        for case in cases:
            writer.writerow({key: case[key] for key in fieldnames})
    return manifest


def main() -> None:
    output_dir = Path('directed_vectors')
    output_dir.mkdir(parents=True, exist_ok=True)

    mac_cases = build_mac_cases()
    requant_cases = build_requant_cases()
    manifest = {
        'version': '1.0',
        'numeric_contract': {
            'activation': 'signed INT16',
            'weight': 'signed INT16',
            'bias': 'signed INT32, sign-extended to INT48',
            'product': 'signed INT32',
            'accumulator': 'signed INT48',
            'rounding': 'round-to-nearest, ties-away-from-zero',
            'mode_1': 'ReLU then signed INT16 saturation',
            'mode_2': 'Clamp 0..32767',
        },
        'mac_case_count': len(mac_cases),
        'mac_term_count': sum(case['term_count'] for case in mac_cases),
        'requant_case_count': len(requant_cases),
        'files': export_mac_vectors(output_dir, mac_cases)
        + export_requant_vectors(output_dir, requant_cases),
    }

    with (output_dir / 'manifest.json').open('w', encoding='utf-8') as file:
        json.dump(manifest, file, ensure_ascii=False, indent=2)
        file.write('\n')

    print('MAC cases      :', manifest['mac_case_count'])
    print('MAC terms      :', manifest['mac_term_count'])
    print('Requant cases  :', manifest['requant_case_count'])
    print('All HEX vectors round-trip verified.')
    print('Output         :', output_dir.resolve())


if __name__ == '__main__':
    main()
