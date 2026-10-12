"""Credential Vault encryption (Fernet = AES-128-CBC + HMAC-SHA256).

Generate a key with:
    python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
"""

from functools import lru_cache

from cryptography.fernet import Fernet

from app.core.config import get_settings


@lru_cache
def _fernet() -> Fernet:
    return Fernet(get_settings().vault_key.get_secret_value().encode())


def encrypt_secret(plain: str) -> bytes:
    return _fernet().encrypt(plain.encode("utf-8"))


def decrypt_secret(token: bytes) -> str:
    return _fernet().decrypt(token).decode("utf-8")
