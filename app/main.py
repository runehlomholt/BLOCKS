import csv
import os
import random
import uuid
from pathlib import Path
from datetime import datetime, timezone
from io import StringIO

from fastapi import (
    FastAPI,
    Request,
    Depends,
    Form,
    HTTPException,
)
from fastapi.responses import (
    HTMLResponse,
    RedirectResponse,
    StreamingResponse,
)
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from .database import SessionLocal, engine
from . import models
from .design_loader import load_design, validate_balanced_sets, get_design_path
from .question_battery_loader import load_question_batteries


app = FastAPI()

app.mount("/static", StaticFiles(directory="app/static"), name="static")
templates = Jinja2Templates(directory="app/templates")

DESIGN = None
QUESTION_BATTERIES = {}


# -------------------------
# DB
# -------------------------

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# -------------------------
# Helpers
# -------------------------

def token_required() -> bool:
    return os.environ.get("TOKEN_REQUIRED", "1") == "1"


def assign_vignette_set() -> str:
    if not DESIGN or not DESIGN.sets:
        raise HTTPException(status_code=500, detail="Design not loaded")
    return random.choice(list(DESIGN.sets.keys()))


def _load_design_or_fail() -> None:
    global DESIGN
    design_path = get_design_path()
    DESIGN = load_design(design_path)
    if os.environ.get("ALLOW_UNBALANCED_SETS", "0") != "1":
        validate_balanced_sets(DESIGN)


def _ensure_respondent_has_attention_plan(respondent, num_vignettes: int) -> None:
    if respondent.attention_order is not None:
        return

    if num_vignettes < 2:
        respondent.attention_order = None
        respondent.attention_completed = True
        respondent.attention_correct = None
        return

    respondent.attention_order = random.randint(2, num_vignettes - 1)
    respondent.attention_completed = False
    respondent.attention_correct = None


def _math_problem(respondent_uuid: str, order: int):
    seed = f"{respondent_uuid}:{order}:attention"
    rng = random.Random(seed)
    a = rng.randint(2, 9)
    b = rng.randint(2, 9)
    return a, b, a + b


def _all_question_ids() -> list[str]:
    qids = []
    seen = set()
    for battery in QUESTION_BATTERIES.values():
        for q in battery:
            qid = str(q["question_id"])
            if qid not in seen:
                seen.add(qid)
                qids.append(qid)
    return qids


# -------------------------
# Startup
# -------------------------

@app.on_event("startup")
def on_startup():
    models.Base.metadata.create_all(bind=engine)
    _load_design_or_fail()

    global QUESTION_BATTERIES
    BASE_DIR = Path(__file__).resolve().parent.parent
    QUESTION_BATTERIES = load_question_batteries(BASE_DIR / "question_batteries")


# -------------------------
# Core flow
# -------------------------

@app.get("/", response_class=HTMLResponse)
def start(request: Request, db: Session = Depends(get_db)):
    token = request.query_params.get("token")
    if token_required() and not token:
        return templates.TemplateResponse(
            "token_error.html", {"request": request}, status_code=400
        )

    if not token:
        token = f"debug_{uuid.uuid4()}"

    respondent = (
        db.query(models.Respondent)
        .filter(models.Respondent.external_id == token)
        .first()
    )

    if respondent is None:
        respondent = models.Respondent(
            respondent_uuid=str(uuid.uuid4()),
            external_id=token,
            condition_set=assign_vignette_set(),
        )
        db.add(respondent)
        db.commit()
        db.refresh(respondent)

        vignettes = DESIGN.sets[respondent.condition_set][:]
        random.shuffle(vignettes)

        for order, v in enumerate(vignettes, start=1):
            db.add(
                models.AssignedVignette(
                    respondent_id=respondent.id,
                    vignette_id=str(v["id"]),
                    display_order=order,
                )
            )

        _ensure_respondent_has_attention_plan(respondent, len(vignettes))
        db.commit()

    return RedirectResponse(
        url=f"/vignette/{respondent.respondent_uuid}?order=1",
        status_code=302,
    )


