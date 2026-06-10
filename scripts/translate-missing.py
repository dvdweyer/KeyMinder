#!/usr/bin/env python3
"""
Translates any untranslated strings in KeyMinder/Localizable.xcstrings using the
Claude API. Reads ANTHROPIC_API_KEY from the environment (or scripts/.env).

Usage:
    python3 scripts/translate-missing.py [--dry-run]

Returns exit code 0 when done (including when there is nothing to translate).
"""
import json
import os
import sys
import subprocess
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
REPO_DIR = SCRIPT_DIR.parent
XCSTRINGS_PATH = REPO_DIR / "KeyMinder" / "Localizable.xcstrings"

LANGUAGES = {
    "ar": "Arabic",
    "da": "Danish",
    "de": "German",
    "es": "Spanish",
    "fi": "Finnish",
    "fr": "French",
    "he": "Hebrew",
    "hi": "Hindi",
    "it": "Italian",
    "ja": "Japanese",
    "nb": "Norwegian Bokmål",
    "nl": "Dutch",
    "pt": "Portuguese (Brazilian)",
    "sv": "Swedish",
    "zh-Hans": "Chinese (Simplified)",
    "zh-Hant": "Chinese (Traditional)",
}

DRY_RUN = "--dry-run" in sys.argv


def load_api_key() -> str:
    key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not key:
        env_file = SCRIPT_DIR / ".env"
        if env_file.exists():
            for line in env_file.read_text().splitlines():
                if line.startswith("ANTHROPIC_API_KEY="):
                    key = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not key:
        print("error: ANTHROPIC_API_KEY not set — add it to the environment or scripts/.env", file=sys.stderr)
        sys.exit(1)
    return key


def find_missing(strings: dict) -> dict[str, list[str]]:
    """Returns {source_key: [lang_code, ...]} for all untranslated entries.

    Entries that use the 'variations' structure (plural rules) are considered
    translated as-is — they require manual attention and are outside the scope
    of simple string translation.
    """
    missing: dict[str, list[str]] = {}
    for key, val in strings.items():
        locs = val.get("localizations", {})
        for lang in LANGUAGES:
            if lang not in locs:
                missing.setdefault(key, []).append(lang)
            else:
                entry = locs[lang]
                if "variations" in entry:
                    continue  # plural form — already handled
                state = entry.get("stringUnit", {}).get("state", "")
                if state in ("needs_translation", "new", ""):
                    missing.setdefault(key, []).append(lang)
    return missing


def translate_batch(client, source_texts: list[str], lang_code: str, lang_name: str) -> list[str]:
    """Translates a list of English strings into one language in a single API call."""
    numbered = "\n".join(f"{i+1}. {t}" for i, t in enumerate(source_texts))
    prompt = (
        f"Translate the following UI strings from English to {lang_name} ({lang_code}).\n"
        "These are short labels and help texts for a macOS app called KeyMinder that shows keyboard shortcuts.\n"
        "Preserve the tone: concise, technical, macOS-native style.\n"
        "Return ONLY a JSON array of translated strings in the same order, no other text.\n\n"
        f"{numbered}"
    )
    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=2048,
        messages=[{"role": "user", "content": prompt}],
    )
    raw = response.content[0].text.strip()
    # Strip markdown code fences if present
    if raw.startswith("```"):
        raw = raw.split("\n", 1)[1].rsplit("```", 1)[0].strip()
    translations = json.loads(raw)
    if len(translations) != len(source_texts):
        raise ValueError(f"Expected {len(source_texts)} translations for {lang_name}, got {len(translations)}")
    return translations


def main() -> None:
    data = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    strings = data["strings"]

    missing = find_missing(strings)
    if not missing:
        print("    All strings are translated — nothing to do.")
        return

    total = sum(len(langs) for langs in missing.values())
    print(f"    Found {len(missing)} string(s) needing translation across {total} language slot(s).")
    for key, langs in missing.items():
        short = key if len(key) <= 60 else key[:57] + "…"
        print(f"      • {short!r}: {', '.join(langs)}")

    if DRY_RUN:
        print("    --dry-run: skipping API calls.")
        return

    import anthropic
    client = anthropic.Anthropic(api_key=load_api_key())

    # Group by language so we make one API call per language (not per string).
    lang_to_keys: dict[str, list[str]] = {}
    for key, langs in missing.items():
        for lang in langs:
            lang_to_keys.setdefault(lang, []).append(key)

    for lang_code, keys in sorted(lang_to_keys.items()):
        lang_name = LANGUAGES[lang_code]
        print(f"    Translating {len(keys)} string(s) → {lang_name}…")
        translations = translate_batch(client, keys, lang_code, lang_name)
        for key, translation in zip(keys, translations):
            strings[key].setdefault("localizations", {})[lang_code] = {
                "stringUnit": {"state": "translated", "value": translation}
            }

    # Xcode's JSON style uses "key" : "value" (space before colon).
    # json.dumps produces "key": "value", so we post-process to match.
    import re
    output = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    output = re.sub(r'("(?:[^"\\]|\\.)*"):', r'\1 :', output)
    XCSTRINGS_PATH.write_text(output, encoding="utf-8")
    print(f"    Wrote {XCSTRINGS_PATH.relative_to(REPO_DIR)}")


if __name__ == "__main__":
    main()
