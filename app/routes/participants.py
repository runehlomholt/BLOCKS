import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import func
from sqlalchemy.orm import Session

from .. import models, state
from ..config import settings
from ..dependencies import get_db
from ..services.allocation import get_or_create_respondent
from ..services.progress import next_order
from ..services.responses import save_submission, validate_submission


router = APIRouter()
templates = Jinja2Templates(directory="app/templates")


def _find_vignette(respondent, assigned):
    return next(
        (
            vignette
            for vignette in state.design.sets[respondent.condition_set]
            if str(vignette["id"]) == str(assigned.vignette_id)
        ),
        None,
    )


@router.get("/", response_class=HTMLResponse)
def start(request: Request, db: Session = Depends(get_db)):
    token = request.query_params.get("token")
    if settings.token_required and not token:
        return templates.TemplateResponse(
            "token_error.html", {"request": request}, status_code=400
        )
    token = token or f"debug_{uuid.uuid4()}"
    respondent = get_or_create_respondent(
        db, token, request.headers.get("user-agent"), state.design
    )
    order = next_order(db, respondent)
    return RedirectResponse(
        url=f"/vignette/{respondent.respondent_uuid}?order={order}", status_code=302
    )


@router.get("/vignette/{respondent_uuid}", response_class=HTMLResponse)
def show_vignette(
    request: Request,
    respondent_uuid: str,
    order: int = 1,
    db: Session = Depends(get_db),
):
    respondent = db.query(models.Respondent).filter(
        models.Respondent.respondent_uuid == respondent_uuid
    ).first()
    if respondent is None:
        raise HTTPException(status_code=404, detail="Respondent not found")

    expected_order = next_order(db, respondent)
    if order != expected_order:
        return RedirectResponse(
            url=f"/vignette/{respondent_uuid}?order={expected_order}", status_code=302
        )

    if (
        respondent.attention_order is not None
        and not respondent.attention_completed
        and order == respondent.attention_order + 1
    ):
        return RedirectResponse(
            url=f"/attention/{respondent_uuid}?order={order}", status_code=302
        )

    assigned = db.query(models.AssignedVignette).filter(
        models.AssignedVignette.respondent_id == respondent.id,
        models.AssignedVignette.display_order == order,
    ).first()
    if assigned is None:
        return templates.TemplateResponse("finished.html", {"request": request})

    vignette = _find_vignette(respondent, assigned)
    if vignette is None:
        raise HTTPException(status_code=500, detail="Vignette not found in design")

    total = db.query(func.count(models.AssignedVignette.id)).filter(
        models.AssignedVignette.respondent_id == respondent.id
    ).scalar() or 1
    vignette = dict(vignette)
    vignette["progress_percent"] = max(0, min(round(order / total * 100), 100))

    respondent.last_activity_at = datetime.now(timezone.utc)
    db.commit()
    return templates.TemplateResponse(
        "vignette.html",
        {
            "request": request,
            "respondent_uuid": respondent_uuid,
            "vignette": vignette,
            "order": order,
            "start_timestamp": datetime.now(timezone.utc).isoformat(),
            "batteries": state.question_batteries,
        },
    )


@router.post("/vignette/{respondent_uuid}")
async def submit_vignette(
    request: Request,
    respondent_uuid: str,
    order: int = Form(...),
    started_at: str = Form(...),
    ended_at: str = Form(...),
    click_count: int = Form(...),
    answer_change_count: int = Form(0),
    db: Session = Depends(get_db),
):
    respondent = db.query(models.Respondent).filter(
        models.Respondent.respondent_uuid == respondent_uuid
    ).first()
    if respondent is None:
        raise HTTPException(status_code=404, detail="Respondent not found")

    form = await request.form()
    assigned, answers = validate_submission(
        db, respondent, order, form, state.question_batteries
    )
    total = db.query(func.count(models.AssignedVignette.id)).filter(
        models.AssignedVignette.respondent_id == respondent.id
    ).scalar() or 0
    save_submission(
        db,
        respondent,
        assigned,
        order,
        answers,
        started_at,
        ended_at,
        click_count,
        answer_change_count,
        total,
    )
    return RedirectResponse(
        url=f"/vignette/{respondent_uuid}?order={order + 1}", status_code=303
    )
