import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

def _normalise_database_url(url: str) -> str:
    # Railway often provides 'postgres://...'
    if url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql+psycopg2://", 1)
    if url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql+psycopg2://", 1)
    return url

DATABASE_URL = os.environ.get("DATABASE_URL")
if not DATABASE_URL:
    # Local fallback only
    DATABASE_URL = "sqlite:///./app.db"

DATABASE_URL = _normalise_database_url(DATABASE_URL)

connect_args = {}
if DATABASE_URL.startswith("sqlite"):
    connect_args = {"check_same_thread": False}

engine = create_engine(
    DATABASE_URL,
    connect_args=connect_args,
    pool_pre_ping=True,
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()
