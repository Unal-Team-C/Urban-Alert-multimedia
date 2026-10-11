"""Image metadata documents in MongoDB (collection `images`, plan §6).

Locally the URI comes from MONGODB_URI; in AWS from Secrets Manager (MONGODB_URI_SECRET_ARN), so the
DocumentDB password never appears in the function configuration (spec 002 RF-004, plan D-006).
"""

from functools import lru_cache

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from pymongo import MongoClient
from pymongo.errors import PyMongoError

from app.config import Settings

COLLECTION = "images"


class MetadataStoreError(Exception):
    """MongoDB unreachable or failing."""


@lru_cache
def mongo_client(uri: str, timeout_ms: int, max_pool_size: int) -> MongoClient:
    """One client per process, reused across Lambda invocations. Connects lazily."""
    return MongoClient(
        uri,
        serverSelectionTimeoutMS=timeout_ms,
        connectTimeoutMS=timeout_ms,
        socketTimeoutMS=timeout_ms,
        maxPoolSize=max_pool_size,
        tz_aware=True,
    )


@lru_cache
def secrets_client():
    """One client per process, reused across Lambda invocations."""
    return boto3.client("secretsmanager")


@lru_cache
def resolve_uri(settings: Settings) -> str:
    """Read once per process; a failure is not cached, so the next request retries."""
    if not settings.mongodb_uri_secret_arn:
        return settings.mongodb_uri
    try:
        return secrets_client().get_secret_value(SecretId=settings.mongodb_uri_secret_arn)["SecretString"]
    except (BotoCoreError, ClientError) as error:
        raise MetadataStoreError(f"cannot read the MongoDB URI secret: {error}") from error


def collection_for(settings: Settings, uri: str | None = None):
    client = mongo_client(uri or resolve_uri(settings), settings.mongodb_timeout_ms, settings.mongodb_max_pool_size)
    return client[settings.mongodb_database][COLLECTION]


class MetadataStore:
    """Built per request: the collection (and the secret behind it) is resolved on first use, so a failure
    surfaces as MetadataStoreError (503) inside the service instead of while building the dependency."""

    def __init__(self, settings: Settings, uri: str | None = None):
        self._settings = settings
        self._uri = uri

    def _collection(self):
        return collection_for(self._settings, self._uri)

    def insert(self, document: dict) -> None:
        try:
            self._collection().insert_one(document)
        except PyMongoError as error:
            raise MetadataStoreError(str(error)) from error

    def find(self, image_id: str) -> dict | None:
        try:
            return self._collection().find_one({"_id": image_id})
        except PyMongoError as error:
            raise MetadataStoreError(str(error)) from error
