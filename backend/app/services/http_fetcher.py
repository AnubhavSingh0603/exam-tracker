"""Polite, SSRF-safe HTTP fetching shared by every crawler.

Safety
  * Only http/https on ports 80/443.
  * Every hop (including each redirect) must resolve exclusively to *public*
    IPs, which blocks localhost, RFC1918, CGNAT, link-local and the OCI/AWS
    metadata service at 169.254.169.254. Redirects are followed manually so
    each target is re-checked.
  * Response bodies are size-capped while streaming.
  Residual risk: DNS rebinding between our check and httpx's own resolution.
  Acceptable for a personal deployment; pin resolved IPs if this ever goes multi-tenant.

Politeness
  * At most one request per host every ``per_host_min_interval_s`` (+ jitter).
  * robots.txt honoured (cached 6 h per origin).
  * 429/503 retried with exponential back-off, honouring short Retry-After.
"""

from __future__ import annotations

import asyncio
import ipaddress
import logging
import random
import socket
import ssl
import time
from collections import defaultdict
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from urllib.robotparser import RobotFileParser

import certifi
import httpx
from tenacity import AsyncRetrying, retry_if_exception_type, stop_after_attempt, wait_exponential_jitter

log = logging.getLogger(__name__)

_ALLOWED_SCHEMES = {"http", "https"}
_ALLOWED_PORTS = {80, 443}
_ROBOTS_TTL_S = 6 * 3600
_EXTRA_INTERMEDIATES = Path(__file__).resolve().parent.parent / "certs" / "extra_intermediates.pem"


@lru_cache(maxsize=4)
def tls_context(
    extra_bundle: str | None = None, *, allow_legacy_renegotiation: bool = True
) -> ssl.SSLContext:
    """certifi roots + intermediates that some .gov.in servers forget to send.
    Full certificate + hostname verification stays on.

    ``allow_legacy_renegotiation``: several state commission servers (e.g. upsssc.gov.in)
    predate RFC 5746 and OpenSSL 3 refuses them outright. Allowing it only weakens
    connections to those already-outdated servers; certificates are still verified.
    """
    ctx = ssl.create_default_context(cafile=certifi.where())
    if _EXTRA_INTERMEDIATES.exists():
        ctx.load_verify_locations(cafile=str(_EXTRA_INTERMEDIATES))
    if extra_bundle:
        ctx.load_verify_locations(cafile=extra_bundle)
    if allow_legacy_renegotiation and hasattr(ssl, "OP_LEGACY_SERVER_CONNECT"):
        ctx.options |= ssl.OP_LEGACY_SERVER_CONNECT
    return ctx


class FetchError(Exception):
    """Permanent failure for this attempt (4xx, too large, not allowed...)."""


class BlockedURLError(FetchError):
    """URL points somewhere we must never connect to."""


class RobotsDisallowedError(FetchError):
    pass


class RetryableFetchError(FetchError):
    """429/5xx/transport error worth retrying."""


@dataclass(frozen=True, slots=True)
class FetchResult:
    url: str  # final URL after redirects
    status: int
    content_type: str
    body: bytes
    encoding: str | None

    @property
    def text(self) -> str:
        return self.body.decode(self.encoding or "utf-8", errors="replace")

    @property
    def is_pdf(self) -> bool:
        return self.body[:5] == b"%PDF-"


# -----------------------------------------------------------------------------
# SSRF guard
# -----------------------------------------------------------------------------


