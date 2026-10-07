"""Object storage access (S3 in the cloud, MinIO locally).

Endpoint, region and credentials come from the standard AWS variables that boto3 reads natively
(AWS_ENDPOINT_URL_S3 is only set locally), so the code has no per-environment branches (plan D-005).
"""

from functools import lru_cache

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from app.config import Settings


class ObjectStoreError(Exception):
    """Object storage unreachable or failing after the configured retries."""


@lru_cache
def s3_client(addressing_style: str, connect_timeout: float, read_timeout: float, max_attempts: int, endpoint_url: str | None = None):
    """One client per process, reused across Lambda invocations."""
    config = Config(
        s3={"addressing_style": addressing_style},
        retries={"mode": "standard", "max_attempts": max_attempts},
        connect_timeout=connect_timeout,
        read_timeout=read_timeout,
    )
    return boto3.client("s3", config=config, endpoint_url=endpoint_url)


def client_for(settings: Settings, endpoint_url: str | None = None):
    return s3_client(
        settings.s3_addressing_style,
        settings.storage_connect_timeout_s,
        settings.storage_read_timeout_s,
        settings.storage_max_attempts,
        endpoint_url,
    )


class ObjectStore:
    def __init__(self, settings: Settings, endpoint_url: str | None = None):
        self.bucket = settings.s3_bucket
        self._client = client_for(settings, endpoint_url)

    def put(self, key: str, data: bytes, content_type: str) -> None:
        try:
            self._client.put_object(Bucket=self.bucket, Key=key, Body=data, ContentType=content_type)
        except (BotoCoreError, ClientError) as error:
            raise ObjectStoreError(str(error)) from error

    def delete(self, key: str) -> None:
        try:
            self._client.delete_object(Bucket=self.bucket, Key=key)
        except (BotoCoreError, ClientError) as error:
            raise ObjectStoreError(str(error)) from error

    def exists(self, key: str) -> bool:
        try:
            self._client.head_object(Bucket=self.bucket, Key=key)
            return True
        except ClientError as error:
            if error.response.get("Error", {}).get("Code") in ("404", "NoSuchKey", "NotFound"):
                return False
            raise ObjectStoreError(str(error)) from error
        except BotoCoreError as error:
            raise ObjectStoreError(str(error)) from error
