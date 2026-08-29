# pyright: reportMissingImports=false
"""Create and build the final Cortex-A9 Standalone Vitis platform."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import vitis


def env_path(name: str, default: Path) -> Path:
    return Path(os.environ.get(name, str(default))).expanduser().resolve()


REPO_ROOT = env_path(
    "SRCNN_REPO",
    Path(__file__).resolve().parents[2],
)
XSA = env_path(
    "SRCNN_XSA",
    REPO_ROOT / "vivado" / "output" / "SRCNN_NPU_wrapper.xsa",
)
WORKSPACE = env_path(
    "SRCNN_VITIS_WS",
    REPO_ROOT / "build" / "vitis_workspace",
)
PLATFORM_NAME = "srcnn_team_a_platform"
DOMAIN_NAME = "standalone_ps7_cortexa9_0"
CPU_NAME = "ps7_cortexa9_0"


def main() -> int:
    print("=== Team A Cortex-A9 Standalone Platform ===")
    print(f"XSA       : {XSA}")
    print(f"Workspace : {WORKSPACE}")
    print(f"Platform  : {PLATFORM_NAME}")
    print(f"Domain    : {DOMAIN_NAME}")

    if not XSA.is_file():
        print(f"ERROR: final XSA not found: {XSA}")
        return 2

    WORKSPACE.mkdir(parents=True, exist_ok=True)
    component_dir = WORKSPACE / PLATFORM_NAME
    client = None

    try:
        print("[1/4] Starting Vitis client...")
        client = vitis.create_client()
        print("[2/4] Setting workspace...")
        client.set_workspace(path=str(WORKSPACE))

        if (component_dir / "vitis-comp.json").is_file():
            print("[3/4] Opening existing platform component...")
            platform = client.get_component(name=PLATFORM_NAME)
        else:
            print("[3/4] Creating platform component...")
            client.create_platform_component(
                name=PLATFORM_NAME,
                hw_design=str(XSA),
                domain_name=DOMAIN_NAME,
                cpu=CPU_NAME,
                os="standalone",
            )
            platform = client.get_component(name=PLATFORM_NAME)

        print("[4/4] Full platform/BSP/FSBL build...")
        result = platform.build()
        print(f"Build API result: {result}")
    except Exception as error:
        print("ERROR: Team A platform creation/build failed")
        print(f"{type(error).__name__}: {error}")
        return 3
    finally:
        if client is not None:
            print("Vitis batch exit will close its server automatically.")

    xpfm = component_dir / "export" / PLATFORM_NAME / f"{PLATFORM_NAME}.xpfm"
    fsbl = component_dir / "export" / PLATFORM_NAME / "sw" / "boot" / "fsbl.elf"
    bitstreams = sorted(
        (component_dir / "export" / PLATFORM_NAME / "hw").glob("**/*.bit")
    )
    generated_bit = (
        bitstreams[0]
        if bitstreams
        else component_dir / "export" / PLATFORM_NAME / "hw"
    )
    outputs = (
        ("XPFM", xpfm),
        ("FSBL", fsbl),
        ("BIT", generated_bit),
    )
    missing = False
    for label, path in outputs:
        passed = path.is_file()
        print(f"[{'PASS' if passed else 'FAIL'}] {label}: {path}")
        missing = missing or not passed
    if missing:
        return 4

    print("=== TEAM A PLATFORM BUILD SUCCESS ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
