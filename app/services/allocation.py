import random
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError

from .. import models
from ..config import settings


ACTIVE_STATUSES = ("allocated", "started", "completed")


def utcnow():
    return datetime.now(timezone.utc)


def expire_stale_allocations(db):
    cutoff = utcnow() - timedelta(minutes=settings.allocation_expiry_minutes)
    return (
        db.query(models.Respondent)
        .filter(
            models.Respondent.status == "allocated",
            models.Respondent.last_activity_at < cutoff,
        )
        .update(
            {
                models.Respondent.status: "abandoned",
                models.Respondent.abandoned_at: utcnow(),
                models.Respondent.last_activity_at: utcnow(),
            },
            synchronize_session=False,
        )
    )


def choose_set(db, design):
    if not design or not design.sets:
        raise HTTPException(status_code=500, detail="Experiment design is unavailable")

    db.query(models.AllocationLock).filter(
        models.AllocationLock.id == 1
    ).with_for_update().one()
    expire_stale_allocations(db)

    all_sets = list(design.sets)
    rows = (
        db.query(models.Respondent.condition_set, func.count(models.Respondent.id))
        .filter(models.Respondent.status.in_(ACTIVE_STATUSES))
        .group_by(models.Respondent.condition_set)
        .all()
    )
    counts = {set_name: 0 for set_name in all_sets}
    for set_name, count in rows:
        if set_name in counts:
            counts[set_name] = int(count)

    minimum = min(counts.values())
    return random.choice([name for name, count in counts.items() if count == minimum])


def ensure_attention_plan(respondent, num_vignettes):
    if respondent.attention_order is not None:
        return
    if num_vignettes < 3:
        respondent.attention_completed = True
        return
    respondent.attention_order = random.randint(2, num_vignettes - 1)


def _create_respondent(db, token, user_agent, design):
    now = utcnow()
    chosen_set = choose_set(db, design)
    respondent = models.Respondent(
        respondent_uuid=str(uuid.uuid4()),
        external_id=token,
        condition_set=chosen_set,
        user_agent=user_agent,
        status="allocated",
        allocated_at=now,
        last_activity_at=now,
        design_version=settings.design_version,
        app_version=settings.app_version,
    )
    db.add(respondent)
    db.flush()

    vignettes = list(design.sets[chosen_set])
    random.shuffle(vignettes)
    for order, vignette in enumerate(vignettes, start=1):
        db.add(
            models.AssignedVignette(
                respondent_id=respondent.id,
                vignette_id=str(vignette["id"]),
                display_order=order,
            )
        )
    ensure_attention_plan(respondent, len(vignettes))
    return respondent


def get_or_create_respondent(db, token, user_agent, design):
    respondent = db.query(models.Respondent).filter(
        models.Respondent.external_id == token
    ).first()
    if respondent is not None:
        if respondent.status == "abandoned":
            respondent.status = "allocated"
            respondent.abandoned_at = None
            respondent.last_activity_at = utcnow()
            db.commit()
        return respondent

    try:
        respondent = _create_respondent(db, token, user_agent, design)
        db.commit()
        db.refresh(respondent)
        return respondent
    except IntegrityError:
        db.rollback()
        respondent = db.query(models.Respondent).filter(
            models.Respondent.external_id == token
        ).first()
        if respondent is None:
            raise
        return respondent
