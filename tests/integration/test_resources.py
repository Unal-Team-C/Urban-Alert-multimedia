"""Bucket policy, idempotent init and Mongo indexes (RF-009, plan D-007/D-010)."""

import json

import httpx
import pytest

from app.admin.init_resources import ensure_all
from app.storage.objects import ObjectStore
from tests import samples

pytestmark = pytest.mark.integration


def test_init_is_idempotent(provisioned):
    ensure_all(provisioned)
    ensure_all(provisioned)


def test_policy_allows_only_anonymous_get_object(provisioned, s3):
    policy = json.loads(s3.get_bucket_policy(Bucket=provisioned.s3_bucket)["Policy"])
    actions = {action for statement in policy["Statement"] for action in statement["Action"]}
    assert actions == {"s3:GetObject"}


def test_unique_index_on_object_key(provisioned, images):
    index = images.index_information()["objectKey_unique"]
    assert index["unique"] is True and index["key"] == [("objectKey", 1)]


def test_anonymous_can_read_an_object_by_key(clean_storage, bucket_url):
    data = samples.jpeg()
    ObjectStore(clean_storage).put("known.jpg", data, "image/jpeg")
    response = httpx.get(f"{bucket_url}/known.jpg")
    assert response.status_code == 200
    assert response.content == data
    assert response.headers["content-type"] == "image/jpeg"


def test_anonymous_cannot_list_write_or_delete(clean_storage, bucket_url):
    ObjectStore(clean_storage).put("known.jpg", samples.jpeg(), "image/jpeg")
    assert httpx.get(bucket_url).status_code == 403
    assert httpx.get(f"{bucket_url}?list-type=2").status_code == 403
    assert httpx.put(f"{bucket_url}/intruder.jpg", content=samples.jpeg()).status_code == 403
    assert httpx.delete(f"{bucket_url}/known.jpg").status_code == 403
