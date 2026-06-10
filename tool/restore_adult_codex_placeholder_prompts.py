from __future__ import annotations

import argparse
import json
import re
import shutil
from datetime import datetime
from pathlib import Path
from typing import Any


DEFAULT_LIBRARY_DIR = Path(
    r"C:\Users\admin\AppData\Roaming\org.exception0x0194"
    r"\nai3_autodraw\novel_studio\library"
)
DEFAULT_INSPIRATIONS_PATH = DEFAULT_LIBRARY_DIR / "inspirations.json"
DEFAULT_PLACEHOLDER_MAP_PATH = (
    DEFAULT_LIBRARY_DIR / "adult_codex_sensitive_placeholder_map.json"
)
DEFAULT_REPORT_PATH = DEFAULT_LIBRARY_DIR / "adult_codex_placeholder_restore_report.json"
DEFAULT_PLACEHOLDER_SOURCE_TYPE = "novalai_codex_adult_docx_placeholder"
DEFAULT_RESTORED_SOURCE_TYPE = "novalai_codex_adult_docx"
PROMPT_FIELDS = ("prompt", "negativePrompt")
PLACEHOLDER_RE = re.compile(r"<SENS_[A-Z0-9_]+>")


def load_json(path: Path) -> Any:
    if not path.exists():
        raise FileNotFoundError(path)
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def build_placeholder_map(data: Any) -> dict[str, str]:
    table = data.get("placeholders") if isinstance(data, dict) else data
    result: dict[str, str] = {}

    if isinstance(table, list):
        for item in table:
            if not isinstance(item, dict):
                continue
            placeholder = str(item.get("placeholder") or "").strip()
            term = str(item.get("term") or "").strip()
            if placeholder and term:
                result[placeholder] = term
        return result

    if isinstance(table, dict):
        for placeholder, value in table.items():
            key = str(placeholder).strip()
            if isinstance(value, str):
                term = value.strip()
            elif isinstance(value, dict):
                term = str(value.get("term") or "").strip()
            else:
                term = ""
            if key and term:
                result[key] = term
        return result

    raise ValueError("placeholder map must be a list, dict, or contain placeholders")


def backup_file(path: Path, suffix: str) -> Path:
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_dir = path.parent / f"backup-{timestamp}-{suffix}"
    backup_dir.mkdir(parents=True, exist_ok=False)
    destination = backup_dir / path.name
    shutil.copy2(path, destination)
    return destination


def replace_placeholders(text: str, replacements: dict[str, str]) -> tuple[str, int]:
    tokens = set(PLACEHOLDER_RE.findall(text))
    if not tokens:
        return text, 0

    changed = 0
    restored = text
    for token in sorted(tokens, key=len, reverse=True):
        term = replacements.get(token)
        if not term:
            continue
        restored = restored.replace(token, term)
        changed += 1
    return restored, changed


def source_type(entry: dict[str, Any]) -> str:
    source = entry.get("source")
    if not isinstance(source, dict):
        return ""
    return str(source.get("type") or "")


def set_source_type(entry: dict[str, Any], value: str) -> None:
    source = entry.get("source")
    if not isinstance(source, dict):
        source = {}
        entry["source"] = source
    source["type"] = value


