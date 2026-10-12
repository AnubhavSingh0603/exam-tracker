import httpx
import pytest

from app.services.http_fetcher import BlockedURLError, Fetcher, FetchError, assert_public_url


@pytest.mark.parametrize(
    "url",
    [
        "http://127.0.0.1/",
        "http://localhost/admin",
        "http://169.254.169.254/opc/v2/instance/",  # OCI metadata service
        "http://10.0.0.5/",
        "http://192.168.1.1/",
        "http://100.64.0.1/",  # CGNAT
        "http://[::1]/",
        "http://[::ffff:127.0.0.1]/",  # IPv4-mapped loopback
        "ftp://example.com/file.pdf",
        "file:///etc/passwd",
        "http://8.8.8.8:22/",
        "http://user:pass@8.8.8.8/",
    ],
)
async def test_guard_blocks_unsafe_targets(url):
    with pytest.raises(BlockedURLError):
        await assert_public_url(url)


async def test_guard_allows_public_ip_literal():
    await assert_public_url("https://8.8.8.8/notice.pdf")


def _fetcher(handler) -> Fetcher:  # noqa: ANN001
    return Fetcher(
        user_agent="test",
        per_host_min_interval_s=0,
        respect_robots=False,
        attempts=1,
        transport=httpx.MockTransport(handler),
    )


async def test_redirect_to_private_address_is_rechecked_and_blocked():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(302, headers={"location": "http://169.254.169.254/latest/meta-data"})

    async with _fetcher(handler) as f:
        with pytest.raises(BlockedURLError):
            await f.get("http://93.184.216.34/careers", max_bytes=1024)


async def test_body_size_cap_enforced_while_streaming():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"x" * 5000)

    async with _fetcher(handler) as f:
        with pytest.raises(FetchError, match="exceeded|too large"):
            await f.get("http://93.184.216.34/big", max_bytes=1000)


async def test_pdf_detection_and_robots(monkeypatch):
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/robots.txt":
            return httpx.Response(200, text="User-agent: *\nDisallow: /private/\n")
        return httpx.Response(200, content=b"%PDF-1.7 ...", headers={"content-type": "application/pdf"})

    f = Fetcher(
        user_agent="ExamTrackerBot/0.3",
        per_host_min_interval_s=0,
        attempts=1,
        transport=httpx.MockTransport(handler),
    )
    async with f:
        res = await f.get("http://93.184.216.34/public/a.pdf", max_bytes=10_000)
        assert res.is_pdf
        with pytest.raises(FetchError, match="robots"):
            await f.get("http://93.184.216.34/private/b.pdf", max_bytes=10_000)
