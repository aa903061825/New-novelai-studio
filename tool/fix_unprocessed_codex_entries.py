"""
fix_unprocessed_codex_entries.py
---------------------------------
诊断并修复 inspirations.json 中 source.type == "novalai_codex_adult_docx_unprocessed"
的占位条目，使其进入素材库。

用法：
  python fix_unprocessed_codex_entries.py            # 诊断模式（只分析，不写文件）
  python fix_unprocessed_codex_entries.py --apply    # 应用修复

修复策略（按优先级）：
  1. 若 report 文件存在且含 rawPrompt/prompt/content 字段 → 填入 prompt 并改 source.type
  2. 若条目自身已有非空 prompt → 仅改 source.type
  3. 若条目有 note/rawText 字段 → 将其作为 prompt 并改 source.type
  4. 其余：仅改 source.type，prompt 留空（条目仍会进入库，只是无 prompt）
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
from datetime import datetime
from pathlib import Path
from typing import Any

LIBRARY_DIR = Path(
    r"C:\Users\admin\AppData\Roaming\Novel Studio"
    r"\Novel Studio\novel_studio\library"
)
INSPIRATIONS_PATH = LIBRARY_DIR / "inspirations.json"
REPORT_PATH = LIBRARY_DIR / "adult_codex_unprocessed_placeholders_report.json"

UNPROCESSED_TYPE = "novalai_codex_adult_docx_unprocessed"
PROCESSED_TYPE = "novalai_codex_adult_docx"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def backup(path: Path) -> Path:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    dest = path.with_name(f"{path.stem}_backup_{ts}{path.suffix}")
    shutil.copy2(path, dest)
    return dest


def _pick_prompt(entry: dict, report_map: dict[str, Any]) -> str:
    """从多个来源中选出最合适的 prompt 字符串。"""
    eid = str(entry.get("id") or "")
    source_id = ""
    if isinstance(entry.get("source"), dict):
        source_id = str(entry["source"].get("id") or "")

    # 1. 从 report 文件查找
    for key in (eid, source_id):
        if key and key in report_map:
            rec = report_map[key]
            if isinstance(rec, str) and rec.strip():
                return rec.strip()
            if isinstance(rec, dict):
                for field in ("rawPrompt", "prompt", "content", "raw", "text"):
                    val = rec.get(field)
                    if val and str(val).strip():
                        return str(val).strip()

    # 2. 条目自身字段
    for field in ("prompt", "content", "rawPrompt", "rawText", "note"):
        val = entry.get(field)
        if val and str(val).strip():
            return str(val).strip()

    return ""


def build_report_map(report_data: Any) -> dict[str, Any]:
    """把 report 文件解析成 id → 数据 的字典。"""
    if isinstance(report_data, dict):
        # 可能是 {id: {...}, id: {...}} 结构
        return {str(k): v for k, v in report_data.items()}
    if isinstance(report_data, list):
        result: dict[str, Any] = {}
        for item in report_data:
            if not isinstance(item, dict):
                continue
            for key_field in ("id", "sourceId", "entryId"):
                key = item.get(key_field)
                if key:
                    result[str(key)] = item
                    break
        return result
    return {}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="实际写入修复，默认只诊断")
    args = parser.parse_args()

    # --- 加载文件 ---
    if not INSPIRATIONS_PATH.exists():
        print(f"[ERROR] 找不到 inspirations.json: {INSPIRATIONS_PATH}")
        return

    entries: list[dict] = load_json(INSPIRATIONS_PATH)
    if not isinstance(entries, list):
        print("[ERROR] inspirations.json 不是 JSON 数组")
        return

    report_map: dict[str, Any] = {}
    if REPORT_PATH.exists():
        try:
            report_data = load_json(REPORT_PATH)
            report_map = build_report_map(report_data)
            print(f"[INFO] 已加载 report 文件，条目数: {len(report_map)}")
        except Exception as e:
            print(f"[WARN] 加载 report 文件失败: {e}")
    else:
        print(f"[INFO] 未找到 report 文件（{REPORT_PATH.name}），将尝试从条目自身数据中提取 prompt")

    # --- 分析 ---
    total = len(entries)
    unprocessed = [e for e in entries if isinstance(e, dict)
                   and isinstance(e.get("source"), dict)
                   and e["source"].get("type") == UNPROCESSED_TYPE]

    print(f"\n[统计] 全部条目: {total}")
    print(f"[统计] 未处理占位 (type={UNPROCESSED_TYPE!r}): {len(unprocessed)}")

    if not unprocessed:
        print("[OK] 没有未处理占位条目，无需修复。")
        return

    # 分析 unprocessed 条目的字段情况
    has_prompt = [e for e in unprocessed if str(e.get("prompt") or "").strip()]
    no_prompt  = [e for e in unprocessed if not str(e.get("prompt") or "").strip()]
    from_report = [e for e in unprocessed if _pick_prompt(e, report_map)]

    print(f"[统计] 其中已有 prompt 字段: {len(has_prompt)}")
    print(f"[统计] 无 prompt 字段:       {len(no_prompt)}")
    print(f"[统计] 可从 report/自身提取 prompt: {len(from_report)}")

    # 预览前 3 条
    print("\n[预览] 前 3 条未处理条目：")
    for e in unprocessed[:3]:
        print(f"  id={e.get('id')!r}  name={e.get('name')!r}")
        print(f"  source={e.get('source')}")
        print(f"  prompt (现有)={str(e.get('prompt',''))[:80]!r}")
        filled = _pick_prompt(e, report_map)
        print(f"  prompt (填入)={filled[:80]!r}")
        print()

    if not args.apply:
        print("[提示] 加 --apply 参数以实际应用修复。")
        return

    # --- 应用修复 ---
    backup_path = backup(INSPIRATIONS_PATH)
    print(f"[备份] 原文件已备份至: {backup_path.name}")

    fixed_count = 0
    no_prompt_count = 0

    for entry in entries:
        if not isinstance(entry, dict):
            continue
        src = entry.get("source")
        if not isinstance(src, dict):
            continue
        if src.get("type") != UNPROCESSED_TYPE:
            continue

        filled = _pick_prompt(entry, report_map)
        if filled:
            entry["prompt"] = filled
            fixed_count += 1
        else:
            no_prompt_count += 1

        # 关键：改 source.type
        src["type"] = PROCESSED_TYPE

    INSPIRATIONS_PATH.write_text(
        json.dumps(entries, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"\n[完成] 已处理 {len(unprocessed)} 条占位条目：")
    print(f"  - 填入 prompt 并改 type: {fixed_count} 条")
    print(f"  - 仅改 type（prompt 为空）: {no_prompt_count} 条")
    print(f"  文件已保存: {INSPIRATIONS_PATH}")
    print("\n重启应用后，这些条目将出现在素材库中。")


if __name__ == "__main__":
    main()
