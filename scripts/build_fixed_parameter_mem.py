#!/usr/bin/env python3

"""Conv1/Conv2/Conv3 Weight와 Bias를 FPGA 초기화 파일로 병합한다."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


REPO_DIR = Path(__file__).resolve().parents[1]

OUTPUT_DIR = REPO_DIR / "rtl" / "mem_init"

WEIGHT_OUTPUT = OUTPUT_DIR / "srcnn_weights_all.hex"
BIAS_OUTPUT = OUTPUT_DIR / "srcnn_biases_all.hex"
MANIFEST_OUTPUT = OUTPUT_DIR / "manifest.json"


WEIGHT_SOURCES = [
    {
        "layer": "conv1",
        "path": REPO_DIR
        / "tb/data/pe4_weights/conv1_weight_pe4.hex",
        "count": 1296,
        "base_address": 0,
        "hex_digits": 16,
        "sha256":
            "98a07e78d2ffd2f354fd85b845c647787e601df649d0c9e18255d865aa403af2",
    },
    {
        "layer": "conv2",
        "path": REPO_DIR
        / "tb/data/pe4_weights/conv2_weight_pe4.hex",
        "count": 12800,
        "base_address": 1296,
        "hex_digits": 16,
        "sha256":
            "6628c54a34344bbc99f182083dd748cfae08bf19bd9b374c59b5a5c3ff316855",
    },
    {
        "layer": "conv3",
        "path": REPO_DIR
        / "tb/data/pe4_weights/conv3_weight_pe4.hex",
        "count": 800,
        "base_address": 14096,
        "hex_digits": 16,
        "sha256":
            "438b89adb94ebae643862e109532cc38d1c3037a99d46f5a7ebc43ae475df1d4",
    },
]


BIAS_SOURCES = [
    {
        "layer": "conv1",
        "path": REPO_DIR
        / "tb/data/single_tile/conv1_bias.hex",
        "count": 64,
        "base_address": 0,
        "hex_digits": 8,
        "sha256":
            "945da6a05a5da60d66c136343d7fbd96b8197e0fa2f81a6d62787190d9a971c4",
    },
    {
        "layer": "conv2",
        "path": REPO_DIR
        / "tb/data/single_tile/conv2_bias.hex",
        "count": 32,
        "base_address": 64,
        "hex_digits": 8,
        "sha256":
            "618e46bdcf32f3f3d5438c5e960b4c6a102c38334836a41924f10a716e22e5be",
    },
    {
        "layer": "conv3",
        "path": REPO_DIR
        / "tb/data/single_tile/conv3_bias.hex",
        "count": 1,
        "base_address": 96,
        "hex_digits": 8,
        "sha256":
            "dc2a567b49e123967bb4bb127e1a80b9e02abf7f7ceb3be705e049418ffd3d06",
    },
]


def calculate_sha256(path: Path) -> str:
    """파일의 SHA-256을 계산한다."""

    digest = hashlib.sha256()

    with path.open("rb") as file_object:
        while True:
            block = file_object.read(1024 * 1024)

            if not block:
                break

            digest.update(block)

    return digest.hexdigest()


def read_hex_values(
    path: Path,
    expected_count: int,
    hex_digits: int,
) -> list[str]:
    """HEX 파일을 읽고 개수와 비트폭을 검사한다."""

    if not path.is_file():
        raise FileNotFoundError(f"Input file not found: {path}")

    values: list[str] = []
    pattern = re.compile(rf"[0-9a-fA-F]{{{hex_digits}}}")

    with path.open("r", encoding="ascii") as file_object:
        for line_number, raw_line in enumerate(file_object, start=1):
            # 주석과 빈 줄을 제거한다.
            token = raw_line.split("//", maxsplit=1)[0]
            token = token.split("#", maxsplit=1)[0]
            token = token.strip().replace("_", "")

            if not token:
                continue

            if pattern.fullmatch(token) is None:
                raise ValueError(
                    f"{path}:{line_number}: "
                    f"expected exactly {hex_digits} hexadecimal digits, "
                    f"got '{token}'"
                )

            # 출력 파일의 형식을 대문자 고정 폭 HEX로 통일한다.
            value = int(token, 16)
            values.append(f"{value:0{hex_digits}X}")

    if len(values) != expected_count:
        raise ValueError(
            f"{path}: expected {expected_count} values, "
            f"got {len(values)}"
        )

    return values


def build_memory_image(
    sources: list[dict],
    output_path: Path,
) -> list[dict]:
    """Layer별 파일을 주소 순서대로 병합한다."""

    output_values: list[str] = []
    layer_manifest: list[dict] = []

    for source in sources:
        path = source["path"]
        actual_sha256 = calculate_sha256(path)

        if actual_sha256 != source["sha256"]:
            raise ValueError(
                f"{path}: SHA-256 mismatch\n"
                f"expected: {source['sha256']}\n"
                f"actual  : {actual_sha256}"
            )

        if len(output_values) != source["base_address"]:
            raise ValueError(
                f"{source['layer']}: base-address mismatch; "
                f"expected current address {source['base_address']}, "
                f"got {len(output_values)}"
            )

        values = read_hex_values(
            path=path,
            expected_count=source["count"],
            hex_digits=source["hex_digits"],
        )

        start_address = len(output_values)
        output_values.extend(values)
        end_address = len(output_values) - 1

        layer_manifest.append(
            {
                "layer": source["layer"],
                "source": str(path.relative_to(REPO_DIR)),
                "source_sha256": actual_sha256,
                "base_address": start_address,
                "end_address": end_address,
                "word_count": len(values),
                "word_bits": source["hex_digits"] * 4,
            }
        )

    output_path.write_text(
        "\n".join(output_values) + "\n",
        encoding="ascii",
    )

    return layer_manifest


def main() -> None:
    """Weight/Bias 병합 파일과 Manifest를 생성한다."""

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    weight_manifest = build_memory_image(
        sources=WEIGHT_SOURCES,
        output_path=WEIGHT_OUTPUT,
    )

    bias_manifest = build_memory_image(
        sources=BIAS_SOURCES,
        output_path=BIAS_OUTPUT,
    )

    manifest = {
        "format_version": 1,
        "description":
            "Fixed SRCNN Conv1/Conv2/Conv3 FPGA parameter memory image",
        "weight_memory": {
            "file": str(WEIGHT_OUTPUT.relative_to(REPO_DIR)),
            "word_bits": 64,
            "word_count": 14896,
            "sha256": calculate_sha256(WEIGHT_OUTPUT),
            "layers": weight_manifest,
        },
        "bias_memory": {
            "file": str(BIAS_OUTPUT.relative_to(REPO_DIR)),
            "word_bits": 32,
            "word_count": 97,
            "sha256": calculate_sha256(BIAS_OUTPUT),
            "layers": bias_manifest,
        },
    }

    MANIFEST_OUTPUT.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print("========================================")
    print("SRCNN Fixed Parameter Images Generated")
    print(f"Weight words : {manifest['weight_memory']['word_count']}")
    print(f"Bias words   : {manifest['bias_memory']['word_count']}")
    print(f"Weight file  : {WEIGHT_OUTPUT}")
    print(f"Bias file    : {BIAS_OUTPUT}")
    print(f"Manifest     : {MANIFEST_OUTPUT}")
    print("========================================")


if __name__ == "__main__":
    main()
