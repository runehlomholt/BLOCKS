import random
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from .. import models
from ..dependencies import get_db


router = APIRouter()
templates = Jinja2Templates(directory="app/templates")


def math_problem(respondent_uuid, order):
    rng = random.Random(f"{respondent_uuid}:{order}:attention")
    a = rng.randint(2, 9)
    b = rng.randint(2, 9)
    return a, b, a + b


def _as_utc(value):
    if value is None or value.tzinfo is not None:
        return value
    return value.replace(tzinfo=timezone.utc)


@router.get("/attention/{respondent_uuid}", response_class=HTMLResponse)
def attention_check(
    request: Request,
    respondent_uuid: str,
    order: int,
    db: Session = Depends(get_db),
):
    respondent = db.query(models.Respondent).filter(
        models.Respondent.respondent_uuid == respondent_uuid
    ).first()
    if respondent is None:
        raise HTTPException(status_code=404, detail="Respondent not found")
    if respondent.attention_order is None or order != respondent.attention_order + 1:
        raise HTTPException(status_code=409, detail="Attention check is not due")
    if respondent.attention_completed:
        return RedirectResponse(
            url=f"/vignette/{respondent_uuid}?order={order}", status_code=302
        )

    a, b, expected = math_problem(respondent_uuid, order)
    now = datetime.now(timezone.utc)
    if respondent.attention_presented_at is None:
        respondent.attention_presented_at = now
    respondent.attention_expected = expected
    respondent.last_activity_at = now
    db.commit()
    return templates.TemplateResponse(
        "attention_check.html",
        {
            "request": request,
            "respondent_uuid": respondent_uuid,
            "order": order,
            "a": a,
            "b": b,
        },
    )


@router.post("/attention/{respondent_uuid}")
def submit_attention_check(
    respondent_uuid: str,
    order: int = Form(...),
    answer: int = Form(...),
    db: Session = Depends(get_db),
):
    respondent = db.query(models.Respondent).filter(
        models.Respondent.respondent_uuid == respondent_uuid
    ).first()
    if respondent is None:
        raise HTTPException(status_code=404, detail="Respondent not found")
    if respondent.attention_order is None or order != respondent.attention_order + 1:
        raise HTTPException(status_code=409, detail="Attention check is not due")
    if respondent.attention_completed:
        return RedirectResponse(
            url=f"/vignette/{respondent_uuid}?order={order}", status_code=303
        )

    _, _, expected = math_problem(respondent_uuid, order)
    submitted = datetime.now(timezone.utc)
    respondent.attention_expected = expected
    respondent.attention_completed = True
    respondent.attention_correct = answer == expected
    respondent.attention_submitted_at = submitted
    if respondent.attention_presented_at is not None:
        respondent.attention_latency_ms = max(
            0,
            int(
                (submitted - _as_utc(respondent.attention_presented_at)).total_seconds()
                * 1000
            ),
        )
    respondent.last_activity_at = submitted
    db.commit()
    return RedirectResponse(
        url=f"/vignette/{respondent_uuid}?order={order}", status_code=303
    )
