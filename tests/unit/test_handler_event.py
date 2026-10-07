"""The Lambda handler answers API Gateway v2 events through Mangum (no storage needed)."""

import json

from app.main import handler
from tests.events import http_event, lambda_context


def test_unknown_route_returns_error_contract_and_correlation_id():
    response = handler(http_event("GET", "/api/v1/multimedia/nothing-here"), lambda_context())
    assert response["statusCode"] == 404
    assert json.loads(response["body"]) == {"code": 404, "message": "Not Found"}
    assert response["headers"]["x-correlation-id"]


def test_correlation_id_is_propagated():
    event = http_event("GET", "/api/v1/multimedia/nothing-here", headers={"X-Correlation-Id": "trace-42"})
    response = handler(event, lambda_context())
    assert response["headers"]["x-correlation-id"] == "trace-42"


def test_docs_are_disabled_by_default():
    for path in ("/docs", "/openapi.json"):
        assert handler(http_event("GET", path), lambda_context())["statusCode"] == 404
