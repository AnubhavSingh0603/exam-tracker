# Multi-arch: builds natively on OCI Ampere A1 (linux/arm64) and x86_64.
# Every Python dependency ships manylinux aarch64 wheels (asyncpg, lxml, cryptography,
# grpcio for firebase-admin, PyMuPDF), so no compiler toolchain is needed on the VM.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /srv
RUN useradd --create-home --uid 10001 app

COPY requirements.txt requirements-playwright.txt ./
RUN pip install -r requirements.txt

# --- Optional JS rendering (off by default; none of the seed sources need it) --------------
#   docker compose build --build-arg WITH_CHROMIUM=1      then set PLAYWRIGHT_ENABLED=true
#
# Uses Debian's own `chromium` package instead of `playwright install`: Playwright's bundled
# browser builds don't officially support Debian 13 (this base image) on arm64, while the
# distro package is native to both arm64 and amd64 and receives Debian security updates.
# `chromium-driver` is NOT installed: it's for Selenium, and Playwright drives Chromium over CDP.
# Fonts: Noto covers Devanagari, so Hindi pages render instead of showing boxes.
ARG WITH_CHROMIUM=0
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/chromium \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
RUN if [ "$WITH_CHROMIUM" = "1" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends chromium fonts-noto-core fonts-liberation && \
      rm -rf /var/lib/apt/lists/* && \
      pip install -r requirements-playwright.txt && \
      chromium --version; \
    fi

COPY app ./app
RUN mkdir -p /data/notifications && chown -R app:app /data

USER app
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz').status==200 else 1)"

# One async worker is plenty for a personal backend and avoids races in
# AUTO_CREATE_SCHEMA. Raise --workers after moving to Alembic.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips=*"]
