"""Public reference data for clients."""

from fastapi import APIRouter

from app.domain.qualifications import taxonomy_as_dict

router = APIRouter(prefix="/meta", tags=["meta"])


@router.get("/qualifications")
async def get_qualification_taxonomy() -> dict[str, object]:
    """Level -> degree -> branch codes for the profile pickers (the app ships a
    generated copy for offline use; this is the authoritative version)."""
    return taxonomy_as_dict()
