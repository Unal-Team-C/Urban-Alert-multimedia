"""Builders of API Gateway HTTP API (payload v2.0) events, as Lambda receives them in the cloud."""

import base64
import uuid
from types import SimpleNamespace


def multipart(fields: dict[str, str] | None = None, files: dict[str, tuple[str, bytes, str]] | None = None):
    """Encode a multipart/form-data body. Returns (body, content_type)."""
    boundary = f"----urbanalert{uuid.uuid4().hex}"
    parts = []
    for name, value in (fields or {}).items():
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n'.encode() + str(value).encode() + b"\r\n"
        )
    for name, (filename, content, content_type) in (files or {}).items():
        header = (
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'
            f"Content-Type: {content_type}\r\n\r\n"
        )
        parts.append(header.encode() + content + b"\r\n")
    body = b"".join(parts) + f"--{boundary}--\r\n".encode()
    return body, f"multipart/form-data; boundary={boundary}"


def http_event(method: str, path: str, body: bytes = b"", headers: dict[str, str] | None = None) -> dict:
    headers = {key.lower(): value for key, value in (headers or {}).items()}
    if body:
        headers.setdefault("content-length", str(len(body)))
    return {
        "version": "2.0",
        "routeKey": "$default",
        "rawPath": path,
        "rawQueryString": "",
        "headers": headers,
        "requestContext": {
            "accountId": "000000000000",
            "apiId": "local",
            "domainName": "localhost",
            "domainPrefix": "localhost",
            "http": {"method": method, "path": path, "protocol": "HTTP/1.1", "sourceIp": "127.0.0.1", "userAgent": "tests"},
            "requestId": str(uuid.uuid4()),
            "routeKey": "$default",
            "stage": "$default",
            "time": "06/Oct/2026:21:15:42 +0000",
            "timeEpoch": 1791328542000,
        },
        "body": base64.b64encode(body).decode() if body else None,
        "isBase64Encoded": bool(body),
    }


def upload_event(image: bytes, filename: str = "photo.jpg", content_type: str = "image/jpeg", **fields) -> dict:
    body, multipart_type = multipart(fields, {"image": (filename, image, content_type)})
    return http_event("POST", "/api/v1/multimedia/images", body, {"content-type": multipart_type})


def lambda_context() -> SimpleNamespace:
    return SimpleNamespace(
        aws_request_id=str(uuid.uuid4()),
        function_name="multimedia",
        memory_limit_in_mb=512,
        invoked_function_arn="arn:aws:lambda:us-east-1:000000000000:function:multimedia",
        get_remaining_time_in_millis=lambda: 15_000,
    )
