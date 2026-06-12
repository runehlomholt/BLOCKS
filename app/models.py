from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import relationship

from .database import Base


class AllocationLock(Base):
    __tablename__ = "allocation_lock"

    id = Column(Integer, primary_key=True)


class Respondent(Base):
    __tablename__ = "respondents"

    id = Column(Integer, primary_key=True, index=True)
    respondent_uuid = Column(String, unique=True, index=True, nullable=False)
    external_id = Column(String, unique=True, index=True, nullable=False)
    condition_set = Column(String, index=True, nullable=False)
    user_agent = Column(String, nullable=True)

    status = Column(String, nullable=False, index=True, default="allocated")
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    allocated_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    started_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    abandoned_at = Column(DateTime(timezone=True), nullable=True)
    last_activity_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    design_version = Column(String, nullable=True)
    app_version = Column(String, nullable=True)

    attention_order = Column(Integer, nullable=True)
    attention_expected = Column(Integer, nullable=True)
    attention_completed = Column(Boolean, default=False, nullable=False)
    attention_correct = Column(Boolean, nullable=True)
    attention_presented_at = Column(DateTime(timezone=True), nullable=True)
    attention_submitted_at = Column(DateTime(timezone=True), nullable=True)
    attention_latency_ms = Column(Integer, nullable=True)

    assigned_vignettes = relationship(
        "AssignedVignette", back_populates="respondent", cascade="all, delete-orphan"
    )
    responses = relationship(
        "VignetteResponse", back_populates="respondent", cascade="all, delete-orphan"
    )


class AssignedVignette(Base):
    __tablename__ = "assigned_vignettes"

    id = Column(Integer, primary_key=True, index=True)
    respondent_id = Column(
        Integer, ForeignKey("respondents.id", ondelete="CASCADE"), index=True, nullable=False
    )
    vignette_id = Column(String, index=True, nullable=False)
    display_order = Column(Integer, index=True, nullable=False)

    respondent = relationship("Respondent", back_populates="assigned_vignettes")


Index("ix_assigned_unique", AssignedVignette.respondent_id, AssignedVignette.display_order, unique=True)


class VignetteResponse(Base):
    __tablename__ = "vignette_responses"
    __table_args__ = (
        UniqueConstraint(
            "respondent_id",
            "vignette_order",
            "question_id",
            name="uq_response_respondent_order_question",
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    respondent_id = Column(
        Integer, ForeignKey("respondents.id", ondelete="CASCADE"), index=True, nullable=False
    )
    vignette_id = Column(String, index=True, nullable=False)
    vignette_order = Column(Integer, index=True, nullable=False)
    question_id = Column(String, index=True, nullable=False)
    response = Column(String, nullable=False)

    started_at = Column(DateTime(timezone=True), nullable=False)
    ended_at = Column(DateTime(timezone=True), nullable=False)
    server_received_at = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    latency_ms = Column(Integer, nullable=False)
    click_count = Column(Integer, nullable=False)
    answer_change_count = Column(Integer, nullable=False, default=0)

    respondent = relationship("Respondent", back_populates="responses")