@app.get("/vignette/{respondent_uuid}", response_class=HTMLResponse)
def show_vignette(
    request: Request,
    respondent_uuid: str,
    order: int = 1,
    db: Session = Depends(get_db),
):
    respondent = (
        db.query(models.Respondent)
        .filter(models.Respondent.respondent_uuid == respondent_uuid)
        .first()
    )

    if respondent is None:
        raise HTTPException(status_code=404, detail="Respondent not found")

    # --- attention check redirect (unchanged) ---
    if (
        respondent.attention_order is not None
        and not respondent.attention_completed
        and int(order) == int(respondent.attention_order) + 1
    ):
        return RedirectResponse(
            url=f"/attention/{respondent_uuid}?order={order}",
            status_code=302,
        )

    assigned = (
        db.query(models.AssignedVignette)
        .filter(
            models.AssignedVignette.respondent_id == respondent.id,
            models.AssignedVignette.display_order == order,
        )
        .first()
    )

    if assigned is None:
        return templates.TemplateResponse(
            "finished.html",
            {"request": request},
        )

    vignette = next(
        (
            v
            for v in DESIGN.sets[respondent.condition_set]
            if str(v["id"]) == str(assigned.vignette_id)
        ),
        None,
    )

    if vignette is None:
        raise HTTPException(status_code=500, detail="Vignette not found in design")

    # ==================================================
    # Progress (purely presentational)
    # order is 1-based, total_vignettes is count
    # ==================================================
    total_vignettes = len(DESIGN.sets[respondent.condition_set])
    current_index = int(order)
    progress_percent = round((current_index / max(total_vignettes, 1)) * 100)

    # clamp defensively
    progress_percent = max(0, min(progress_percent, 100))

    # attach progress to vignette dict (safe copy)
    vignette = dict(vignette)
    vignette["progress_percent"] = progress_percent

    # ==================================================
    # Batteries: support BOTH list and dict loader outputs
    # (design refinement: keep template stable)
    # ==================================================
    if isinstance(QUESTION_BATTERIES, dict):
        batteries_for_template = list(QUESTION_BATTERIES.values())
    else:
        batteries_for_template = QUESTION_BATTERIES  # already a list

    return templates.TemplateResponse(
        "vignette.html",
        {
            "request": request,
            "respondent_uuid": respondent_uuid,
            "vignette": vignette,
            "order": order,
            "start_timestamp": datetime.now(timezone.utc).isoformat(),
            "batteries": batteries_for_template,
        },
    )


    # ==================================================
    # NEW (1): progress calculation (purely presentational)
    # ==================================================
    total_vignettes = len(DESIGN.sets[respondent.condition_set])
    current_index = int(order)
    progress_percent = round((current_index / total_vignettes) * 100)

    # ==================================================
    # NEW (2): attach progress to vignette dict
    # ==================================================
    vignette = dict(vignette)  # safe copy
    vignette["progress_percent"] = progress_percent

    return templates.TemplateResponse(
        "vignette.html",
        {
            "request": request,
            "respondent_uuid": respondent_uuid,
            "vignette": vignette,
            "order": order,
            "start_timestamp": datetime.now(timezone.utc).isoformat(),

            # ==================================================
            # NEW (3): pass batteries as LIST, not dict
            # ==================================================
            "batteries": list(QUESTION_BATTERIES.values()),
        },
    )



@app.post("/vignette/{respondent_uuid}")
async def submit_vignette(
    request: Request,
    respondent_uuid: str,
    order: int = Form(...),
    vignette_id: str = Form(...),
    started_at: str = Form(...),
    ended_at: str = Form(...),
    click_count: int = Form(...),
    db: Session = Depends(get_db),
):
    respondent = (
        db.query(models.Respondent)
        .filter(models.Respondent.respondent_uuid == respondent_uuid)
        .first()
    )

    started_dt = datetime.fromisoformat(started_at)
    ended_dt = datetime.fromisoformat(ended_at)
    latency_ms = int((ended_dt - started_dt).total_seconds() * 1000)

    form = await request.form()
    for key, value in form.items():
        if key.startswith("battery_"):
            db.add(
                models.VignetteResponse(
                    respondent_id=respondent.id,
                    vignette_id=str(vignette_id),
                    vignette_order=int(order),
                    question_id=key.replace("battery_", ""),
                    response=str(value),
                    started_at=started_dt,
                    ended_at=ended_dt,
                    latency_ms=latency_ms,
                    click_count=int(click_count),
                )
            )

    db.commit()

    return RedirectResponse(
        url=f"/vignette/{respondent_uuid}?order={int(order) + 1}",
        status_code=302,
    )


