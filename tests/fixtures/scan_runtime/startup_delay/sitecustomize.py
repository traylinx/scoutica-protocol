"""Delay only the grouped scan helper before its signal reset runs."""

from __future__ import annotations

import os
import time


def write_new(path: str) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600)
    os.close(descriptor)


if os.environ.get("SCOUTICA_SCAN_GROUPED") == "1":
    write_new(os.environ["SCOUTICA_GROUP_START_MARKER"])
    time.sleep(10)
