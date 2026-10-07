"""Structured JSON logs to stdout with a per-request correlation id (plan D-012, RNF-008)."""

import contextvars
import json
import logging
import sys
from datetime import UTC, datetime

correlation_id: contextvars.ContextVar[str | None] = contextvars.ContextVar("correlation_id", default=None)
aws_request_id: contextvars.ContextVar[str | None] = contextvars.ContextVar("aws_request_id", default=None)


def _safe(value):
    """Never let binary content (image bytes) reach the logs."""
    if isinstance(value, (bytes, bytearray, memoryview)):
        return f"<{len(value)} bytes>"
    if isinstance(value, dict):
        return {key: _safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_safe(item) for item in value]
    return value


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "timestamp": datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "correlationId": correlation_id.get(),
            "awsRequestId": aws_request_id.get(),
        }
        extra = getattr(record, "fields", None)
        if isinstance(extra, dict):
            entry.update(_safe(extra))
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, ensure_ascii=False, default=str)


def configure_logging(level: str = "INFO") -> None:
    """Replace any pre-installed handler (the Lambda runtime adds one) with a JSON handler to stdout."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level.upper())
