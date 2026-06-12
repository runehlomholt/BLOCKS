from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app import models
from app.services.allocation import choose_set, expire_stale_allocations
from app.services.responses import save_submission, validate_submission


class Design:
    sets = {
        "Set_1": [{"id": "1"}],
        "Set_2": [{"id": "2"}],
    }


BATTERIES = [
    {
        "name": "test",
        "heading": "Test",
        "scale": {"values": [1, 2, 3], "labels": ["Low", "Mid", "High"]},
        "questions": [{"question_id": "q1", "question_text": "Question"}],
    }
]


@pytest.fixture()
def db():
    engine = create_engine("sqlite:///:memory:")
    models.Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    session.add(models.AllocationLock(id=1))
    session.commit()
    try:
        yield session
    finally:
        session.close()


def make_respondent(db, token="token", condition_set="Set_1"):
    now = datetime.now(timezone.utc)
    respondent = models.Respondent(
        respondent_uuid=f"uuid-{token}",
        external_id=token,
        condition_set=condition_set,
        status="allocated",
        allocated_at=now,
        last_activity_at=now,
    )
    db.add(respondent)
    db.flush()
    db.add(
        models.AssignedVignette(
            respondent_id=respondent.id, vignette_id="1", display_order=1
        )
    )
    db.commit()
    return respondent


def test_allocation_ignores_abandoned_records(db, monkeypatch):
    abandoned = make_respondent(db)
    abandoned.status = "abandoned"
    db.commit()

    monkeypatch.setattr("app.services.allocation.random.choice", lambda values: values[0])
    assert choose_set(db, Design()) == "Set_1"


def test_stale_allocation_becomes_abandoned(db):
    respondent = make_respondent(db)
    respondent.last_activity_at = datetime.now(timezone.utc) - timedelta(hours=2)
    db.commit()
    assert expire_stale_allocations(db) == 1
    db.commit()
    assert respondent.status == "abandoned"


def test_submission_uses_server_assignment_and_is_idempotent(db):
    respondent = make_respondent(db)
    form = {"battery_q1": "2"}
    assigned, answers = validate_submission(db, respondent, 1, form, BATTERIES)
    now = datetime.now(timezone.utc)

    created = save_submission(
        db,
        respondent,
        assigned,
        1,
        answers,
        (now - timedelta(seconds=2)).isoformat(),
        now.isoformat(),
        3,
        1,
        1,
    )
    repeated = save_submission(
        db,
        respondent,
        assigned,
        1,
        answers,
        (now - timedelta(seconds=2)).isoformat(),
        now.isoformat(),
        3,
        1,
        1,
    )

    assert created is True
    assert repeated is False
    assert db.query(models.VignetteResponse).count() == 1
    assert respondent.status == "completed"
    assert respondent.completed_at is not None


def test_submission_rejects_unknown_or_invalid_answers(db):
    respondent = make_respondent(db)
    with pytest.raises(HTTPException):
        validate_submission(db, respondent, 1, {"battery_other": "2"}, BATTERIES)
    with pytest.raises(HTTPException):
        validate_submission(db, respondent, 1, {"battery_q1": "99"}, BATTERIES)


def test_unique_response_constraint_is_database_enforced(db):
    respondent = make_respondent(db)
    now = datetime.now(timezone.utc)
    values = dict(
        respondent_id=respondent.id,
        vignette_id="1",
        vignette_order=1,
        question_id="q1",
        response="1",
        started_at=now,
        ended_at=now,
        server_received_at=now,
        latency_ms=0,
        click_count=1,
        answer_change_count=0,
    )
    db.add(models.VignetteResponse(**values))
    db.commit()
    db.add(models.VignetteResponse(**values))
    with pytest.raises(Exception):
        db.commit()
