#!/usr/bin/env python3
"""Connect to hw_server and display the available Zybo JTAG targets."""

from __future__ import annotations

import os
import sys

import xsdb


HW_SERVER_URL = os.environ.get(
    "SRCNN_HW_SERVER",
    "TCP:127.0.0.1:3121",
)


def main() -> int:
    print("=== Zybo Z7-20 JTAG Target Probe ===")
    print(f"HW server: {HW_SERVER_URL}")

    try:
        session = xsdb.start_debug_session()

        print("\n[1/3] Connecting to hw_server...")
        channel = session.connect(url=HW_SERVER_URL)
        print(f"Connected: {channel}")

        print("\n[2/3] JTAG chain:")
        session.jtag_targets()

        print("\n[3/3] Debug targets:")
        session.targets()

    except Exception as error:
        print("\nERROR: JTAG target probe failed.")
        print(f"{type(error).__name__}: {error}")
        return 1

    print("\n=== JTAG TARGET PROBE SUCCESS ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
