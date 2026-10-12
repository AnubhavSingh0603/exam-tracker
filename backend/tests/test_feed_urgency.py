from datetime import UTC, datetime, timedelta

import pytest

from app.domain.enums import UrgencyBand
from app.services.feed import urgency_for

NOW = datetime(2026, 10, 11, 12, 0, tzinfo=UTC)


@pytest.mark.parametrize(
    ("delta", "band"),
    [
        (timedelta(hours=5), UrgencyBand.CRITICAL),
        (timedelta(hours=71, minutes=59), UrgencyBand.CRITICAL),
        (timedelta(hours=72), UrgencyBand.APPROACHING),
        (timedelta(days=14), UrgencyBand.APPROACHING),
        (timedelta(days=14, hours=1), UrgencyBand.SAFE),
    ],
)
def test_bands(delta, band):
    assert urgency_for(NOW + delta, NOW)[0] is band
