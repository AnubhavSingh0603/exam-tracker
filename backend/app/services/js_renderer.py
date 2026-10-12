"""Optional Playwright fallback for JavaScript-rendered pages.

Off by default (PLAYWRIGHT_ENABLED=false): Chromium costs ~300 MB RAM per page,
which matters on a 1 GB micro VM. Build the image with WITH_CHROMIUM=1 on an
Ampere A1 shape to enable it. Uses the distro Chromium at
PLAYWRIGHT_CHROMIUM_EXECUTABLE (/usr/bin/chromium) when set. Every sub-request
the page makes passes the same SSRF guard as plain fetches.
"""

from __future__ import annotations

import logging
import os

from app.services.http_fetcher import BlockedURLError, FetchError, assert_public_url

log = logging.getLogger(__name__)

_SKIP_RESOURCES = {"image", "media", "font", "stylesheet"}


async def render_page(url: str, *, user_agent: str, timeout_ms: int = 30_000) -> str:
    try:
        from playwright.async_api import Route, async_playwright
    except ImportError as exc:
        raise FetchError("Playwright is not installed in this image") from exc

    await assert_public_url(url)

    async def guard(route: Route) -> None:
        req = route.request
        if req.resource_type in _SKIP_RESOURCES:
            await route.abort()
            return
        try:
            await assert_public_url(req.url)
        except FetchError:
            await route.abort()
            return
        await route.continue_()

    async with async_playwright() as pw:
        executable = os.environ.get("PLAYWRIGHT_CHROMIUM_EXECUTABLE") or None
        if executable and not os.path.exists(executable):
            executable = None  # fall back to a Playwright-managed browser, if any
        browser = await pw.chromium.launch(
            executable_path=executable,
            args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"],
        )
        try:
            context = await browser.new_context(user_agent=user_agent, service_workers="block")
            await context.route("**/*", guard)
            page = await context.new_page()
            await page.goto(url, wait_until="networkidle", timeout=timeout_ms)
            return await page.content()
        except BlockedURLError:
            raise
        except Exception as exc:  # noqa: BLE001 - Playwright raises many types
            raise FetchError(f"JS render failed: {exc}") from exc
        finally:
            await browser.close()


def looks_js_rendered(html: str, link_count: int) -> bool:
    """Heuristic: an SPA shell has almost no links and a mount point."""
    if link_count >= 8:
        return False
    markers = ('id="root"', 'id="app"', "__NEXT_DATA__", "ng-version", "data-reactroot", "<noscript>")
    return any(m in html for m in markers)
