#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fills untranslated strings in the String Catalogs. Kept for the old command (pre-deploy.sh);
`dev localize --fill` does the work: the languages come from the catalog, the model from
LOCALIZE_MODEL in .devops, replies use structured output, plural variations are listed for
manual work, and it asks before calling the API.

Usage:
    python3 scripts/translate-missing.py [--dry-run]
"""
import os
import shutil
import sys

if shutil.which("dev") is None:
    sys.exit("error: dev isn't on PATH; it does the translation now (dev localize --fill)")
repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = ["dev", "-C", repo, "localize"] + ([] if "--dry-run" in sys.argv else ["--fill"])
os.execvp("dev", args)
