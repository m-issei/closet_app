from __future__ import annotations
import os
from pathlib import Path
from typing import List
import uuid
from datetime import date, datetime, timedelta

from fastapi import FastAPI, UploadFile, File, Form, Depends, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import select, and_, not_, exists

from models import Base, User, Cloth, WornHistory
from schemas import ClothCreate, ClothOut, RecommendRequest, RecommendResponse, WearRequest
from services.ai_stylist import analyze_image, recommend_outfit

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql+asyncpg://user:password@localhost:5432/closet")

engine = create_async_engine(DATABASE_URL, echo=False, future=True)
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

app = FastAPI(title="SmartOutfit API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = Path(__file__).parent / "uploads"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


async def get_session() -> AsyncSession:
    async with AsyncSessionLocal() as session:
        yield session


@app.on_event("startup")
async def on_startup():
    # Ensure DB models exist: in production use migrations (alembic)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


@app.post("/clothes", response_model=ClothOut)
async def create_cloth(
    user_id: str = Form(...),
    category: str = Form(...),
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_session),
):
    # save image
    ext = Path(file.filename).suffix or ".jpg"
    filename = f"{uuid.uuid4().hex}{ext}"
    dest = UPLOAD_DIR / filename
    with open(dest, "wb") as f:
        content = await file.read()
        f.write(content)

    image_url = str(dest)

    # analyze image (mock or real)
    features = analyze_image(image_url)

    # ensure user exists
    q = select(User).where(User.user_id == uuid.UUID(user_id))
    res = await db.execute(q)
    user = res.scalars().first()
    if user is None:
        # create minimal user
        user = User(user_id=uuid.UUID(user_id))
        db.add(user)
        await db.commit()

    cloth = Cloth(user_id=uuid.UUID(user_id), image_url=image_url, category=category, features=features)
    db.add(cloth)
    await db.commit()
    await db.refresh(cloth)

    return cloth


async def mock_weather_api(lat: float, lon: float) -> dict:
    # Very simple mock: return weather string and temp_c
    # For deterministic results, use lat/lon to vary temperature
    temp_c = 15 + (int(abs(lat * 100)) % 15) - (int(abs(lon * 100)) % 7)
    weather = "clear" if (int(lat * 100) % 3) != 0 else "rain"
    return {"weather": weather, "temp_c": float(temp_c)}


@app.post("/recommend", response_model=RecommendResponse)
async def recommend(req: RecommendRequest, db: AsyncSession = Depends(get_session)):
    # 1) get weather
    weather_info = await mock_weather_api(req.latitude, req.longitude)
    weather = weather_info["weather"]
    temp_c = weather_info["temp_c"]

    # 2) compute cutoff date for wash_cycle
    q_user = select(User).where(User.user_id == req.user_id)
    res = await db.execute(q_user)
    user = res.scalars().first()
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")

    wash_days = user.wash_cycle_days or 3
    cutoff_date = date.today() - timedelta(days=wash_days)

    # 3) query clothes: status = 'ACTIVE' and not in LAUNDRY and not worn within wash_cycle_days
    q = select(Cloth).where(
        Cloth.user_id == req.user_id,
        Cloth.status == "ACTIVE",
    )
    res = await db.execute(q)
    clothes = res.scalars().all()

    # filter out laundry and recently worn
    candidates = []
    for c in clothes:
        # status check already done; skip LAUNDRY anyway
        if c.status == "LAUNDRY":
            continue
        # check worn history
        q2 = select(WornHistory).where(WornHistory.cloth_id == c.cloth_id, WornHistory.worn_date >= cutoff_date)
        res2 = await db.execute(q2)
        recent = res2.scalars().first()
        if recent:
            continue
        candidates.append({
            "cloth_id": c.cloth_id,
            "category": c.category,
            "features": c.features,
            "image_url": c.image_url,
        })

    if not candidates:
        return RecommendResponse(clothes=[], reason="候補となる服が見つかりませんでした。")

    # 4) call AI stylist (mock) to pick
    ai_result = recommend_outfit(candidates, temp_c=temp_c, weather=weather, tpo=req.tpo)

    selected_ids = {s["cloth_id"] for s in ai_result["selected"]}

    # fetch selected cloth objects for full output
    q_sel = select(Cloth).where(Cloth.cloth_id.in_(list(selected_ids)))
    res = await db.execute(q_sel)
    sel_objs = res.scalars().all()

    return RecommendResponse(clothes=sel_objs, reason=ai_result["reason"])


@app.post("/wear")
async def wear(req: WearRequest, db: AsyncSession = Depends(get_session)):
    # record worn_history for each cloth_id
    entries = []
    for cid in req.cloth_ids:
        wh = WornHistory(cloth_id=cid, worn_date=date.today())
        db.add(wh)
        entries.append(wh)
    await db.commit()
    return JSONResponse({"recorded": len(entries)})
