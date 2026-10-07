"""The versioned contract (docs/openapi.json) matches the code (plan D-011, RNF-009)."""

import json
import re
from pathlib import Path

from app.export_openapi import render

CONTRACT = Path(__file__).resolve().parents[2] / "docs" / "openapi.json"
CAMEL = re.compile(r"^[a-z][a-zA-Z0-9]*$")


def _schema() -> dict:
    return json.loads(render())


def test_versioned_file_matches_the_code():
    assert CONTRACT.read_text(encoding="utf-8") == render(), "run: python -m app.export_openapi docs/openapi.json"


def test_operations_and_status_codes():
    paths = _schema()["paths"]
    upload = paths["/api/v1/multimedia/images"]["post"]
    metadata = paths["/api/v1/multimedia/images/{imageId}/metadata"]["get"]
    assert upload["summary"] == "UploadImage" and metadata["summary"] == "GetImageMetadata"
    assert set(upload["responses"]) == {"201", "400", "413", "415", "503"}
    assert set(metadata["responses"]) == {"200", "404", "503"}


def test_contract_fields_are_camel_case_english():
    schemas = _schema()["components"]["schemas"]
    image = schemas["ImageResponse"]["properties"]
    assert set(image) == {"imageId", "imageUrl", "contentType", "sizeBytes", "uploadedAt", "capture"}
    form = next(name for name in schemas if name.startswith("Body_upload_image"))
    assert set(schemas[form]["properties"]) == {"image", "capturedAt", "lat", "lon"}
    for name in ("ImageResponse", "Capture", "Coordinate", "ErrorResponse"):
        assert all(CAMEL.match(field) for field in schemas[name]["properties"]), name
    assert "HTTPValidationError" not in schemas
