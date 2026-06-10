from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

from docx import Document


SKIP_PREFIXES = ("PS", "ps：", "ps:")


def clean(value: str) -> str:
    return re.sub(r"\s+", " ", value.replace("\xa0", " ")).strip()


def is_sensitive(value: str) -> bool:
    normalized = value.lower()
    return "pst-" in normalized or normalized.startswith("bearer ")


def is_front_matter(value: str) -> bool:
    return (
        not value
        or value == "目录"
        or value.startswith("一些前言")
        or value.startswith(SKIP_PREFIXES)
        or "QQ：" in value
        or "以下正文" in value
    )


def is_prompt_line(value: str) -> bool:
    if not value or is_sensitive(value):
        return False
    lowered = value.lower()
    return (
        "," in value
        or "::" in value
        or "artist:" in lowered
        or "year " in lowered
        or "year_" in lowered
        or "【】" in value
    )


def stable_id(index: int) -> str:
    return f"legacy-codex-regular-{index + 1:04d}"


def source_ref(paragraph_index: int) -> dict[str, Any]:
    return {
        "type": "legacy_codex",
        "id": f"regular.docx#p{paragraph_index}",
    }


def build_entry(
    *,
    index: int,
    title: str,
    prompt_parts: list[str],
    paragraph_index: int,
) -> dict[str, Any]:
    prompt = ", ".join(part.strip(" ,") for part in prompt_parts if part.strip(" ,"))
    return {
        "id": stable_id(index),
        "name": title[:120] if title else f"法典条目 {index + 1}",
        "prompt": prompt,
        "tags": ["法典", "常规"],
        "source": source_ref(paragraph_index),
        "note": "所长常规 NovalAI 个人法典（2026.3.21版，一般所长整理）",
    }


def convert_docx(input_path: Path) -> dict[str, Any]:
    doc = Document(str(input_path))
    entries: list[dict[str, Any]] = []
    in_body = False
    title = ""
    prompt_parts: list[str] = []
    prompt_start = 0

    def flush() -> None:
        nonlocal prompt_parts, prompt_start
        if not prompt_parts:
            return
        prompt = ", ".join(prompt_parts)
        if len(prompt) >= 8:
            entries.append(
                build_entry(
                    index=len(entries),
                    title=title,
                    prompt_parts=prompt_parts,
                    paragraph_index=prompt_start,
                )
            )
        prompt_parts = []
        prompt_start = 0

    for paragraph_index, paragraph in enumerate(doc.paragraphs):
        if paragraph.style.name.startswith("toc"):
            continue
        text = clean(paragraph.text)
        if "以下正文" in text:
            in_body = True
            continue
        if not in_body or is_front_matter(text):
            continue
        if is_prompt_line(text):
            if not prompt_parts:
                prompt_start = paragraph_index
            prompt_parts.append(text)
            continue
        flush()
        if text and len(text) <= 80:
            title = text

    flush()
    return {
        "source": {
            "type": "legacy_codex",
            "path": str(input_path),
            "importedFiles": [input_path.name],
            "skippedFiles": [
                {
                    "name": "所长色色NovalAI个人法典（2026.3.21版，一般所长整理）.docx",
                    "reason": "adult explicit prompt collection was not converted",
                }
            ],
        },
        "inspirations": entries,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    data = convert_docx(args.input)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(data['inspirations'])} codex entries to {args.output}")


if __name__ == "__main__":
    main()
