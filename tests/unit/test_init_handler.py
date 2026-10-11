"""Lambda entry point of the one-off init process (spec 002 RF-007, plan D-007): indexes only, never S3."""

from app.admin import init_resources
from tests.events import lambda_context


class FakeCollection:
    def __init__(self):
        self.indexes = []

    def create_index(self, keys, **options):
        self.indexes.append((keys, options))
        return options["name"]


def test_handler_creates_the_indexes_and_does_not_touch_s3(monkeypatch):
    collection = FakeCollection()
    monkeypatch.setattr(init_resources, "collection_for", lambda settings: collection)

    def no_s3(*args, **kwargs):
        raise AssertionError("the init function must not use S3: the bucket belongs to Terraform")

    monkeypatch.setattr(init_resources, "client_for", no_s3)

    result = init_resources.handler({}, lambda_context())

    assert collection.indexes == [("objectKey", {"unique": True, "name": "objectKey_unique"})]
    assert result == {"indexes": ["objectKey_unique"]}
