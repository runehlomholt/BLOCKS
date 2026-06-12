import csv
from io import StringIO

from .. import models


META_COLUMNS = [
    "internal_id",
    "respondent_id",
    "block",
    "status",
    "allocated_at",
    "participant_started_at",
    "participant_completed_at",
    "participant_abandoned_at",
    "design_version",
    "app_version",
    "attention_order",
    "attention_completed",
    "attention_correct",
    "attention_presented_at",
    "attention_submitted_at",
    "attention_latency_ms",
    "vignette",
    "vignette_order",
    "client_started_at",
    "client_ended_at",
    "server_received_at",
    "latency_ms",
    "click_count",
    "answer_change_count",
]


def build_export(db):
    rows = (
        db.query(
            models.Respondent.respondent_uuid.label("internal_id"),
            models.Respondent.external_id.label("respondent_id"),
            models.Respondent.condition_set.label("block"),
            models.Respondent.status,
            models.Respondent.allocated_at,
            models.Respondent.started_at.label("participant_started_at"),
            models.Respondent.completed_at.label("participant_completed_at"),
            models.Respondent.abandoned_at.label("participant_abandoned_at"),
            models.Respondent.design_version,
            models.Respondent.app_version,
            models.Respondent.attention_order,
            models.Respondent.attention_completed,
            models.Respondent.attention_correct,
            models.Respondent.attention_presented_at,
            models.Respondent.attention_submitted_at,
            models.Respondent.attention_latency_ms,
            models.VignetteResponse.vignette_id.label("vignette"),
            models.VignetteResponse.vignette_order,
            models.VignetteResponse.started_at.label("client_started_at"),
            models.VignetteResponse.ended_at.label("client_ended_at"),
            models.VignetteResponse.server_received_at,
            models.VignetteResponse.latency_ms,
            models.VignetteResponse.click_count,
            models.VignetteResponse.answer_change_count,
            models.VignetteResponse.question_id,
            models.VignetteResponse.response,
        )
        .join(models.VignetteResponse)
        .order_by(models.Respondent.respondent_uuid, models.VignetteResponse.vignette_order)
        .all()
    )
    item_ids = sorted({row.question_id for row in rows})
    episodes = {}
    for row in rows:
        key = (row.internal_id, row.vignette, row.vignette_order)
        if key not in episodes:
            episodes[key] = {column: getattr(row, column) for column in META_COLUMNS}
            block = episodes[key]["block"]
            if isinstance(block, str) and block.startswith("Set_"):
                episodes[key]["block"] = int(block.replace("Set_", ""))
        episodes[key][row.question_id] = row.response

    output = StringIO()
    writer = csv.writer(output)
    header = META_COLUMNS + item_ids
    writer.writerow(header)
    for key in sorted(episodes, key=lambda value: (value[0], value[2])):
        writer.writerow([episodes[key].get(column) for column in header])
    output.seek(0)
    return output
