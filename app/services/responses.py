from datetime import datetime, timedelta, timezone

from fastapi import HTTPException

from .. import models


def utcnow():
    return datetime.now(timezone.utc)


def parse_client_timestamp(value, field_name):
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail=f"Invalid {field_name}")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def question_schema(batteries):
    result = {}
    for battery in batteries:
        allowed = {str(value) for value in battery["scale"]["values"]}
        for question in battery["questions"]:
            question_id = str(question["question_id"])
            if question_id in result:
                raise RuntimeError(f"Duplicate question_id: {question_id}")
            result[question_id] = allowed
    return result


def validate_submission(db, respondent, order, form, batteries):
    if (
        respondent.attention_order is not None
        and not respondent.attention_completed
        and order == respondent.attention_order + 1
    ):
        raise HTTPException(status_code=409, detail="Attention check is incomplete")
    assigned = db.query(models.AssignedVignette).filter(
        models.AssignedVignette.respondent_id == respondent.id,
        models.AssignedVignette.display_order == order,
    ).first()
    if assigned is None:
        raise HTTPException(status_code=400, detail="Vignette is not assigned")

    if order > 1:
        previous_exists = db.query(models.VignetteResponse.id).filter(
            models.VignetteResponse.respondent_id == respondent.id,
            models.VignetteResponse.vignette_order == order - 1,
        ).first()
        if previous_exists is None:
            raise HTTPException(status_code=409, detail="Earlier vignette is incomplete")

    schema = question_schema(batteries)
    answers = {
        key[len("battery_") :]: str(value)
        for key, value in form.items()
        if key.startswith("battery_")
    }
    if set(answers) != set(schema):
        raise HTTPException(status_code=400, detail="Incomplete or unknown questions")
    for question_id, value in answers.items():
        if value not in schema[question_id]:
            raise HTTPException(status_code=400, detail="Invalid response value")
    return assigned, answers


def save_submission(
    db,
    respondent,
    assigned,
    order,
    answers,
    client_started_at,
    client_ended_at,
    click_count,
    answer_change_count,
    total_vignettes,
):
    existing = db.query(models.VignetteResponse).filter(
        models.VignetteResponse.respondent_id == respondent.id,
        models.VignetteResponse.vignette_order == order,
    ).all()
    if existing:
        if {row.question_id for row in existing} == set(answers):
            return False
        raise HTTPException(status_code=409, detail="Partial submission already exists")

    started = parse_client_timestamp(client_started_at, "start time")
    ended = parse_client_timestamp(client_ended_at, "end time")
    latency_ms = int((ended - started).total_seconds() * 1000)
    if latency_ms < 0 or latency_ms > 24 * 60 * 60 * 1000:
        raise HTTPException(status_code=400, detail="Implausible response time")
    if click_count < 0 or answer_change_count < 0:
        raise HTTPException(status_code=400, detail="Invalid interaction count")

    received = utcnow()
    if ended > received + timedelta(minutes=5) or started < received - timedelta(days=1):
        raise HTTPException(status_code=400, detail="Implausible client timestamp")
    for question_id, value in answers.items():
        db.add(
            models.VignetteResponse(
                respondent_id=respondent.id,
                vignette_id=assigned.vignette_id,
                vignette_order=order,
                question_id=question_id,
                response=value,
                started_at=started,
                ended_at=ended,
                server_received_at=received,
                latency_ms=latency_ms,
                click_count=click_count,
                answer_change_count=answer_change_count,
            )
        )

    if respondent.status in {"allocated", "abandoned"}:
        respondent.status = "started"
        respondent.started_at = respondent.started_at or received
    if order == total_vignettes:
        respondent.status = "completed"
        respondent.completed_at = received
    respondent.last_activity_at = received
    db.commit()
    return True
