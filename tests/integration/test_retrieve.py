"""Reading an image through its definitive URL, straight from the storage (HU-2, RF-007/008/009, RNF-005)."""

import statistics
import time
import uuid

import httpx
import pytest

from tests import samples
from tests.conftest import upload

pytestmark = pytest.mark.integration


@pytest.mark.parametrize(
    ("data", "filename", "content_type"),
    [(samples.jpeg_with_personal_metadata(), "photo.jpg", "image/jpeg"), (samples.png(), "photo.png", "image/png")],
    ids=["jpeg", "png"],
)
def test_anonymous_download_returns_the_stored_image(client, s3, clean_storage, data, filename, content_type):
    body = upload(client, data, filename, content_type).json()
    response = httpx.get(body["imageUrl"])
    assert response.status_code == 200
    assert response.headers["content-type"] == content_type
    key = body["imageUrl"].rsplit("/", 1)[1]
    stored = s3.get_object(Bucket=clean_storage.s3_bucket, Key=key)["Body"].read()
    assert response.content == stored  # the cleaned file (RF-017), byte for byte


def test_unknown_url_returns_no_image(clean_storage, bucket_url):
    """HU-2.2. MinIO answers 404 NoSuchKey; AWS S3 without ListBucket answers 403 (CloudFront can map it
    to 404). Pending user decision on the spec wording (see STATE.md): here only "no image" is asserted."""
    response = httpx.get(f"{bucket_url}/{uuid.uuid4()}.jpg")
    assert response.status_code in (403, 404)
    assert not response.headers.get("content-type", "").startswith("image/")


def test_bucket_cannot_be_listed(clean_storage, bucket_url):
    assert httpx.get(bucket_url).status_code == 403


def test_url_is_definitive(client):
    url = upload(client, samples.jpeg()).json()["imageUrl"]
    assert "X-Amz-" not in url and "Signature" not in url and "Expires" not in url  # never expires (RF-008)
    assert len(url) < 2000  # Reportes stores up to 2000 characters (S-11)


def test_download_p95_under_2_seconds(client):
    """RNF-005: 20 downloads of a 3.5 MB image (PNG padding is image data, so it survives the cleaning)."""
    body = upload(client, samples.png(size=3_670_016), "big.png", "image/png").json()
    assert body["sizeBytes"] == 3_670_016
    durations = []
    with httpx.Client() as http:
        for _ in range(20):
            started = time.perf_counter()
            response = http.get(body["imageUrl"])
            durations.append(time.perf_counter() - started)
            assert response.status_code == 200 and len(response.content) == 3_670_016
    p95 = statistics.quantiles(durations, n=20)[-1]
    print(f"download p95={p95 * 1000:.1f} ms max={max(durations) * 1000:.1f} ms")
    assert p95 < 2
