from __future__ import annotations

import argparse
import json
import shutil
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

try:
    from convert_legacy_codex_docx import (
        BODY_MARKER,
        clean,
        extract_toc_headings,
        is_front_matter,
        is_prompt_line,
        is_variant_title,
        iter_paragraphs,
        looks_like_initial_category,
    )
except ModuleNotFoundError:
    from tool.convert_legacy_codex_docx import (
        BODY_MARKER,
        clean,
        extract_toc_headings,
        is_front_matter,
        is_prompt_line,
        is_variant_title,
        iter_paragraphs,
        looks_like_initial_category,
    )


@dataclass(frozen=True)
class CodexSourceMeta:
    title: str
    source_id: str
    category_path: list[str]
    parent_source_id: str | None


def build_source_metadata(docx_path: Path, source_prefix: str) -> dict[str, CodexSourceMeta]:
    paragraphs = iter_paragraphs(docx_path)
    toc_headings = extract_toc_headings(paragraphs)
    metadata: dict[str, CodexSourceMeta] = {}
    in_body = False
    title = ""
    pending_titles: list[str] = []
    prompt_parts: list[str] = []
    prompt_start = 0
    category_path: list[str] = []
    last_parent: CodexSourceMeta | None = None
    category_updated_for_current_title = False

    def consume_pending_title() -> None:
        nonlocal title, pending_titles, category_path
        nonlocal last_parent, category_updated_for_current_title
        category_updated_for_current_title = False
        if not pending_titles:
            return
        category_candidates: list[str] = []
        for pending in pending_titles[:-1]:
            if pending in toc_headings:
                category_candidates.append(pending)
            elif not category_path and looks_like_initial_category(pending):
                category_candidates.append(pending)
        if category_candidates:
            category_path = category_candidates
            last_parent = None
            category_updated_for_current_title = True
        title = pending_titles[-1]
        pending_titles = []

    def flush() -> None:
        nonlocal prompt_parts, prompt_start, last_parent
        if not prompt_parts:
            return
        prompt = ", ".join(prompt_parts)
        if len(prompt) >= 8:
            parent = (
                last_parent
                if is_variant_title(title)
                and last_parent is not None
                and not category_updated_for_current_title
                else None
            )
            source_id = f"{source_prefix}#p{prompt_start}"
            meta = CodexSourceMeta(
                title=title,
                source_id=source_id,
                category_path=[entry for entry in category_path if entry.strip()],
                parent_source_id=parent.source_id if parent is not None else None,
            )
            metadata[source_id] = meta
            if parent is None:
                last_parent = meta
        prompt_parts = []
        prompt_start = 0

    for paragraph in paragraphs:
        text = clean(paragraph.text)
        if BODY_MARKER in text:
            in_body = True
            pending_titles = []
            continue
        if not in_body or is_front_matter(text):
            continue
        if is_prompt_line(text):
            if not prompt_parts:
                consume_pending_title()
                prompt_start = paragraph.index
            prompt_parts.append(text)
            continue
        flush()
        if text and len(text) <= 80:
            pending_titles.append(text)

    flush()
    return metadata


def enrich_inspirations(
    inspirations_path: Path,
    docx_path: Path,
    *,
    source_type: str,
    source_prefix: str,
    dry_run: bool,
) -> dict[str, Any]:
    entries = json.loads(inspirations_path.read_text(encoding="utf-8"))
    if not isinstance(entries, list):
        raise ValueError(f"{inspirations_path} must contain a JSON array")

    metadata = build_source_metadata(docx_path, source_prefix)
    by_source_id = {
        entry.get("source", {}).get("id"): entry
        for entry in entries
        if isinstance(entry, dict)
        and entry.get("source", {}).get("type") == source_type
    }
    changed = 0
    parent_links = 0
    category_paths = 0
    missing_source_ids: list[str] = []

    for source_id, entry in by_source_id.items():
        meta = metadata.get(source_id)
        if meta is None:
            missing_source_ids.append(source_id)
            continue
        before = json.dumps(entry, sort_keys=True, ensure_ascii=False)
        if meta.category_path:
            entry["sourceCategoryPath"] = meta.category_path
            category_paths += 1
        else:
            entry.pop("sourceCategoryPath", None)
        if meta.parent_source_id and meta.parent_source_id in by_source_id:
            parent = by_source_id[meta.parent_source_id]
            entry["sourceParentId"] = parent["id"]
            entry["sourceParentName"] = parent.get("name", meta.title)
            entry["sourceVariantLabel"] = meta.title
            parent_links += 1
        else:
            entry.pop("sourceParentId", None)
            entry.pop("sourceParentName", None)
            entry.pop("sourceVariantLabel", None)
        after = json.dumps(entry, sort_keys=True, ensure_ascii=False)
        if before != after:
            changed += 1

    backup_path = None
    if changed and not dry_run:
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_path = inspirations_path.with_name(
            f"{inspirations_path.stem}.backup-{timestamp}-codex-source-structure.json"
        )
        shutil.copy2(inspirations_path, backup_path)
        inspirations_path.write_text(
            json.dumps(entries, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        cache_path = inspirations_path.with_name("asset_catalog_cache.json")
        if cache_path.exists():
            cache_path.unlink()

    return {
        "path": str(inspirations_path),
        "sourceType": source_type,
        "metadataCount": len(metadata),
        "matchingEntries": len(by_source_id),
        "changedEntries": changed,
        "categoryPaths": category_paths,
        "parentLinks": parent_links,
        "missingSourceIds": len(missing_source_ids),
        "backupPath": str(backup_path) if backup_path else None,
        "dryRun": dry_run,
    }


def default_inspirations_paths() -> list[Path]:
    roaming = Path.home() / "AppData" / "Roaming"
    candidates = [
        roaming
        / "Novel Studio"
        / "Novel Studio"
        / "novel_studio"
        / "library"
        / "inspirations.json",
    ]
    return [path for path in candidates if path.exists()]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("docx", type=Path)
    parser.add_argument("--inspirations", type=Path, nargs="*")
    parser.add_argument("--source-type", default="novalai_codex_adult_docx")
    parser.add_argument("--source-prefix", default="adult.docx")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    paths = args.inspirations or default_inspirations_paths()
    if not paths:
        raise SystemExit("No inspirations.json files found.")
    reports = [
        enrich_inspirations(
            path,
            args.docx,
            source_type=args.source_type,
            source_prefix=args.source_prefix,
            dry_run=args.dry_run,
        )
        for path in paths
    ]
    print(json.dumps(reports, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
