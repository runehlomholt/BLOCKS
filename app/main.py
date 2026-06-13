from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles

from . import models, state
from .config import settings
from .database import SessionLocal, engine
from .design_loader import load_design, validate_balanced_sets
from .question_battery_loader import load_question_batteries
from .routes import admin, attention, participants


def initialise_experiment():
    models.Base.metadata.create_all(bind=engine)
    design = load_design(settings.vignette_content_path)
    if not settings.allow_unbalanced_sets:
        validate_balanced_sets(design)
    base_dir = Path(__file__).resolve().parent.parent
    batteries = load_question_batteries(base_dir / "question_batteries")
    if not batteries:
        raise RuntimeError("No question batteries were loaded")
    state.set_experiment(design, batteries)

    db = SessionLocal()
    try:
        if db.query(models.AllocationLock).filter(models.AllocationLock.id == 1).first() is None:
            db.add(models.AllocationLock(id=1))
            db.commit()
    finally:
        db.close()


@asynccontextmanager
async def lifespan(app):
    initialise_experiment()
    yield


app = FastAPI(
    title="BLOCKS: an application for administering blocked, text-based factorial vignette studies",
    lifespan=lifespan,
)
templates = Jinja2Templates(directory="app/templates")
app.mount("/static", StaticFiles(directory="app/static"), name="static")
app.include_router(participants.router)
app.include_router(attention.router)
app.include_router(admin.router)


@app.exception_handler(HTTPException)
async def http_error(request: Request, exc: HTTPException):
    if request.url.path == "/export":
        from fastapi.responses import JSONResponse

        return JSONResponse({"detail": exc.detail}, status_code=exc.status_code)
    return templates.TemplateResponse(
        "error.html",
        {"request": request, "message": str(exc.detail)},
        status_code=exc.status_code,
    )
