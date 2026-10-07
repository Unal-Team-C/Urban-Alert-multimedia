"""Service settings, read from environment variables (see .env.example).

S3 endpoint and credentials are not here: boto3 reads AWS_ENDPOINT_URL_S3, AWS_REGION and
AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY natively, so the cloud deployment just omits them (plan D-005).
"""

import os
from dataclasses import dataclass, fields, replace
from functools import lru_cache


def _bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    s3_bucket: str = "urbanalert-images"
    s3_addressing_style: str = "auto"
    public_image_base_url: str = "http://localhost:9000/urbanalert-images"
    mongodb_uri: str = "mongodb://localhost:27017"
    mongodb_database: str = "multimedia"
    mongodb_timeout_ms: int = 3000
    mongodb_max_pool_size: int = 5
    max_image_bytes: int = 3_670_016
    multipart_overhead_bytes: int = 65_536
    storage_connect_timeout_s: float = 2
    storage_read_timeout_s: float = 5
    storage_max_attempts: int = 3
    enable_docs: bool = False
    log_level: str = "INFO"

    @classmethod
    def from_env(cls) -> "Settings":
        parsers = {bool: _bool, int: int, float: float, str: str}
        values = {
            field.name: parsers[field.type](os.environ[field.name.upper()])
            for field in fields(cls)
            if field.name.upper() in os.environ
        }
        settings = cls(**values)
        return replace(settings, public_image_base_url=settings.public_image_base_url.rstrip("/"))


@lru_cache
def get_settings() -> Settings:
    return Settings.from_env()
