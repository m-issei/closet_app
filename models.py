from __future__ import annotations
import uuid
from datetime import datetime, date
from typing import Any
from sqlalchemy import Column, String, Integer, DateTime, Date, ForeignKey, Enum
from sqlalchemy.dialects.postgresql import UUID as PG_UUID, JSONB
from sqlalchemy.orm import relationship, declarative_base

Base = declarative_base()


class User(Base):
    __tablename__ = "users"

    user_id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    wash_cycle_days = Column(Integer, nullable=False, default=3)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    # 追加: 外部認証プロバイダ関連
    auth_provider_id = Column(String, unique=True, nullable=True)
    auth_providers = relationship("UserAuthProvider", back_populates="user", cascade="all, delete-orphan")

    clothes = relationship("Cloth", back_populates="user", cascade="all, delete-orphan")


class Cloth(Base):
    __tablename__ = "clothes"

    cloth_id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False)
    image_url = Column(String, nullable=False)
    category = Column(String, nullable=False)
    features = Column(JSONB, nullable=False)
    status = Column(String, nullable=False, default="ACTIVE")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    deleted_at = Column(DateTime, nullable=True)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    user = relationship("User", back_populates="clothes")
    worn_history = relationship("WornHistory", back_populates="cloth", cascade="all, delete-orphan")


class WornHistory(Base):
    __tablename__ = "worn_history"

    history_id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    cloth_id = Column(PG_UUID(as_uuid=True), ForeignKey("clothes.cloth_id", ondelete="CASCADE"), nullable=False)
    worn_date = Column(Date, nullable=False)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    cloth = relationship("Cloth", back_populates="worn_history")


class UserAuthProvider(Base):
    __tablename__ = "user_auth_providers"

    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False)
    provider = Column(String, nullable=False)
    provider_user_id = Column(String, nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    user = relationship("User", back_populates="auth_providers")
