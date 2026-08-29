#!/usr/bin/env python3
"""Verify the final SRCNN hardware, firmware and release artifacts."""

from __future__ import annotations

import hashlib
import os
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree


def env_path(name: str, default: Path) -> Path:
    return Path(os.environ.get(name, str(default))).expanduser().resolve()


REPO_ROOT = env_path(
    "SRCNN_REPO",
    Path(__file__).resolve().parents[2],
)
VIVADO_ROOT = env_path(
    "SRCNN_VIVADO_ROOT",
    REPO_ROOT / "vivado",
)
VITIS_ROOT = env_path(
    "SRCNN_VITIS_ROOT",
    REPO_ROOT / "vitis",
)

XSA = VIVADO_ROOT / "output" / "SRCNN_NPU_wrapper.xsa"
BIT = VIVADO_ROOT / "output" / "SRCNN_NPU_wrapper.bit"
ELF = VITIS_ROOT / "output" / "srcnn_team_a_final.elf"
FSBL = VITIS_ROOT / "output" / "fsbl.elf"
HW_HEADER = VITIS_ROOT / "firmware" / "src" / "srcnn_hw.h"
UART_CLIENT = VITIS_ROOT / "tools" / "srcnn_uart_client.py"

EXPECTED_XSA_SHA256 = "701064a853a2f3027ceb7d02df8f0dbdef6e732a0f29d3b0e109d11ed34eeb2f"
EXPECTED_BIT_SHA256 = "2b84f0a11c8292763724d8222ff261bd059acc14b567ad9009ad7063791adc38"
EXPECTED_ELF_SHA256 = "bcd84c278759cb78de60d26663995bd35570e7fbd26e8aa1a4944bb23becdaee"
EXPECTED_FSBL_SHA256 = "235717926f324ab7c2cd6e13a7afdac17dd45a747f93da6f8bd5d6a5e41b142c"

EXPECTED_NPU_BASE = "0x43C00000"
EXPECTED_BRAM_BASE = "0x40000000"
EXPECTED_UART_BASE = "0xE0001000"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parameter_values(root: ElementTree.Element, name: str) -> set[str]:
    return {
        element.attrib.get("VALUE", "")
        for element in root.iter("PARAMETER")
        if element.attrib.get("NAME") == name
    }


def memory_range_base_values(
    root: ElementTree.Element,
    instance: str,
) -> set[str]:
    return {
        element.attrib.get("BASEVALUE", "")
        for element in root.iter()
        if element.tag.upper().endswith("MEMRANGE")
        and element.attrib.get("INSTANCE") == instance
    }


def fail(message: str) -> None:
    print(f"[FAIL] {message}")


def main() -> int:
    print("=== SRCNN Final Release Verification ===")
    print(f"XSA: {XSA}")
    print(f"BIT: {BIT}")

    required_files = (
        XSA,
        BIT,
        ELF,
        FSBL,
        HW_HEADER,
        UART_CLIENT,
    )
    missing = [str(path) for path in required_files if not path.is_file()]
    if missing:
        for path in missing:
            fail(f"missing file: {path}")
        return 2

    artifact_checks = (
        ("XSA", XSA, EXPECTED_XSA_SHA256),
        ("BIT", BIT, EXPECTED_BIT_SHA256),
        ("Application ELF", ELF, EXPECTED_ELF_SHA256),
        ("FSBL", FSBL, EXPECTED_FSBL_SHA256),
    )

    for label, artifact, expected_hash in artifact_checks:
        actual_hash = sha256_file(artifact)
        print(f"{label} SHA-256: {actual_hash}")
        if actual_hash != expected_hash:
            fail(f"{label} hash differs from the final release")
            return 3

    bit_hash = sha256_file(BIT)

    with zipfile.ZipFile(XSA) as archive:
        names = set(archive.namelist())
        bit_members = sorted(
            name for name in names if name.endswith(".bit")
        )

        if "SRCNN_NPU.hwh" not in names:
            fail("XSA lacks SRCNN_NPU.hwh")
            return 4
        if len(bit_members) != 1:
            fail(
                "XSA must contain exactly one bitstream; "
                f"found {len(bit_members)}"
            )
            return 4

        internal_bit = archive.read(bit_members[0])
        if hashlib.sha256(internal_bit).hexdigest() != bit_hash:
            fail(
                "external BIT is not identical to "
                "the bitstream embedded in the XSA"
            )
            return 5

        print(f"[PASS] XSA embedded BIT: {bit_members[0]}")
        hwh = archive.read("SRCNN_NPU.hwh").decode("utf-8-sig")

    root = ElementTree.fromstring(hwh)
    npu_bases = parameter_values(root, "C_S00_AXI_BASEADDR")
    bram_bases = parameter_values(root, "C_S_AXI_BASEADDR")
    uart_bases = parameter_values(root, "PCW_UART1_BASEADDR")
    uart_enabled = parameter_values(root, "PCW_EN_UART1")
    uart_baud = parameter_values(root, "PCW_UART1_BAUD_RATE")
    fabric_irq = parameter_values(root, "PCW_USE_FABRIC_INTERRUPT")

    checks = [
        (
            EXPECTED_NPU_BASE
            in memory_range_base_values(
                root,
                "AXI4_SRCNN_NPU_0",
            ),
            f"NPU base {EXPECTED_NPU_BASE}",
        ),
        (EXPECTED_BRAM_BASE in bram_bases, f"Input BRAM base {EXPECTED_BRAM_BASE}"),
        (EXPECTED_UART_BASE in uart_bases, f"UART1 base {EXPECTED_UART_BASE}"),
        ("1" in uart_enabled, "UART1 enabled"),
        ("115200" in uart_baud, "UART1 baud 115200"),
        ("0" in fabric_irq, "no PL fabric interrupt; polling required"),
    ]
    for passed, label in checks:
        print(f"[{'PASS' if passed else 'FAIL'}] {label}")
    if not all(passed for passed, _ in checks):
        return 6

    header_text = HW_HEADER.read_text(encoding="utf-8")
    uart_text = UART_CLIENT.read_text(encoding="utf-8")

    software_checks = [
        (
            "SRCNN_EXPECTED_VERSION   0x00010001U" in header_text,
            "NPU expected VERSION 0x00010001",
        ),
        (
            "SRCNN_REG_TILE_POS       0x20U" in header_text,
            "TILE_POS register offset 0x20",
        ),
        (
            'REQUEST_MAGIC = b"SRQ1"' in uart_text,
            "UART request magic SRQ1",
        ),
        (
            'RESPONSE_MAGIC = b"SRS1"' in uart_text,
            "UART response magic SRS1",
        ),
        (
            '"BAD_TILE_POSITION"' in uart_text,
            "UART BAD_TILE_POSITION status",
        ),
        (
            '"TILE_POS_IO"' in uart_text,
            "UART TILE_POS_IO status",
        ),
    ]

    for passed, label in software_checks:
        print(f"[{'PASS' if passed else 'FAIL'}] {label}")
    if not all(passed for passed, _ in software_checks):
        return 7

    print("[PASS] external BIT equals the XSA-embedded bitstream")
    print("=== FINAL RELEASE VERIFICATION SUCCESS ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
