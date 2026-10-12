from datetime import datetime

from pydantic import AnyHttpUrl, BaseModel, Field, field_validator


class ApkAsset(BaseModel):
    url: AnyHttpUrl
    sha256: str = Field(pattern=r"^[0-9a-f]{64}$")
    size_bytes: int | None = Field(None, ge=1)

    @field_validator("url")
    @classmethod
    def _https_only(cls, v: AnyHttpUrl) -> AnyHttpUrl:
        if v.scheme != "https":
            raise ValueError("APK URLs must be https")
        return v


class ReleaseManifest(BaseModel):
    """Written by CI (``latest.json`` attached to each GitHub Release) and synced
    to the server by scripts/sync_release_manifest.sh."""

    version_code: int = Field(ge=1)
    version_name: str
    min_supported_version_code: int = Field(1, ge=1)
    release_notes: str = ""
    published_at: datetime | None = None
    # "universal" plus optional per-ABI split APKs ("arm64-v8a", "armeabi-v7a", "x86_64").
    apks: dict[str, ApkAsset]

    @field_validator("apks")
    @classmethod
    def _needs_universal(cls, v: dict[str, ApkAsset]) -> dict[str, ApkAsset]:
        if "universal" not in v:
            raise ValueError("apks must include a 'universal' entry")
        return v


class AppVersionOut(BaseModel):
    latest_version_code: int
    version_name: str
    min_supported_version_code: int
    release_notes: str
    published_at: datetime | None
    apk_url: str
    sha256: str
    size_bytes: int | None
    abi: str = Field(description="Which APK was chosen: an ABI name or 'universal'")
    update_available: bool | None = Field(None, description="Set when current_version_code is sent")
    mandatory: bool | None = None
