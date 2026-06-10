from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Any, Iterable


SAFE_SOURCE_TYPE = "novalai_codex_adult_docx"
DEFAULT_LIBRARY = Path(
    r"C:\Users\admin\AppData\Roaming\org.exception0x0194\nai3_autodraw"
    r"\novel_studio\library\inspirations.json"
)
DEFAULT_EXPORT_DIR = Path("build/adult_codex_export")


def _load_entries(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        raise FileNotFoundError(path)
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError(f"{path} must contain a JSON array")
    return [entry for entry in data if isinstance(entry, dict)]


def _safe_entries(entries: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    safe: list[dict[str, Any]] = []
    for entry in entries:
        source = entry.get("source")
        if not isinstance(source, dict):
            continue
        if source.get("type") != SAFE_SOURCE_TYPE:
            continue
        prompt = str(entry.get("prompt") or "").strip()
        if not prompt:
            continue
        safe.append(
            {
                "id": str(entry.get("id") or "").strip(),
                "name": str(entry.get("name") or "").strip(),
                "prompt": prompt,
                "tags": [
                    str(tag).strip()
                    for tag in entry.get("tags", [])
                    if str(tag).strip()
                ],
                "sourceId": str(source.get("id") or "").strip(),
                "sourcePath": str(source.get("path") or "").strip(),
                "note": str(entry.get("note") or "").strip(),
            }
        )
    safe.sort(key=lambda item: item["id"])
    return safe


def _slug(value: str, fallback: str) -> str:
    text = re.sub(r"[^a-zA-Z0-9._-]+", "-", value).strip("-._").lower()
    return text[:80] if text else fallback


def _write_json(path: Path, entries: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(entries, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _write_jsonl(path: Path, entries: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for entry in entries:
            handle.write(json.dumps(entry, ensure_ascii=False) + "\n")


def _write_csv(path: Path, entries: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["id", "name", "prompt", "tags", "sourceId", "sourcePath", "note"],
        )
        writer.writeheader()
        for entry in entries:
            row = dict(entry)
            row["tags"] = ", ".join(entry["tags"])
            writer.writerow(row)


def _write_prompt_lines(path: Path, entries: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for entry in entries:
            handle.write(entry["prompt"].replace("\n", " ").strip() + "\n")


def _write_txt_combined(path: Path, entries: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for entry in entries:
            handle.write(f"# {entry['id']} | {entry['name']} | {entry['sourceId']}\n")
            handle.write(entry["prompt"].strip() + "\n\n")


def _write_txt_per_entry(path: Path, entries: list[dict[str, Any]]) -> None:
    path.mkdir(parents=True, exist_ok=True)
    for index, entry in enumerate(entries, start=1):
        filename = f"{index:04d}-{_slug(entry['id'], 'entry')}.txt"
        (path / filename).write_text(entry["prompt"].strip() + "\n", encoding="utf-8")


def _read_json_or_jsonl(path: Path) -> list[dict[str, Any]]:
    raw = path.read_text(encoding="utf-8").strip()
    if not raw:
        return []
    if path.suffix.lower() == ".jsonl":
        return [
            json.loads(line)
            for line in raw.splitlines()
            if line.strip()
        ]
    data = json.loads(raw)
    if not isinstance(data, list):
        raise ValueError(f"{path} must contain a JSON array or JSONL records")
    return [entry for entry in data if isinstance(entry, dict)]


def export_command(args: argparse.Namespace) -> None:
    entries = _safe_entries(_load_entries(args.library))
    args.out_dir.mkdir(parents=True, exist_ok=True)
    stem = args.stem
    _write_json(args.out_dir / f"{stem}.json", entries)
    _write_jsonl(args.out_dir / f"{stem}.jsonl", entries)
    _write_csv(args.out_dir / f"{stem}.csv", entries)
    summary = {
        "source": str(args.library),
        "sourceType": SAFE_SOURCE_TYPE,
        "count": len(entries),
        "outputs": [
            str(args.out_dir / f"{stem}.json"),
            str(args.out_dir / f"{stem}.jsonl"),
            str(args.out_dir / f"{stem}.csv"),
        ],
    }
    (args.out_dir / f"{stem}.summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


def convert_command(args: argparse.Namespace) -> None:
    entries = _read_json_or_jsonl(args.input)
    if args.format == "json":
        _write_json(args.output, entries)
    elif args.format == "jsonl":
        _write_jsonl(args.output, entries)
    elif args.format == "csv":
        _write_csv(args.output, entries)
    elif args.format == "prompt-lines":
        _write_prompt_lines(args.output, entries)
    elif args.format == "txt-combined":
        _write_txt_combined(args.output, entries)
    elif args.format == "txt-per-entry":
        _write_txt_per_entry(args.output, entries)
    else:
        raise ValueError(f"Unsupported format: {args.format}")
    print(json.dumps({"count": len(entries), "output": str(args.output)}, ensure_ascii=False))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Export and convert only the risk-filtered usable adult codex entries. "
            "Unprocessed placeholders are ignored."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    export_parser = subparsers.add_parser("export")
    export_parser.add_argument("--library", type=Path, default=DEFAULT_LIBRARY)
    export_parser.add_argument("--out-dir", type=Path, default=DEFAULT_EXPORT_DIR)
    export_parser.add_argument("--stem", default="novalai-codex-adult-safe")
    export_parser.set_defaults(func=export_command)

    convert_parser = subparsers.add_parser("convert")
    convert_parser.add_argument("--input", type=Path, required=True)
    convert_parser.add_argument("--output", type=Path, required=True)
    convert_parser.add_argument(
        "--format",
        choices=[
            "json",
            "jsonl",
            "csv",
            "prompt-lines",
            "txt-combined",
            "txt-per-entry",
        ],
        required=True,
    )
    convert_parser.set_defaults(func=convert_command)
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
