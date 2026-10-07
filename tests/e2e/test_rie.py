"""End-to-end through the Lambda Runtime Interface Emulator with API Gateway v2 events (HU-5, RNF-002, RNF-010)."""

import json
import os
import time
from urllib.parse import urlsplit

import httpx
import pytest

from tests import samples
from tests.events import http_event, upload_event

pytestmark = pytest.mark.e2e

INVOKE_URL = os.environ.get("MULTIMEDIA_INVOKE_URL", "http://multimedia:8080/2015-03-31/functions/function/invocations")
SYNC_PAYLOAD_LIMIT = 6 * 1024 * 1024  # AWS Lambda synchronous invocation limit
MAX = 3_670_016


def invoke(event: dict) -> httpx.Response:
    return httpx.post(INVOKE_URL, content=json.dumps(event), timeout=30)


def internal(url: str) -> str:
    """imageUrl points to localhost:9000 (reachable from the host); from this container MinIO is minio:9000."""
    parts = urlsplit(url)
    return f"http://minio:9000{parts.path}"


def test_upload_event_returns_201_and_a_downloadable_url():
    response = invoke(upload_event(samples.jpeg_with_personal_metadata(), capturedAt="2026-10-06T16:12:05-05:00", lat="4.6097", lon="-74.0817"))
    assert response.status_code == 200  # the RIE call itself
    result = response.json()
    assert result["statusCode"] == 201
    body = json.loads(result["body"])
    assert body["imageUrl"].startswith("http://localhost:9000/urbanalert-images/")
    download = httpx.get(internal(body["imageUrl"]))
    assert download.status_code == 200 and download.headers["content-type"] == "image/jpeg"
    assert b"iPhone 15 Pro" not in download.content


def test_metadata_event_returns_200():
    created = json.loads(invoke(upload_event(samples.png(), "photo.png", "image/png")).json()["body"])
    result = invoke(http_event("GET", f"/api/v1/multimedia/images/{created['imageId']}/metadata")).json()
    assert result["statusCode"] == 200
    assert json.loads(result["body"]) == created


def test_largest_image_fits_the_payload_limit_and_the_timeout():
    event = upload_event(samples.png(size=MAX), "big.png", "image/png", capturedAt="2026-10-06T16:12:05-05:00", lat="4.6", lon="-74.08")
    size = len(json.dumps(event).encode())
    assert size < SYNC_PAYLOAD_LIMIT, size  # RNF-010
    started = time.monotonic()
    result = invoke(event).json()
    elapsed = time.monotonic() - started
    print(f"max image: event={size} bytes, invocation={elapsed * 1000:.0f} ms")
    assert result["statusCode"] == 201
    assert elapsed < 15  # RNF-002


def test_event_above_6mb_is_rejected_one_way_or_another():
    """Research R-3: record how the RIE treats a payload larger than the cloud limit."""
    event = upload_event(samples.png(size=int(4.8 * samples.MB)), "huge.png", "image/png")
    size = len(json.dumps(event).encode())
    assert size > SYNC_PAYLOAD_LIMIT
    response = invoke(event)
    try:
        result = response.json()
    except ValueError:
        result = {"raw": response.text[:200]}
    print(f"RIE with {size} bytes: http={response.status_code} result={str(result)[:300]}")
    if isinstance(result, dict) and "statusCode" in result:
        assert result["statusCode"] == 413  # the RIE let it through: the function enforces RF-003
    else:
        assert response.status_code >= 400 or "errorType" in str(result)  # rejected by the RIE itself
