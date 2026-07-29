#!/usr/bin/env python3
"""Fetch the latest stats from the local dynamic dashboard and rebuild the static site.

Run this after the local DouBao crawler finishes, then push the updated dist/ to GitHub
and deploy to the server.
"""
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

BASE_URL = os.environ.get(
    "DOUBAO_DASHBOARD_BASE_URL",
    "http://127.0.0.1:8766",
).rstrip("/") + "/api/stats"
OUT_FILE = Path(__file__).with_name("src") / "snapshots.json"
PUBLIC_DASHBOARD_NAME = "营养健康洞察"


def fetch(url, timeout=60):
    print(f"Fetching {url} ...")
    req = urllib.request.Request(url, headers={"Cache-Control": "no-store"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def prepare_snapshot(payload):
    """Remove internal customer labels while preserving the complete dataset."""
    payload.setdefault("customer", {})["name"] = PUBLIC_DASHBOARD_NAME
    return payload


def validate_snapshots(snapshots, questions):
    """Fail the export instead of publishing an incomplete customer dashboard."""
    expected_keys = {"__all__", *questions}
    if set(snapshots) != expected_keys:
        raise RuntimeError("快照问题集合不完整，已停止发布。")

    required_sections = (
        "daily_question_sources",
        "daily_question_products",
        "brand_source_daily_analytics",
        "owned_product_source_analytics",
        "products",
        "latest_items",
    )
    normalize_name = lambda value: re.sub(
        r"[\s\-—_·•|｜/（）()]+", "", str(value or "")
    ).casefold()
    for key, payload in snapshots.items():
        missing = [name for name in required_sections if name not in payload]
        if missing:
            raise RuntimeError(f"{key}: 缺少面板数据区块 {', '.join(missing)}")
        if payload.get("capture_skips", {}).get("active_count", 0):
            raise RuntimeError(f"{key}: 仍有未处理采集异常，已停止发布。")

        media_names = {
            normalize_name(item.get("name"))
            for item in payload.get("by_media", [])
            if normalize_name(item.get("name"))
        }
        brand_names = {
            normalize_name(item.get("name"))
            for item in payload.get("products", {}).get("by_brand", [])
            if normalize_name(item.get("name"))
        }
        media_conflicts = sorted(
            media_name
            for media_name in media_names
            if any(
                len(brand_name) >= 3
                and (
                    media_name == brand_name
                    or brand_name in media_name
                    or media_name in brand_name
                )
                for brand_name in brand_names
            )
        )
        if media_conflicts:
            raise RuntimeError(
                f"{key}: 媒体与品牌分类发生冲突 "
                f"{', '.join(media_conflicts)}，已停止发布。"
            )

        product_names = {
            normalize_name(item.get("name"))
            for item in payload.get("products", {}).get("by_product", [])
            if normalize_name(item.get("name"))
        }
        product_conflicts = sorted(product_names & brand_names)
        if product_conflicts:
            raise RuntimeError(
                f"{key}: 品牌与产品完全重复 "
                f"{', '.join(product_conflicts)}，已停止发布。"
            )
        if key == "__all__":
            continue
        if payload.get("products", {}).get("total_product_runs", 0) < payload.get("total_runs", 0):
            raise RuntimeError(f"{key}: 正文产品分析轮次不足，已停止发布。")
        daily = payload["daily_question_sources"][0]
        latest_date = daily.get("dates", [])[-1]
        links = daily.get("top_links_by_date", {}).get(latest_date, [])
        for source_type in ("文章", "视频"):
            if sum(item.get("type") == source_type for item in links) < 10:
                raise RuntimeError(f"{key}: {source_type}信源不足 10 条，已停止发布。")


def main():
    base = prepare_snapshot(fetch(BASE_URL))
    questions = [q["question"] for q in base.get("questions", [])]

    snapshots = {"__all__": base}
    for question in questions:
        url = f"{BASE_URL}?{urllib.parse.urlencode({'question': question})}"
        snapshots[question] = prepare_snapshot(fetch(url))

    validate_snapshots(snapshots, questions)
    OUT_FILE.write_text(json.dumps(snapshots, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Saved {len(snapshots)} snapshots to {OUT_FILE}")

    print("Building static site...")
    npm_command = "npm.cmd" if os.name == "nt" else "npm"
    result = subprocess.run(
        [npm_command, "run", "build"],
        cwd=Path(__file__).parent,
    )
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
