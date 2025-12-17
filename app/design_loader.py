from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

VIGNETTE_FILE_RE = re.compile(r"^vignette_(?P<id>.+)\.txt$", re.IGNORECASE)

DESIGN_DEFAULTS = {
    "question_id": "rating",
    "question_text": "Please provide your rating.",
    "scale_min": 1,
    "scale_max": 7,
    "scale_min_label": "Low",
    "scale_max_label": "High",
}

@dataclass(frozen=True)
class Design:
    sets: dict[str, list[dict[str, Any]]]

def _read_optional_config(set_dir: Path) -> dict[str, Any]:
    cfg_path = set_dir / "config.json"
    if not cfg_path.exists():
        return {}
    return json.loads(cfg_path.read_text(encoding="utf-8"))

def load_design(base_path: str | Path) -> Design:
    base = Path(base_path)
    if not base.exists():
        raise FileNotFoundError(f"Design folder not found: {base}")

    sets: dict[str, list[dict[str, Any]]] = {}

    for set_dir in sorted([p for p in base.iterdir() if p.is_dir()]):
        set_name = set_dir.name
        cfg = {**DESIGN_DEFAULTS, **_read_optional_config(set_dir)}

        vignettes: list[dict[str, Any]] = []
        for f in sorted(set_dir.iterdir()):
            if not f.is_file():
                continue
            m = VIGNETTE_FILE_RE.match(f.name)
            if not m:
                continue

            vignette_id = m.group("id")
            text = f.read_text(encoding="utf-8").strip()

            vignettes.append(
                {
                    "id": vignette_id,
                    "text": text,
                    "question_id": cfg["question_id"],
                    "question_text": cfg["question_text"],
                    "scale_min": int(cfg["scale_min"]),
                    "scale_max": int(cfg["scale_max"]),
                    "scale_min_label": cfg["scale_min_label"],
                    "scale_max_label": cfg["scale_max_label"],
                }
            )

        sets[set_name] = vignettes

    if not sets:
        raise ValueError(f"No vignette sets found under: {base}")

    return Design(sets=sets)

def validate_balanced_sets(design: Design) -> None:
    lengths = {k: len(v) for k, v in design.sets.items()}
    unique_lengths = set(lengths.values())
    if len(unique_lengths) != 1:
        raise ValueError(f"Inconsistent vignette counts across sets: {lengths}")

def get_design_path() -> Path:
    return Path(os.environ.get("VIGNETTE_CONTENT_PATH", "vignette_content"))
