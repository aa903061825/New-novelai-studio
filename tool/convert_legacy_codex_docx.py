from __future__ import annotations

import argparse
import json
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from zipfile import ZipFile


WORD_NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
BODY_MARKER = "以下正文"
SKIP_PREFIXES = ("PS", "ps：", "ps:")
TOC_STYLES = {"2", "4", "5"}
TOC_BULLET = "\uf06c"


@dataclass(frozen=True)
class Paragraph:
    index: int
    style: str
    text: str


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
        or BODY_MARKER in value
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


def is_variant_title(value: str) -> bool:
    return "版本" in value


def stable_id(index: int) -> str:
    return f"legacy-codex-regular-{index + 1:04d}"


def source_ref(paragraph_index: int) -> dict[str, Any]:
    return {
        "type": "legacy_codex",
        "id": f"regular.docx#p{paragraph_index}",
    }


def paragraph_style(paragraph: ET.Element) -> str:
    props = paragraph.find("w:pPr", WORD_NS)
    if props is None:
        return ""
    style = props.find("w:pStyle", WORD_NS)
    if style is None:
        return ""
    return style.attrib.get(f"{{{WORD_NS['w']}}}val", "")


def paragraph_text(paragraph: ET.Element) -> str:
    return clean(
        "".join(
            text.text or "" for text in paragraph.findall(".//w:t", WORD_NS)
        )
    )


def iter_paragraphs(input_path: Path) -> list[Paragraph]:
    with ZipFile(input_path) as archive:
        document = ET.fromstring(archive.read("word/document.xml"))
    paragraphs: list[Paragraph] = []
    for index, paragraph in enumerate(document.findall(".//w:body/w:p", WORD_NS)):
        paragraphs.append(
            Paragraph(
                index=index,
                style=paragraph_style(paragraph),
                text=paragraph_text(paragraph),
            )
        )
    return paragraphs


def toc_label(value: str) -> str:
    text = value.replace(TOC_BULLET, "").strip()
    text = re.sub(r"\s+", " ", text)
    return re.sub(r"\d+$", "", text).strip()


def extract_toc_headings(paragraphs: list[Paragraph]) -> set[str]:
    headings: set[str] = set()
    for paragraph in paragraphs:
        if BODY_MARKER in paragraph.text:
            break
        if paragraph.style in TOC_STYLES:
            label = toc_label(paragraph.text)
            if label and label not in {"目录", "一些前言"}:
                headings.add(label)
    return headings


def looks_like_initial_category(value: str) -> bool:
    if len(value) > 32:
        return False
    if re.search(r"[，。,.：:；;（）()【】\[\]{}]", value):
        return False
    return bool(value.strip())


def build_entry(
    *,
    index: int,
    title: str,
    prompt_parts: list[str],
    paragraph_index: int,
    category_path: list[str],
    parent: dict[str, Any] | None,
) -> dict[str, Any]:
    prompt = ", ".join(part.strip(" ,") for part in prompt_parts if part.strip(" ,"))
    entry = {
        "id": stable_id(index),
        "name": title[:120] if title else f"法典条目 {index + 1}",
        "prompt": prompt,
        "tags": ["法典", "常规"],
        "source": source_ref(paragraph_index),
        "note": "所长常规 NovalAI 个人法典（2026.3.21版，一般所长整理）",
    }
    if category_path:
        entry["sourceCategoryPath"] = category_path
    if parent is not None:
        entry["sourceParentId"] = parent["id"]
        entry["sourceParentName"] = parent["name"]
        entry["sourceVariantLabel"] = title
    return entry


def convert_docx(input_path: Path) -> dict[str, Any]:
    paragraphs = iter_paragraphs(input_path)
    toc_headings = extract_toc_headings(paragraphs)
    entries: list[dict[str, Any]] = []
    in_body = False
    title = ""
    pending_titles: list[str] = []
    prompt_parts: list[str] = []
    prompt_start = 0
    category_path: list[str] = []
    last_parent: dict[str, Any] | None = None
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
            entries.append(
                build_entry(
                    index=len(entries),
                    title=title,
                    prompt_parts=prompt_parts,
                    paragraph_index=prompt_start,
                    category_path=category_path,
                    parent=parent,
                )
            )
            if parent is None:
                last_parent = entries[-1]
        prompt_parts = []
        prompt_start = 0

    for paragraph in paragraphs:
        text = paragraph.text
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
    return {
        "source": {
            "type": "legacy_codex",
            "path": str(input_path),
            "importedFiles": [input_path.name],
            "skippedFiles": [
                {
                    "name": "所长色色NovalAI个人法典（2026.3.21版，一般所长整理）.docx",
                    "reason": "adult explicit prompt collection is imported from the workspace library",
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
