"""GetImageMetadata and capture data (HU-3, RF-010, RF-015, RF-017)."""

import io
import uuid

import httpx
import pytest
from PIL import Image

from app.api.routes import get_service
from app.service import ImageService
from app.storage.metadata import MetadataStore
from app.storage.objects import ObjectStore
from tests import samples
from tests.conftest import UPLOAD_URL, upload

pytestmark = pytest.mark.integration


def _metadata(client, image_id: str):
    return client.get(f"{UPLOAD_URL}/{image_id}/metadata")


def test_full_capture_round_trip(client):
    created = upload(client, samples.jpeg(), capturedAt="2026-10-06T16:12:05-05:00", lat="4.6097", lon="-74.0817")
    response = _metadata(client, created.json()["imageId"])
    assert response.status_code == 200
    assert response.json() == created.json()
    assert response.json()["capture"]["capturedAt"] == "2026-10-06T16:12:05-05:00"


def test_only_capture_date(client):
    body = upload(client, samples.jpeg(), capturedAt="2026-10-06T10:30:00+05:30").json()
    capture = _metadata(client, body["imageId"]).json()["capture"]
    assert capture == {"capturedAt": "2026-10-06T10:30:00+05:30", "coordinate": None}


def test_without_capture_data_records_only_the_upload(client, images):
    body = upload(client, samples.png(), "gallery.png", "image/png").json()
    metadata = _metadata(client, body["imageId"]).json()
    assert metadata["capture"] is None
    assert metadata["uploadedAt"].endswith("Z")
    stored = images.find_one({"_id": body["imageId"]})
    assert stored["capture"] is None and stored["sizeBytes"] == metadata["sizeBytes"]


def test_downloaded_file_has_no_personal_metadata_but_keeps_orientation(client, clean_storage, bucket_url):
    body = upload(client, samples.jpeg_with_personal_metadata()).json()
    downloaded = httpx.get(f"{bucket_url}/{body['imageId']}.jpg").content
    for personal in samples.PERSONAL_STRINGS:
        assert personal not in downloaded
    exif = Image.open(io.BytesIO(downloaded)).getexif()
    assert dict(exif) == {0x0112: 6}  # HU-3.6
    assert not exif.get_ifd(samples.GPS_IFD)  # HU-3.5


@pytest.mark.parametrize("image_id", [str(uuid.uuid4()), "not-a-uuid", "' OR 1=1 --"], ids=["unknown", "malformed", "injection"])
def test_unknown_image_is_not_found(client, image_id):
    response = _metadata(client, image_id)
    assert response.status_code == 404
    assert response.json() == {"code": 404, "message": "Image not found"}


def test_metadata_storage_down_returns_503(client, clean_storage):
    from dataclasses import replace

    settings = replace(clean_storage, mongodb_timeout_ms=1000)
    service = ImageService(settings, ObjectStore(settings), MetadataStore(settings, "mongodb://127.0.0.1:1/?directConnection=true"))
    client.app.dependency_overrides[get_service] = lambda: service
    assert _metadata(client, str(uuid.uuid4())).status_code == 503
