#!/usr/bin/env python3
"""Compatibility launcher for the NanoQL graphical setup assistant."""

from pathlib import Path
import runpy


runpy.run_path(
    str(Path(__file__).with_name("nanoql_setup.pyw")),
    run_name="__main__",
)
