"""Response models of the multimedia contract (camelCase JSON, English names, as in Geospatial)."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel


class CamelModel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class Coordinate(CamelModel):
    lat: float
    lon: float


class Capture(CamelModel):
    captured_at: datetime | None
    coordinate: Coordinate | None


class ImageResponse(CamelModel):
    image_id: UUID
    image_url: str
    content_type: str
    size_bytes: int
    uploaded_at: datetime
    capture: Capture | None


class ErrorDetail(BaseModel):
    field: str
    reason: str


class ErrorResponse(BaseModel):
    code: int
    message: str
    details: list[ErrorDetail] | None = None
