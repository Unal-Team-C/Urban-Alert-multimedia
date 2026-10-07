"""Rules for the optional capture data sent with an upload (RF-010, spec §4 edge cases).

Capture coordinates are evidence metadata, not the report's official location: they are not
restricted to Bogotá (that is Geospatial's job).
"""

import math
from dataclasses import dataclass
from datetime import datetime


class InvalidCapture(ValueError):
    def __init__(self, field: str, reason: str):
        super().__init__(f"{field}: {reason}")
        self.field = field
        self.reason = reason


@dataclass(frozen=True)
class Capture:
    captured_at: datetime | None  # timezone-aware, original offset preserved
    lat: float | None
    lon: float | None

    @property
    def utc_offset_minutes(self) -> int | None:
        if self.captured_at is None:
            return None
        return int(self.captured_at.utcoffset().total_seconds() // 60)


def _blank(value) -> bool:
    return value is None or (isinstance(value, str) and value.strip() == "")


def _parse_datetime(value: str, now: datetime) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.strip())
    except ValueError:
        raise InvalidCapture("capturedAt", "must be an ISO 8601 date-time") from None
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise InvalidCapture("capturedAt", "must include a UTC offset or Z")
    if parsed > now:
        raise InvalidCapture("capturedAt", "must not be in the future")
    return parsed


def _parse_number(field: str, value, low: float, high: float) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        raise InvalidCapture(field, "must be a number") from None
    if not math.isfinite(number) or not low <= number <= high:
        raise InvalidCapture(field, f"must be between {low:g} and {high:g}")
    return number


def parse(captured_at, lat, lon, now: datetime) -> Capture | None:
    """Validate the capture fields; None when none was sent. `now` must be timezone-aware."""
    when = None if _blank(captured_at) else _parse_datetime(str(captured_at), now)
    has_lat, has_lon = not _blank(lat), not _blank(lon)
    if has_lat != has_lon:
        raise InvalidCapture("lon" if has_lat else "lat", "lat and lon must be sent together")
    latitude = _parse_number("lat", lat, -90, 90) if has_lat else None
    longitude = _parse_number("lon", lon, -180, 180) if has_lon else None
    if when is None and latitude is None:
        return None
    return Capture(captured_at=when, lat=latitude, lon=longitude)