def restore_entries(
    entries: list[Any],
    replacements: dict[str, str],
    placeholder_source_type: str,
    restored_source_type: str,
) -> dict[str, Any]:
    stats: dict[str, Any] = {
        "totalEntries": len(entries),
        "placeholderSourceEntries": 0,
        "entriesWithPromptTokens": 0,
        "entriesWithPromptRestored": 0,
        "entriesWithoutPromptTokens": 0,
        "entriesConvertedToRestoredSourceType": 0,
        "fieldReplacementCounts": {field: 0 for field in PROMPT_FIELDS},
        "uniqueTokensSeen": 0,
        "uniqueTokensRestored": 0,
        "uniqueTokensUnresolved": 0,
        "unresolvedTokens": [],
    }
    tokens_seen: set[str] = set()
    tokens_restored: set[str] = set()
    unresolved_tokens: set[str] = set()

    for entry in entries:
        if not isinstance(entry, dict):
            continue

        is_placeholder_source = source_type(entry) == placeholder_source_type
        if is_placeholder_source:
            stats["placeholderSourceEntries"] += 1

        entry_had_tokens = False
        entry_restored = False

        for field in PROMPT_FIELDS:
            value = entry.get(field)
            if not isinstance(value, str):
                continue
            tokens = set(PLACEHOLDER_RE.findall(value))
            if tokens:
                entry_had_tokens = True
                tokens_seen.update(tokens)
                unresolved_tokens.update(token for token in tokens if token not in replacements)

            restored, changed_count = replace_placeholders(value, replacements)
            if changed_count:
                entry[field] = restored
                entry_restored = True
                stats["fieldReplacementCounts"][field] += changed_count
                tokens_restored.update(token for token in tokens if token in replacements)

        if entry_had_tokens:
            stats["entriesWithPromptTokens"] += 1
        elif is_placeholder_source:
            stats["entriesWithoutPromptTokens"] += 1

        has_remaining_tokens = any(
            isinstance(entry.get(field), str)
            and bool(PLACEHOLDER_RE.search(str(entry.get(field))))
            for field in PROMPT_FIELDS
        )
        if is_placeholder_source and not has_remaining_tokens:
            set_source_type(entry, restored_source_type)
            stats["entriesConvertedToRestoredSourceType"] += 1

        if entry_restored:
            stats["entriesWithPromptRestored"] += 1

    stats["uniqueTokensSeen"] = len(tokens_seen)
    stats["uniqueTokensRestored"] = len(tokens_restored)
    stats["uniqueTokensUnresolved"] = len(unresolved_tokens)
    stats["unresolvedTokens"] = sorted(unresolved_tokens)
    return stats


def remove_asset_cache(library_dir: Path, apply: bool) -> bool:
    cache_path = library_dir / "asset_catalog_cache.json"
    if not cache_path.exists():
        return False
    if apply:
        cache_path.unlink()
    return True


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Restore adult codex placeholder prompt tokens in inspirations.json."
    )
    parser.add_argument("--inspirations", type=Path, default=DEFAULT_INSPIRATIONS_PATH)
    parser.add_argument("--map", type=Path, default=DEFAULT_PLACEHOLDER_MAP_PATH)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT_PATH)
    parser.add_argument(
        "--placeholder-source-type",
        default=DEFAULT_PLACEHOLDER_SOURCE_TYPE,
    )
    parser.add_argument(
        "--restored-source-type",
        default=DEFAULT_RESTORED_SOURCE_TYPE,
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the planned changes without writing inspirations.json.",
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    inspirations_path = args.inspirations
    map_path = args.map
    report_path = args.report
    apply_changes = not args.dry_run

    entries_data = load_json(inspirations_path)
    if not isinstance(entries_data, list):
        raise ValueError(f"{inspirations_path} must contain a JSON array")

    replacements = build_placeholder_map(load_json(map_path))
    if not replacements:
        raise ValueError(f"no placeholder replacements loaded from {map_path}")

    entries = json.loads(json.dumps(entries_data, ensure_ascii=False))
    stats = restore_entries(
        entries,
        replacements,
        args.placeholder_source_type,
        args.restored_source_type,
    )

    cache_present = remove_asset_cache(inspirations_path.parent, apply_changes)
    report = {
        "createdAt": datetime.now().isoformat(timespec="seconds"),
        "dryRun": args.dry_run,
        "inspirationsPath": str(inspirations_path),
        "placeholderMapPath": str(map_path),
        "loadedPlaceholderTerms": len(replacements),
        "assetCatalogCacheDeleted": cache_present and apply_changes,
        **stats,
    }

    if apply_changes:
        backup_path = backup_file(inspirations_path, "adult-codex-placeholder-restore")
        report["backupPath"] = str(backup_path)
        write_json(inspirations_path, entries)
        write_json(report_path, report)

    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