def _ip_is_public(ip: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped is not None:
        ip = ip.ipv4_mapped
    return ip.is_global and not ip.is_multicast


async def assert_public_url(url: str) -> None:
    parts = urlsplit(url)
    if parts.scheme.lower() not in _ALLOWED_SCHEMES:
        raise BlockedURLError(f"Scheme not allowed: {parts.scheme or '(none)'}")
    host = parts.hostname
    if not host:
        raise BlockedURLError("URL has no host")
    if parts.username or parts.password:
        raise BlockedURLError("Credentials in URL are not allowed")
    port = parts.port or (443 if parts.scheme.lower() == "https" else 80)
    if port not in _ALLOWED_PORTS:
        raise BlockedURLError(f"Port {port} not allowed")

    try:
        literal = ipaddress.ip_address(host.strip("[]"))
    except ValueError:
        literal = None
    if literal is not None:
        if not _ip_is_public(literal):
            raise BlockedURLError("Private or reserved address")
        return

    try:
        infos = await asyncio.get_running_loop().getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except socket.gaierror as exc:
        raise FetchError(f"Cannot resolve host {host}") from exc
    addresses = {info[4][0] for info in infos}
    if not addresses:
        raise FetchError(f"Cannot resolve host {host}")
    for addr in addresses:
        if not _ip_is_public(ipaddress.ip_address(addr.split("%", 1)[0])):
            raise BlockedURLError(f"{host} resolves to a private or reserved address")


# -----------------------------------------------------------------------------
# Per-host throttle
# -----------------------------------------------------------------------------


class HostThrottle:
    def __init__(self, min_interval_s: float) -> None:
        self._min = min_interval_s
        self._locks: defaultdict[str, asyncio.Lock] = defaultdict(asyncio.Lock)
        self._last: dict[str, float] = {}

    async def wait(self, host: str) -> None:
        async with self._locks[host]:
            last = self._last.get(host)
            if last is not None:
                gap = self._min + random.uniform(0, self._min * 0.3)
                delay = last + gap - time.monotonic()
                if delay > 0:
                    await asyncio.sleep(delay)
            self._last[host] = time.monotonic()


# -----------------------------------------------------------------------------
# Fetcher
# -----------------------------------------------------------------------------


class Fetcher:
    def __init__(
        self,
        *,
        user_agent: str,
        timeout_s: float = 25.0,
        per_host_min_interval_s: float = 8.0,
        respect_robots: bool = True,
        max_redirects: int = 5,
        attempts: int = 3,
        transport: httpx.AsyncBaseTransport | None = None,
        url_guard=assert_public_url,  # noqa: ANN001 - injectable for tests
        extra_ca_bundle: str | None = None,
        allow_legacy_tls_renegotiation: bool = True,
    ) -> None:
        self.user_agent = user_agent
        self._throttle = HostThrottle(per_host_min_interval_s)
        self._respect_robots = respect_robots
        self._max_redirects = max_redirects
        self._attempts = attempts
        self._guard = url_guard
        self._robots: dict[str, tuple[float, RobotFileParser | None]] = {}
        self._client = httpx.AsyncClient(
            follow_redirects=False,
            timeout=httpx.Timeout(timeout_s, connect=10.0),
            headers={
                "User-Agent": user_agent,
                "Accept-Language": "en-IN,en;q=0.9,hi;q=0.6",
            },
            limits=httpx.Limits(max_connections=10, max_keepalive_connections=5),
            transport=transport,
            verify=tls_context(extra_ca_bundle, allow_legacy_renegotiation=allow_legacy_tls_renegotiation),
        )

    async def aclose(self) -> None:
        await self._client.aclose()

    async def __aenter__(self) -> Fetcher:
        return self

    async def __aexit__(self, *exc: object) -> None:
        await self.aclose()

    async def get(self, url: str, *, max_bytes: int, check_robots: bool = True) -> FetchResult:
        retrying = AsyncRetrying(
            retry=retry_if_exception_type(RetryableFetchError),
            wait=wait_exponential_jitter(initial=5, max=60),
            stop=stop_after_attempt(self._attempts),
            reraise=True,
        )
        async for attempt in retrying:
            with attempt:
                return await self._get_once(url, max_bytes=max_bytes, check_robots=check_robots)
        raise AssertionError("unreachable")

    async def _get_once(self, url: str, *, max_bytes: int, check_robots: bool) -> FetchResult:
        current = url
        for _ in range(self._max_redirects + 1):
            await self._guard(current)
            if check_robots and self._respect_robots and not await self._robots_allow(current):
                raise RobotsDisallowedError(f"robots.txt disallows {current}")
            host = urlsplit(current).hostname or ""
            await self._throttle.wait(host)
            try:
                async with self._client.stream("GET", current) as resp:
                    if resp.is_redirect:
                        location = resp.headers.get("location")
                        if not location:
                            raise FetchError("Redirect without Location")
                        current = urljoin(str(resp.url), location)
                        continue
                    if resp.status_code == 429 or resp.status_code >= 500:
                        await self._honour_retry_after(resp)
                        raise RetryableFetchError(f"HTTP {resp.status_code} from {host}")
                    if resp.status_code >= 400:
                        raise FetchError(f"HTTP {resp.status_code} for {current}")
                    declared = int(resp.headers.get("content-length") or 0)
                    if declared > max_bytes:
                        raise FetchError(f"Response too large ({declared} bytes)")
                    buf = bytearray()
                    async for chunk in resp.aiter_bytes():
                        buf.extend(chunk)
                        if len(buf) > max_bytes:
                            raise FetchError(f"Response exceeded {max_bytes} bytes")
                    return FetchResult(
                        url=str(resp.url),
                        status=resp.status_code,
                        content_type=resp.headers.get("content-type", ""),
                        body=bytes(buf),
                        encoding=resp.charset_encoding,
                    )
            except httpx.TransportError as exc:  # timeouts, resets, TLS errors
                raise RetryableFetchError(f"{type(exc).__name__} for {current}") from exc
        raise FetchError("Too many redirects")

    @staticmethod
    async def _honour_retry_after(resp: httpx.Response) -> None:
        try:
            delay = float(resp.headers.get("retry-after", "0"))
        except ValueError:
            return
        if 0 < delay <= 120:
            await asyncio.sleep(delay)

    async def _robots_allow(self, url: str) -> bool:
        parts = urlsplit(url)
        origin = f"{parts.scheme}://{parts.netloc}"
        cached = self._robots.get(origin)
        if cached is None or time.monotonic() - cached[0] > _ROBOTS_TTL_S:
            parser: RobotFileParser | None = None
            try:
                res = await self._get_once(f"{origin}/robots.txt", max_bytes=512 * 1024, check_robots=False)
                parser = RobotFileParser()
                parser.parse(res.text.splitlines())
            except FetchError as exc:
                # 4xx (no robots.txt) => allowed; we also fail open on errors and log it.
                log.debug("robots.txt unavailable for %s: %s", origin, exc)
            self._robots[origin] = (time.monotonic(), parser)
            cached = self._robots[origin]
        parser = cached[1]
        return True if parser is None else parser.can_fetch(self.user_agent, url)