# -------------------------
# ATTENTION CHECK
# -------------------------

@app.get("/attention/{respondent_uuid}", response_class=HTMLResponse)
def attention_check(
    request: Request,
    respondent_uuid: str,
    order: int = 2,
    db: Session = Depends(get_db),
):
    a, b, _ = _math_problem(respondent_uuid, int(order))
    return templates.TemplateResponse(
        "attention_check.html",
        {
            "request": request,
            "respondent_uuid": respondent_uuid,
            "order": int(order),
            "a": a,
            "b": b,
        },
    )
    
@app.post("/attention/{respondent_uuid}")
def submit_attention_check(
    respondent_uuid: str,
    order: int = Form(...),
    answer: int = Form(...),
    db: Session = Depends(get_db),
):
    respondent = (
        db.query(models.Respondent)
        .filter(models.Respondent.respondent_uuid == respondent_uuid)
        .first()
    )

    _, _, expected = _math_problem(respondent_uuid, int(order))
    respondent.attention_completed = True
    respondent.attention_correct = int(answer) == int(expected)
    db.commit()

    return RedirectResponse(
        url=f"/vignette/{respondent_uuid}?order={int(order)}",
        status_code=302,
    )


# -------------------------
# EXPORT
# -------------------------

@app.get("/export")
def export_csv(db: Session = Depends(get_db)):
    """
    Export one row per respondent × vignette.
    Item responses are columns.
    Includes attention-check metadata.
    """

    rows = (
        db.query(
            models.Respondent.respondent_uuid.label("internal_id"),
            models.Respondent.external_id.label("respondent_id"),
            models.Respondent.condition_set.label("block"),
            models.Respondent.attention_order,
            models.Respondent.attention_completed,
            models.Respondent.attention_correct,
            models.VignetteResponse.vignette_id.label("vignette"),
            models.VignetteResponse.vignette_order,
            models.VignetteResponse.question_id,
            models.VignetteResponse.response,
            models.VignetteResponse.latency_ms,
            models.VignetteResponse.click_count,
        )
        .join(
            models.VignetteResponse,
            models.VignetteResponse.respondent_id == models.Respondent.id,
        )
        .order_by(
            models.Respondent.respondent_uuid,
            models.VignetteResponse.vignette_order,
        )
        .all()
    )

    # All item IDs that appear in the dataset
    item_ids = sorted({r.question_id for r in rows})

    episodes = {}

    for r in rows:
        key = (r.internal_id, r.vignette, r.vignette_order)

        if key not in episodes:
            episodes[key] = {
                "internal_id": r.internal_id,
                "respondent_id": r.respondent_id,
                "block": int(r.block.replace("Set_", "")),
                "attention_order": r.attention_order,
                "attention_completed": r.attention_completed,
                "attention_correct": r.attention_correct,
                "vignette": r.vignette,
                "vignette_order": r.vignette_order,
                "latency_ms": r.latency_ms,
                "click_count": r.click_count,
            }

        episodes[key][r.question_id] = r.response

    header = [
        "internal_id",
        "respondent_id",
        "block",
        "attention_order",
        "attention_completed",
        "attention_correct",
        "vignette",
        "vignette_order",
        "latency_ms",
        "click_count",
        *item_ids,
    ]

    output = StringIO()
    writer = csv.writer(output)
    writer.writerow(header)

    for key in sorted(episodes.keys(), key=lambda x: (x[0], x[2])):
        row = episodes[key]
        writer.writerow([row.get(col, None) for col in header])

    output.seek(0)

    return StreamingResponse(
        output,
        media_type="text/csv",
        headers={
            "Content-Disposition": "attachment; filename=vignette_data.csv"
        },
    )
