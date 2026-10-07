"""Unavailable storage → 503 with no leftovers (RF-016, RNF-006); time bounded below 15 s (RNF-002)."""

import logging
import time
from dataclasses import replace

import pytest

from app.api.errors import StorageUnavailable
from app.api.routes import get_service
from app.service import ImageService
from app.storage.metadata import MetadataStore
from app.storage.objects import ObjectStore, ObjectStoreError
from tests import samples
from tests.conftest import object_keys, upload

pytestmark = pytest.mark.integration

CLOSED_PORT_MONGO = "mongodb://127.0.0.1:1/?directConnection=true"
CLOSED_PORT_S3 = "http://127.0.0.1:1"


@pytest.fixture
def fast_settings(clean_storage):
    return replace(clean_storage, mongodb_timeout_ms=1000)


def _override(client, service: ImageService):
    client.app.dependency_overrides[get_service] = lambda: service


def test_mongo_down_returns_503_and_removes_the_object(client, s3, images, fast_settings):
    _override(client, ImageService(fast_settings, ObjectStore(fast_settings), MetadataStore(fast_settings, CLOSED_PORT_MONGO)))
    started = time.monotonic()
    response = upload(client, samples.jpeg())
    assert time.monotonic() - started < 15
    assert response.status_code == 503
    assert response.json() == {"code": 503, "message": "Service unavailable"}
    assert object_keys(s3, fast_settings.s3_bucket) == []  # compensated
    assert images.count_documents({}) == 0


def test_object_storage_down_returns_503_and_writes_no_document(client, s3, images, fast_settings):
    _override(client, ImageService(fast_settings, ObjectStore(fast_settings, CLOSED_PORT_S3), MetadataStore(fast_settings)))
    started = time.monotonic()
    response = upload(client, samples.jpeg())
    assert time.monotonic() - started < 15
    assert response.status_code == 503
    assert images.count_documents({}) == 0
    assert object_keys(s3, fast_settings.s3_bucket) == []


class _UndeletableStore(ObjectStore):
    def delete(self, key: str) -> None:
        raise ObjectStoreError("delete refused")


class _Records(logging.Handler):
    def __init__(self):
        super().__init__()
        self.records = []

    def emit(self, record):
        self.records.append(record)


def test_failed_compensation_is_logged_with_the_object_key(s3, fast_settings):
    service = ImageService(fast_settings, _UndeletableStore(fast_settings), MetadataStore(fast_settings, CLOSED_PORT_MONGO))
    handler = _Records()
    logger = logging.getLogger("app.service")
    logger.addHandler(handler)
    try:
        with pytest.raises(StorageUnavailable):
            service.upload_image(samples.jpeg(), None, None, None)
    finally:
        logger.removeHandler(handler)
    orphan = [r for r in handler.records if r.getMessage() == "compensation failed: orphan object"]
    assert len(orphan) == 1
    key = orphan[0].fields["objectKey"]
    assert object_keys(s3, fast_settings.s3_bucket) == [key]  # left for the deferred cleanup (HU-6)
