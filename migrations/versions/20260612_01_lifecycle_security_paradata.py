"""Add lifecycle, submission integrity, and paradata fields."""

from alembic import op
import sqlalchemy as sa


revision = "20260612_01"
down_revision = None
branch_labels = None
depends_on = None


RESPONDENT_COLUMNS = [
    sa.Column("status", sa.String(), nullable=True),
    sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
    sa.Column("allocated_at", sa.DateTime(timezone=True), nullable=True),
    sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
    sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
    sa.Column("abandoned_at", sa.DateTime(timezone=True), nullable=True),
    sa.Column("last_activity_at", sa.DateTime(timezone=True), nullable=True),
    sa.Column("design_version", sa.String(), nullable=True),
    sa.Column("app_version", sa.String(), nullable=True),
    sa.Column("attention_presented_at", sa.DateTime(timezone=True), nullable=True),
    sa.Column("attention_submitted_at", sa.DateTime(timezone=True), nullable=True),
    sa.Column("attention_latency_ms", sa.Integer(), nullable=True),
]

RESPONSE_COLUMNS = [
    sa.Column("server_received_at", sa.DateTime(timezone=True), nullable=True),
    sa.Column("answer_change_count", sa.Integer(), nullable=True),
]


def _column_names(inspector, table):
    return {column["name"] for column in inspector.get_columns(table)}


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "respondents" not in inspector.get_table_names():
        from app.models import Base

        Base.metadata.create_all(bind=bind)
        return

    respondent_columns = _column_names(inspector, "respondents")
    for column in RESPONDENT_COLUMNS:
        if column.name not in respondent_columns:
            op.add_column("respondents", column)

    response_columns = _column_names(inspector, "vignette_responses")
    for column in RESPONSE_COLUMNS:
        if column.name not in response_columns:
            op.add_column("vignette_responses", column)

    op.execute(
        """
        UPDATE respondents
        SET created_at = COALESCE(created_at, CURRENT_TIMESTAMP),
            allocated_at = COALESCE(allocated_at, created_at, CURRENT_TIMESTAMP),
            last_activity_at = COALESCE(last_activity_at, created_at, CURRENT_TIMESTAMP),
            status = COALESCE(
                status,
                CASE WHEN EXISTS (
                    SELECT 1 FROM vignette_responses vr WHERE vr.respondent_id = respondents.id
                ) THEN 'started' ELSE 'allocated' END
            )
        """
    )
    op.execute(
        """
        UPDATE respondents
        SET status = 'completed', completed_at = COALESCE(completed_at, CURRENT_TIMESTAMP)
        WHERE EXISTS (SELECT 1 FROM assigned_vignettes av WHERE av.respondent_id = respondents.id)
          AND (SELECT COUNT(DISTINCT vr.vignette_order) FROM vignette_responses vr
               WHERE vr.respondent_id = respondents.id)
              =
              (SELECT COUNT(*) FROM assigned_vignettes av
               WHERE av.respondent_id = respondents.id)
        """
    )
    op.execute(
        """
        UPDATE vignette_responses
        SET server_received_at = COALESCE(server_received_at, ended_at, CURRENT_TIMESTAMP),
            answer_change_count = COALESCE(answer_change_count, 0)
        """
    )
    op.execute(
        """
        DELETE FROM vignette_responses
        WHERE id NOT IN (
            SELECT MIN(id)
            FROM vignette_responses
            GROUP BY respondent_id, vignette_order, question_id
        )
        """
    )

    inspector = sa.inspect(bind)
    unique_names = {
        constraint.get("name")
        for constraint in inspector.get_unique_constraints("vignette_responses")
    }
    if "uq_response_respondent_order_question" not in unique_names:
        with op.batch_alter_table("vignette_responses") as batch:
            batch.create_unique_constraint(
                "uq_response_respondent_order_question",
                ["respondent_id", "vignette_order", "question_id"],
            )

    with op.batch_alter_table("respondents") as batch:
        batch.alter_column("status", existing_type=sa.String(), nullable=False)
        batch.alter_column(
            "created_at",
            existing_type=sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        )
        batch.alter_column("allocated_at", existing_type=sa.DateTime(timezone=True), nullable=False)
        batch.alter_column("last_activity_at", existing_type=sa.DateTime(timezone=True), nullable=False)
    with op.batch_alter_table("vignette_responses") as batch:
        batch.alter_column(
            "server_received_at", existing_type=sa.DateTime(timezone=True), nullable=False
        )
        batch.alter_column("answer_change_count", existing_type=sa.Integer(), nullable=False)

    inspector = sa.inspect(bind)
    indexes = {index["name"] for index in inspector.get_indexes("respondents")}
    if "ix_respondents_status" not in indexes:
        op.create_index("ix_respondents_status", "respondents", ["status"])


def downgrade():
    raise RuntimeError("This data-preserving migration is not automatically reversible")
