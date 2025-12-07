from __future__ import annotations
import os
import hashlib
import json
import asyncio
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


async def analyze_image(image_path: str) -> Dict[str, Any]:
    """
    Analyze image to extract features. If OPENAI_API_KEY is present, call OpenAI Vision (async).
    Falls back to mock when API key is not present.
    """
    if OPENAI_API_KEY:
        try:
            return await analyze_image_with_openai(image_path)
        except Exception:
            # fallback to mock on any error
            return _mock_analyze_image(image_path)
    return _mock_analyze_image(image_path)


# ---------- OpenAI / production helpers (async) ----------
if OPENAI_API_KEY:
    try:
        from openai import AsyncOpenAI
        _openai_client = AsyncOpenAI(api_key=OPENAI_API_KEY)
    except Exception:
        _openai_client = None


async def analyze_image_with_openai(image_url: str) -> Dict[str, Any]:
    """
    OpenAI (GPT-4o) を使って画像を解析する。
    画像認識用の正しいペイロード形式に修正済み。
    """
    if not OPENAI_API_KEY or _openai_client is None:
        return _mock_analyze_image(image_url)

    prompt_text = (
        "以下のJSON形式で出力してください: "
        "{\"color\": str, \"pattern\": str, \"material\": str, "
        "\"warmth_level\": int(1-5), \"is_rain_ok\": bool, \"seasons\": list(str)}。 "
        "画像を解析してファッション特徴を抽出してください。"
    )

    try:
        resp = await _openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": "You are a professional fashion analyst."},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt_text},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": image_url,
                                "detail": "low"  # コスト節約のためlow推奨（十分認識できます）
                            }
                        }
                    ]
                }
            ],
            response_format={"type": "json_object"},
            temperature=0.0,
        )
        
        content = resp.choices[0].message.content
        if isinstance(content, (str, bytes)):
            return json.loads(content)
        elif isinstance(content, dict):
            return content
            
    except Exception as e:
        print(f"OpenAI API Error: {e}")
        # エラー時はモックにフォールバック
        pass

    return _mock_analyze_image(image_url)

async def recommend_with_openai(candidates: List[Dict[str, Any]], temp_c: float, weather: str, tpo: Optional[str] = None) -> Dict[str, Any]:
    """
    Call OpenAI to get a recommended subset and reasoning. Returns dict {selected: [...], reason: str}.
    If API is not available, raises an exception.
    """
    if not OPENAI_API_KEY or _openai_client is None:
        raise RuntimeError("OpenAI client not configured")

    system = "あなたはプロのスタイリストです。候補リストと天候・気温・TPOを考慮し、最適な組み合わせをJSONで返してください。"
    user_msg = {
        "candidates": candidates,
        "temp_c": temp_c,
        "weather": weather,
        "tpo": tpo,
    }

    try:
        resp = await _openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": json.dumps(user_msg, ensure_ascii=False)},
            ],
            response_format={"type": "json_object"},
            temperature=0.2,
        )
        content = resp.choices[0].message.content
        if isinstance(content, str):
            obj = json.loads(content)
        else:
            obj = content
        # Expecting {'selected': [ { 'cloth_id': '...', ... }, ... ], 'reason': '...'}
        return obj
    except Exception:
        raise


async def get_recommendation(candidates: List[Dict[str, Any]], temp_c: float, weather: str, tpo: Optional[str] = None) -> Dict[str, Any]:
    """
    High-level wrapper: use OpenAI when available, otherwise fallback to local heuristic.
    """
    if OPENAI_API_KEY:
        try:
            return await recommend_with_openai(candidates, temp_c, weather, tpo)
        except Exception:
            return recommend_outfit(candidates, temp_c, weather, tpo)
    else:
        return recommend_outfit(candidates, temp_c, weather, tpo)


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
