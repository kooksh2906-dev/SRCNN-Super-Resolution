# pyright: reportMissingImports=false
"""Create and build the final SRCNN UART firmware application."""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

import vitis


def env_path(name: str, default: Path) -> Path:
    return Path(os.environ.get(name, str(default))).expanduser().resolve()


REPO_ROOT = env_path(
    "SRCNN_REPO",
    Path(__file__).resolve().parents[2],
)
VITIS_ROOT = env_path(
    "SRCNN_VITIS_ROOT",
    REPO_ROOT / "vitis",
)
WORKSPACE = env_path(
    "SRCNN_VITIS_WS",
    REPO_ROOT / "build" / "vitis_workspace",
)
PLATFORM_NAME = "srcnn_team_a_platform"
DOMAIN_NAME = "standalone_ps7_cortexa9_0"
APP_NAME = "srcnn_team_a_final"
SOURCE_DIR = VITIS_ROOT / "firmware" / "src"
SOURCE_FILES = [
    "main.c",
    "srcnn_crc32.c",
    "srcnn_crc32.h",
    "srcnn_hw.c",
    "srcnn_hw.h",
    "srcnn_time.c",
    "srcnn_time.h",
    "srcnn_uart.c",
    "srcnn_uart.h",
]
IMPORT_FILES = [name for name in SOURCE_FILES if name != "main.c"]
XPFM = WORKSPACE / PLATFORM_NAME / "export" / PLATFORM_NAME / f"{PLATFORM_NAME}.xpfm"


def main() -> int:
    print("=== SRCNN Final Firmware Build ===")
    print(f"Workspace : {WORKSPACE}")
    print(f"Platform  : {XPFM}")
    print(f"Sources   : {SOURCE_DIR}")
    print(f"App       : {APP_NAME}")

    if not XPFM.is_file():
        print(f"ERROR: platform XPFM not found: {XPFM}")
        return 2
    missing_sources = [name for name in SOURCE_FILES if not (SOURCE_DIR / name).is_file()]
    if missing_sources:
        print(f"ERROR: missing firmware sources: {', '.join(missing_sources)}")
        return 2

    client = None
    app_dir = WORKSPACE / APP_NAME
    try:
        client = vitis.create_client()
        client.set_workspace(path=str(WORKSPACE))
        if (app_dir / "vitis-comp.json").is_file():
            print("Opening existing final firmware component...")
            app = client.get_component(name=APP_NAME)
        else:
            print("Creating application component from Hello World template...")
            app = client.create_app_component(
                name=APP_NAME,
                platform=str(XPFM),
                domain=DOMAIN_NAME,
                template="hello_world",
            )

        print("Replacing the template entry point with final firmware main.c...")
        template_main = app_dir / "src" / "helloworld.c"
        shutil.copy2(SOURCE_DIR / "main.c", template_main)
        stale_main = app_dir / "src" / "main.c"
        if stale_main.is_file():
            stale_main.unlink()

        print("Importing current repository support sources...")
        app.import_files(
            from_loc=str(SOURCE_DIR),
            files=IMPORT_FILES,
            dest_dir_in_cmp="src",
        )
        print("Building final firmware...")
        result = app.build()
        print(f"Build API result: {result}")
    except Exception as error:
        print("ERROR: final firmware creation/build failed")
        print(f"{type(error).__name__}: {error}")
        return 3
    finally:
        if client is not None:
            print("Vitis batch exit will close its server automatically.")

    elf = app_dir / "build" / f"{APP_NAME}.elf"
    if not elf.is_file():
        print(f"[FAIL] final ELF missing: {elf}")
        return 4
    print(f"[PASS] final ELF: {elf}")
    print("=== FINAL FIRMWARE BUILD SUCCESS ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
