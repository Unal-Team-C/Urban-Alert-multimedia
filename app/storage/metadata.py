"""Image metadata documents in MongoDB (collection `images`, plan §6)."""

from functools import lru_cache

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


def collection_for(settings: Settings, uri: str | None = None):
    client = mongo_client(uri or settings.mongodb_uri, settings.mongodb_timeout_ms, settings.mongodb_max_pool_size)
    return client[settings.mongodb_database][COLLECTION]


class MetadataStore:
    def __init__(self, settings: Settings, uri: str | None = None):
        self._collection = collection_for(settings, uri)

    def insert(self, document: dict) -> None:
        try:
            self._collection.insert_one(document)
        except PyMongoError as error:
            raise MetadataStoreError(str(error)) from error

    def find(self, image_id: str) -> dict | None:
        try:
            return self._collection.find_one({"_id": image_id})
        except PyMongoError as error:
            raise MetadataStoreError(str(error)) from error
