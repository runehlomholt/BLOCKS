import hmac

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from ..config import settings
from ..dependencies import get_db
from ..services.export import build_export


router = APIRouter()


def require_export_key(
    export_key: str = Query("", alias="key"),
    authorization: str = Header(""),
):
    if not settings.export_key:
        raise HTTPException(status_code=503, detail="Export is not configured")
    supplied = export_key
    if authorization.startswith("Bearer "):
        supplied = authorization[len("Bearer ") :]
    if not supplied or not hmac.compare_digest(supplied, settings.export_key):
        raise HTTPException(status_code=401, detail="Unauthorized")


@router.get("/export", dependencies=[Depends(require_export_key)])
def export_csv(db: Session = Depends(get_db)):
    return StreamingResponse(
        build_export(db),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=vignette_data.csv"},
    )
