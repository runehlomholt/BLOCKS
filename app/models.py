from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Boolean, Index
from sqlalchemy.orm import relationship
from .database import Base


class AllocationLock(Base):
    """
    Single-row table used for concurrency-safe quota assignment.
    We lock the row with SELECT ... FOR UPDATE to ensure only one assignment
    happens at a time (Pattern A).
    """
    __tablename__ = "allocation_lock"

    id = Column(Integer, primary_key=True)  # we'll use id=1


class Respondent(Base):
    __tablename__ = "respondents"

    id = Column(Integer, primary_key=True, index=True)
    respondent_uuid = Column(String, unique=True, index=True, nullable=False)
    external_id = Column(String, unique=True, index=True, nullable=False)
    condition_set = Column(String, index=True, nullable=False)
    user_agent = Column(String, nullable=True)

    # Attention check fields
    attention_order = Column(Integer, nullable=True)
    attention_expected = Column(Integer, nullable=True)
    attention_completed = Column(Boolean, default=False)
    attention_correct = Column(Boolean, nullable=True)

    assigned_vignettes = relationship("AssignedVignette", back_populates="respondent")
    responses = relationship("VignetteResponse", back_populates="respondent")


class AssignedVignette(Base):
    __tablename__ = "assigned_vignettes"

    id = Column(Integer, primary_key=True, index=True)
    respondent_id = Column(Integer, ForeignKey("respondents.id"), index=True, nullable=False)
    vignette_id = Column(String, index=True, nullable=False)
    display_order = Column(Integer, index=True, nullable=False)

    respondent = relationship("Respondent", back_populates="assigned_vignettes")


Index(
    "ix_assigned_unique",
    AssignedVignette.respondent_id,
    AssignedVignette.display_order,
    unique=True,
)


class VignetteResponse(Base):
    __tablename__ = "vignette_responses"

    id = Column(Integer, primary_key=True, index=True)
    respondent_id = Column(Integer, ForeignKey("respondents.id"), index=True, nullable=False)

    vignette_id = Column(String, index=True, nullable=False)
    vignette_order = Column(Integer, index=True, nullable=False)

    question_id = Column(String, index=True, nullable=False)
    response = Column(String, nullable=False)

    started_at = Column(DateTime(timezone=True), nullable=False)
    ended_at = Column(DateTime(timezone=True), nullable=False)
    latency_ms = Column(Integer, nullable=False)
    click_count = Column(Integer, nullable=False)

    respondent = relationship("Respondent", back_populates="responses")
