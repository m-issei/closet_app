from __future__ import annotations
from typing import List, Optional, Any
from uuid import UUID
from datetime import date
from pydantic import BaseModel, Field, Json


class FeatureSchema(BaseModel):
    color: Optional[str]
    pattern: Optional[str]
    material: Optional[str]
    warmth_level: Optional[int]
    is_rain_ok: Optional[bool] = False
    seasons: Optional[List[str]] = []


class ClothCreate(BaseModel):
    user_id: UUID
    category: str


class ClothOut(BaseModel):
    cloth_id: UUID
    user_id: UUID
    image_url: str
    category: str
    features: FeatureSchema
    status: str

    class Config:
        orm_mode = True


class RecommendRequest(BaseModel):
    user_id: UUID
    latitude: float
    longitude: float
    tpo: Optional[str] = None


class RecommendResponse(BaseModel):
    clothes: List[ClothOut]
    reason: str


class WearRequest(BaseModel):
    user_id: UUID
    cloth_ids: List[UUID]
