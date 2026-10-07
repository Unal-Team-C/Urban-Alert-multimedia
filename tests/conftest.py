"""Shared fixtures. Integration tests use the real MinIO and MongoDB with a test bucket and database."""

from urllib.parse import urlsplit

import pytest

from app.config import Settings
from app.storage.metadata import collection_for
from app.storage.objects import client_for


@pytest.fixture(scope="session")
def settings() -> Settings:
    return Settings.from_env()


@pytest.fixture(scope="session")
def provisioned(settings):
    from app.admin.init_resources import ensure_all

    ensure_all(settings)
    return settings


@pytest.fixture(scope="session")
def s3(settings):
    return client_for(settings)


@pytest.fixture(scope="session")
def images(settings):
    return collection_for(settings)


@pytest.fixture
def clean_storage(provisioned, s3, images):
    """Empty the test bucket and collection before each test."""
    bucket = provisioned.s3_bucket
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket):
        for item in page.get("Contents", []):
            s3.delete_object(Bucket=bucket, Key=item["Key"])
    images.delete_many({})
    yield provisioned


def object_keys(s3, bucket: str) -> list[str]:
    response = s3.list_objects_v2(Bucket=bucket)
    return [item["Key"] for item in response.get("Contents", [])]


@pytest.fixture(scope="session")
def bucket_url(settings) -> str:
    """Anonymous URL of the bucket root (as seen from the tests container)."""
    parts = urlsplit(settings.public_image_base_url)
    return f"{parts.scheme}://{parts.netloc}{parts.path}"


@pytest.fixture
def client(clean_storage):
    from fastapi.testclient import TestClient

    from app.main import create_app

    with TestClient(create_app(clean_storage)) as test_client:
        yield test_client


UPLOAD_URL = "/api/v1/multimedia/images"


def upload(client, data: bytes, filename: str = "photo.jpg", content_type: str = "image/jpeg", **fields):
    return client.post(UPLOAD_URL, files={"image": (filename, data, content_type)}, data=fields)
