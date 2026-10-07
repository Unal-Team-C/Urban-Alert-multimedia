from datetime import UTC, datetime

import pytest

from app.domain.capture import Capture, InvalidCapture, parse

NOW = datetime(2026, 10, 6, 21, 15, tzinfo=UTC)


def test_nothing_sent_returns_none():
    assert parse(None, None, None, NOW) is None
    assert parse("", " ", "", NOW) is None


def test_full_capture_keeps_original_offset():
    capture = parse("2026-10-06T16:12:05-05:00", "4.6097", "-74.0817", NOW)
    assert capture == Capture(datetime.fromisoformat("2026-10-06T16:12:05-05:00"), 4.6097, -74.0817)
    assert capture.utc_offset_minutes == -300


def test_z_suffix_accepted():
    assert parse("2026-10-06T21:00:00Z", None, None, NOW).utc_offset_minutes == 0


def test_only_date_or_only_coordinates():
    assert parse("2026-10-06T10:00:00Z", None, None, NOW).lat is None
    only_coordinates = parse(None, 4.6, -74.08, NOW)
    assert only_coordinates.captured_at is None and only_coordinates.utc_offset_minutes is None


def test_coordinates_outside_bogota_are_accepted():
    assert parse(None, "48.8584", "2.2945", NOW).lat == 48.8584


@pytest.mark.parametrize(
    ("captured_at", "lat", "lon", "field"),
    [
        ("2026-10-06T16:12:05", None, None, "capturedAt"),  # no offset
        ("06/10/2026", None, None, "capturedAt"),  # not ISO 8601
        ("2026-10-07T00:00:00Z", None, None, "capturedAt"),  # future
        (None, "4.6", None, "lon"),  # only lat
        (None, None, "-74.08", "lat"),  # only lon
        (None, "90.1", "0", "lat"),
        (None, "0", "-180.5", "lon"),
        (None, "abc", "0", "lat"),
        (None, "nan", "0", "lat"),
        (None, "0", "inf", "lon"),
        (None, "' OR 1=1 --", "0", "lat"),
    ],
)
def test_invalid_capture_points_to_the_field(captured_at, lat, lon, field):
    with pytest.raises(InvalidCapture) as error:
        parse(captured_at, lat, lon, NOW)
    assert error.value.field == field


def test_range_limits_are_inclusive():
    capture = parse(None, "-90", "180", NOW)
    assert (capture.lat, capture.lon) == (-90, 180)
