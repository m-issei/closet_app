from __future__ import annotations
import os
import hashlib
import json
from typing import List, Dict, Any, Optional
from pathlib import Path
import random

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")


def _mock_analyze_image(image_path: str) -> Dict[str, Any]:
    """
    Simple deterministic mock that derives features from the filename hash.
    In production, replace this with a call to OpenAI Vision API or other image model.
    """
    h = hashlib.sha256(image_path.encode()).hexdigest()
    # pick color from hash
    colors = ["白", "黒", "赤", "青", "緑", "ベージュ"]
    patterns = ["無地", "ストライプ", "チェック", "花柄"]
    materials = ["コットン", "ポリエステル", "ウール", "シルク"]
    color = colors[int(h[0:2], 16) % len(colors)]
    pattern = patterns[int(h[2:4], 16) % len(patterns)]
    material = materials[int(h[4:6], 16) % len(materials)]
    warmth_level = (int(h[6:8], 16) % 5) + 1
    is_rain_ok = (int(h[8:10], 16) % 2) == 0
    seasons = []
    # heuristics: warm -> summer, cold -> winter
    if warmth_level <= 2:
        seasons = ["春", "秋"]
    elif warmth_level == 3:
        seasons = ["春", "秋", "冬"]
    else:
        seasons = ["冬"]

    return {
        "color": color,
        "pattern": pattern,
        "material": material,
        "warmth_level": warmth_level,
        "is_rain_ok": is_rain_ok,
        "seasons": seasons,
    }


def analyze_image(image_path: str) -> Dict[str, Any]:
    """
    Analyze image to extract features. If OPENAI_API_KEY is present, you could
    implement a real OpenAI Vision call here. For now we use a mock.
    """
    # Placeholder for real API call
    return _mock_analyze_image(image_path)


def _heuristic_score(item: Dict[str, Any], temp_c: float, weather: str, tpo: Optional[str]) -> float:
    # Prefer warmth levels matching temp: map temp to preferred warmth
    # Define target warmth: lower temp -> higher warmth_level
    if temp_c <= 5:
        target = 5
    elif temp_c <= 12:
        target = 4
    elif temp_c <= 18:
        target = 3
    elif temp_c <= 24:
        target = 2
    else:
        target = 1

    wl = item.get("features", {}).get("warmth_level") or 3
    # score inverse distance
    score = 10 - abs(target - wl)
    # if rain and item is not rain OK, penalize
    if weather.lower().startswith("rain") and not item.get("features", {}).get("is_rain_ok", False):
        score -= 3
    # small random tie-breaker
    score += random.random() * 0.5
    return score


def recommend_outfit(candidates: List[Dict[str, Any]], temp_c: float, weather: str, tpo: Optional[str] = None) -> Dict[str, Any]:
    """
    Given candidate clothes (each should include `cloth_id`, `category`, `features`),
    return a curated selection and a textual reason. This uses a simple heuristic by default.
    In production, this should call OpenAI with a prompt that includes candidates and weather.
    """
    # group by category and pick best per category
    by_cat = {}
    for c in candidates:
        cat = c.get("category", "その他")
        by_cat.setdefault(cat, []).append(c)

    selected = []
    reasons = []
    for cat, items in by_cat.items():
        scores = [(item, _heuristic_score(item, temp_c, weather, tpo)) for item in items]
        scores.sort(key=lambda x: x[1], reverse=True)
        best = scores[0][0]
        selected.append(best)
        reasons.append(f"{cat}には{best['features'].get('color')}の{best['features'].get('pattern')}が合います。（候補スコア {scores[0][1]:.1f}）")

    reason_text = "\n".join(reasons)
    return {"selected": selected, "reason": reason_text}
