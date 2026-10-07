import json
import logging

from app.config import Settings
from app.logging_setup import JsonFormatter, correlation_id


def test_defaults_match_plan():
    settings = Settings()
    assert settings.max_image_bytes == 3_670_016
    assert settings.multipart_overhead_bytes == 65_536
    assert settings.enable_docs is False
    assert settings.mongodb_max_pool_size == 5


def test_from_env_overrides_and_parses_types(monkeypatch):
    monkeypatch.setenv("MAX_IMAGE_BYTES", "1000")
    monkeypatch.setenv("ENABLE_DOCS", "true")
    monkeypatch.setenv("STORAGE_READ_TIMEOUT_S", "7.5")
    monkeypatch.setenv("S3_BUCKET", "other-bucket")
    monkeypatch.setenv("PUBLIC_IMAGE_BASE_URL", "http://cdn.example/images/")
    settings = Settings.from_env()
    assert settings.max_image_bytes == 1000
    assert settings.enable_docs is True
    assert settings.storage_read_timeout_s == 7.5
    assert settings.s3_bucket == "other-bucket"
    assert settings.public_image_base_url == "http://cdn.example/images"


def _format(message, fields=None):
    record = logging.LogRecord("app", logging.INFO, __file__, 1, message, None, None)
    if fields is not None:
        record.fields = fields
    return json.loads(JsonFormatter().format(record))


def test_log_line_is_json_with_required_fields():
    token = correlation_id.set("abc-123")
    try:
        entry = _format("image stored", {"objectKey": "k.jpg"})
    finally:
        correlation_id.reset(token)
    assert entry["message"] == "image stored"
    assert entry["level"] == "INFO"
    assert entry["correlationId"] == "abc-123"
    assert "awsRequestId" in entry and "timestamp" in entry
    assert entry["objectKey"] == "k.jpg"


def test_image_bytes_never_reach_the_logs():
    entry = _format("upload", {"payload": b"\xff\xd8\xff" * 100, "nested": {"raw": bytearray(10)}})
    assert entry["payload"] == "<300 bytes>"
    assert entry["nested"]["raw"] == "<10 bytes>"
