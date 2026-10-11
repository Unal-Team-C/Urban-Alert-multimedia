"""MongoDB URI resolution: local env var vs. AWS Secrets Manager (spec 002 RF-004, plan §7.3)."""

import pytest
from botocore.exceptions import ClientError

from app.config import Settings
from app.storage import metadata
from app.storage.metadata import MetadataStore, MetadataStoreError, resolve_uri

SECRET_ARN = "arn:aws:secretsmanager:us-east-2:348364742283:secret:urban-alert-multimedia-docdb-AbCdEf"
CLOUD_URI = "mongodb://multimedia:pw@docdb.example:27017/?tls=true&replicaSet=rs0&retryWrites=false"


class FakeSecrets:
    def __init__(self, error: Exception | None = None):
        self.calls = []
        self.error = error

    def get_secret_value(self, SecretId):
        self.calls.append(SecretId)
        if self.error:
            raise self.error
        return {"SecretString": CLOUD_URI}


@pytest.fixture
def fake_secrets(monkeypatch):
    def install(error: Exception | None = None) -> FakeSecrets:
        fake = FakeSecrets(error)
        monkeypatch.setattr(metadata, "secrets_client", lambda: fake)
        return fake

    resolve_uri.cache_clear()
    yield install
    resolve_uri.cache_clear()


def test_without_secret_arn_uses_mongodb_uri(fake_secrets):
    fake = fake_secrets()
    settings = Settings(mongodb_uri="mongodb://local:27017")
    assert resolve_uri(settings) == "mongodb://local:27017"
    assert fake.calls == []


def test_with_secret_arn_reads_the_uri_from_secrets_manager_once(fake_secrets):
    fake = fake_secrets()
    settings = Settings(mongodb_uri_secret_arn=SECRET_ARN)
    assert resolve_uri(settings) == CLOUD_URI
    assert resolve_uri(settings) == CLOUD_URI
    assert fake.calls == [SECRET_ARN]


def test_secret_failure_is_a_metadata_store_error_and_is_retried(fake_secrets):
    error = ClientError({"Error": {"Code": "AccessDeniedException", "Message": "denied"}}, "GetSecretValue")
    fake = fake_secrets(error)
    settings = Settings(mongodb_uri_secret_arn=SECRET_ARN)
    with pytest.raises(MetadataStoreError):
        resolve_uri(settings)
    with pytest.raises(MetadataStoreError):
        resolve_uri(settings)
    assert len(fake.calls) == 2  # failures are not cached


def test_store_reports_secret_failure_on_use_not_on_creation(fake_secrets):
    fake_secrets(ClientError({"Error": {"Code": "ResourceNotFoundException", "Message": "gone"}}, "GetSecretValue"))
    store = MetadataStore(Settings(mongodb_uri_secret_arn=SECRET_ARN))  # built per request: must not fail here
    with pytest.raises(MetadataStoreError):
        store.find("7f3c2a9e-1b4d-4c6e-9a8f-2d1e0b5c7a31")
