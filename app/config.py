import os
from dataclasses import dataclass
from pathlib import Path


def _as_bool(name, default=False):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    token_required: bool
    export_key: str
    allocation_expiry_minutes: int
    vignette_content_path: Path
    allow_unbalanced_sets: bool
    app_version: str
    design_version: str


def load_settings():
    return Settings(
        token_required=_as_bool("TOKEN_REQUIRED", True),
        export_key=os.environ.get("EXPORT_KEY", ""),
        allocation_expiry_minutes=int(
            os.environ.get("ALLOCATION_EXPIRY_MINUTES", "60")
        ),
        vignette_content_path=Path(
            os.environ.get("VIGNETTE_CONTENT_PATH", "vignette_content")
        ),
        allow_unbalanced_sets=_as_bool("ALLOW_UNBALANCED_SETS", False),
        app_version=os.environ.get("APP_VERSION", "development"),
        design_version=os.environ.get("DESIGN_VERSION", "unspecified"),
    )


settings = load_settings()
