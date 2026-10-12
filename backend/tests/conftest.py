import os

from cryptography.fernet import Fernet

# Settings require secrets; give tests harmless values before anything imports config.
os.environ.setdefault("API_KEY", "test-key")
os.environ.setdefault("VAULT_KEY", Fernet.generate_key().decode())
os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("JWT_SECRET", "test-secret-" + "x" * 40)
os.environ.setdefault("GOOGLE_CLIENT_IDS", '["test-client.apps.googleusercontent.com"]')
