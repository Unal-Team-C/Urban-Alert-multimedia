"""One-off admin process (12-factor XII, plan D-010): bucket, bucket policy and Mongo indexes.

Idempotent. Locally, run by the `init` compose service before the function starts:
    python -m app.admin.init_resources
In AWS, `handler` runs as the function urban-alert-multimedia-init, invoked by the Provision workflow before
the gateway routes are published. It only creates the indexes: the bucket and its policy belong to Terraform
(spec 002 RF-007, plan D-007).
"""

import json
import logging

from botocore.exceptions import ClientError

from app.config import Settings, get_settings
from app.logging_setup import configure_logging
from app.storage.metadata import collection_for
from app.storage.objects import client_for

logger = logging.getLogger("app.admin.init_resources")


def bucket_policy(bucket: str) -> dict:
    """Anonymous read of single objects only: no ListBucket, no writes (plan D-007, RF-009)."""
    return {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {"AWS": ["*"]},
                "Action": ["s3:GetObject"],
                "Resource": [f"arn:aws:s3:::{bucket}/*"],
            }
        ],
    }


def ensure_bucket(s3, bucket: str) -> None:
    try:
        s3.head_bucket(Bucket=bucket)
    except ClientError as error:
        if error.response.get("Error", {}).get("Code") not in ("404", "NoSuchBucket", "NotFound"):
            raise
        s3.create_bucket(Bucket=bucket)
        logger.info("bucket created", extra={"fields": {"bucket": bucket}})
    s3.put_bucket_policy(Bucket=bucket, Policy=json.dumps(bucket_policy(bucket)))


def ensure_indexes(collection) -> list[str]:
    return [collection.create_index("objectKey", unique=True, name="objectKey_unique")]


def ensure_all(settings: Settings) -> None:
    ensure_bucket(client_for(settings), settings.s3_bucket)
    ensure_indexes(collection_for(settings))
    logger.info(
        "resources ready",
        extra={"fields": {"bucket": settings.s3_bucket, "database": settings.mongodb_database}},
    )


def main() -> None:
    settings = get_settings()
    configure_logging(settings.log_level)
    ensure_all(settings)


def handler(event, context) -> dict:
    """Lambda entry point (urban-alert-multimedia-init)."""
    settings = get_settings()
    configure_logging(settings.log_level)
    indexes = ensure_indexes(collection_for(settings))
    logger.info("indexes ready", extra={"fields": {"database": settings.mongodb_database, "indexes": indexes}})
    return {"indexes": indexes}


if __name__ == "__main__":
    main()
