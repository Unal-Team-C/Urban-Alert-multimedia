"""UploadImage: HU-1 and HU-4 acceptance criteria against the real MinIO and MongoDB."""

import re

import pytest

from tests import samples
from tests.conftest import UPLOAD_URL, object_keys, upload

pytestmark = pytest.mark.integration

MAX = 3_670_016
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"


def _assert_nothing_stored(s3, images, settings):
    assert object_keys(s3, settings.s3_bucket) == []
    assert images.count_documents({}) == 0


def test_jpeg_3mb_accepted_with_definitive_url(client, s3, images, clean_storage):
    response = upload(client, samples.jpeg(size=3 * samples.MB))
    assert response.status_code == 201
    body = response.json()
    assert set(body) == {"imageId", "imageUrl", "contentType", "sizeBytes", "uploadedAt", "capture"}
    assert re.fullmatch(UUID, body["imageId"])
    assert body["imageUrl"] == f"{clean_storage.public_image_base_url}/{body['imageId']}.jpg"
    assert body["contentType"] == "image/jpeg" and body["capture"] is None
    assert response.headers["location"] == f"{UPLOAD_URL}/{body['imageId']}/metadata"
    assert object_keys(s3, clean_storage.s3_bucket) == [f"{body['imageId']}.jpg"]
    assert images.find_one({"_id": body["imageId"]})["objectKey"] == f"{body['imageId']}.jpg"


def test_png_2mb_accepted(client):
    response = upload(client, samples.png(size=2 * samples.MB), "photo.png", "image/png")
    assert response.status_code == 201
    assert response.json()["contentType"] == "image/png"
    assert response.json()["imageUrl"].endswith(".png")


@pytest.mark.parametrize(
    ("data", "filename", "declared"),
    [
        (samples.heic(samples.MB), "IMG_0001.heic", "image/heic"),
        (samples.pdf(samples.MB), "report.pdf", "application/pdf"),
        (samples.exe(), "photo.jpg", "image/jpeg"),  # executable renamed .jpg
        (samples.webp(), "photo.webp", "image/webp"),
    ],
    ids=["heic", "pdf", "exe-named-jpg", "webp"],
)
def test_unsupported_formats_rejected_and_nothing_stored(client, s3, images, clean_storage, data, filename, declared):
    response = upload(client, data, filename, declared)
    assert response.status_code == 415
    assert response.json()["message"] == "Unsupported image format"
    _assert_nothing_stored(s3, images, clean_storage)


def test_25mb_rejected_before_parsing(client, s3, images, clean_storage):
    response = upload(client, samples.jpeg(size=25 * samples.MB))
    assert response.status_code == 413
    assert response.json() == {"code": 413, "message": "Image exceeds the maximum size"}
    _assert_nothing_stored(s3, images, clean_storage)


def test_exact_maximum_accepted_and_one_byte_more_rejected(client, s3, images, clean_storage):
    assert upload(client, samples.jpeg(size=MAX)).status_code == 201
    images.delete_many({})
    for key in object_keys(s3, clean_storage.s3_bucket):
        s3.delete_object(Bucket=clean_storage.s3_bucket, Key=key)
    response = upload(client, samples.jpeg(size=MAX + 1))
    assert response.status_code == 413
    assert response.json()["details"][0]["field"] == "image"
    _assert_nothing_stored(s3, images, clean_storage)


def test_declared_type_is_ignored(client):
    response = upload(client, samples.jpeg(), "photo.png", "image/png")
    assert response.status_code == 201
    assert response.json()["contentType"] == "image/jpeg"


def test_same_file_twice_gives_two_images(client, s3, clean_storage):
    data = samples.jpeg()
    first, second = upload(client, data).json(), upload(client, data).json()
    assert first["imageId"] != second["imageId"] and first["imageUrl"] != second["imageUrl"]
    assert len(object_keys(s3, clean_storage.s3_bucket)) == 2


def test_missing_or_empty_image_is_invalid(client, s3, images, clean_storage):
    missing = client.post(UPLOAD_URL, data={"lat": "4.6", "lon": "-74.08"})
    assert missing.status_code == 400
    assert missing.json()["details"][0]["field"] == "image"
    empty = upload(client, b"")
    assert empty.status_code == 400
    _assert_nothing_stored(s3, images, clean_storage)


def test_invalid_capture_rejected_and_nothing_stored(client, s3, images, clean_storage):
    response = upload(client, samples.jpeg(), lat="4.6")
    assert response.status_code == 400
    assert response.json()["details"] == [{"field": "lon", "reason": "lat and lon must be sent together"}]
    _assert_nothing_stored(s3, images, clean_storage)


def test_malicious_file_name_does_not_influence_the_key(client, s3, clean_storage):
    body = upload(client, samples.jpeg(), "../../etc/passwd.jpg").json()
    assert object_keys(s3, clean_storage.s3_bucket) == [f"{body['imageId']}.jpg"]


def test_size_is_the_stored_size_after_cleaning(client, s3, clean_storage):
    received = samples.jpeg_with_personal_metadata()
    body = upload(client, received).json()
    stored = s3.head_object(Bucket=clean_storage.s3_bucket, Key=f"{body['imageId']}.jpg")
    assert body["sizeBytes"] == stored["ContentLength"] < len(received)


def test_progress_photos_one_by_one_each_get_their_url(client):
    """HU-4: a supervisor uploads several progress photos."""
    bodies = [upload(client, samples.jpeg()).json() for _ in range(3)]
    assert len({body["imageUrl"] for body in bodies}) == 3
    assert all(body["uploadedAt"].endswith("Z") for body in bodies)


def test_capture_data_is_returned(client):
    body = upload(client, samples.jpeg(), capturedAt="2026-10-06T16:12:05-05:00", lat="4.6097", lon="-74.0817").json()
    assert body["capture"] == {"capturedAt": "2026-10-06T16:12:05-05:00", "coordinate": {"lat": 4.6097, "lon": -74.0817}}


@pytest.mark.parametrize(
    ("data", "filename", "content_type"),
    [
        (b"\xff\xd8\xff\xe1\xff\xf0Exif\0\0" + b"\0" * 64, "broken.jpg", "image/jpeg"),  # APP1 longer than the file
        (samples.png()[:8] + b"\0\0\x27\x10tEXt" + b"x" * 16, "broken.png", "image/png"),  # truncated chunk
    ],
    ids=["jpeg-app1-overflow", "png-truncated-chunk"],
)
def test_damaged_metadata_structure_rejected_and_nothing_stored(client, s3, images, clean_storage, data, filename, content_type):
    """Spec §4 edge case: metadata that cannot be removed safely is never stored (RF-017)."""
    response = upload(client, data, filename, content_type)
    assert response.status_code == 415
    assert response.json()["details"][0]["field"] == "image"
    _assert_nothing_stored(s3, images, clean_storage)
