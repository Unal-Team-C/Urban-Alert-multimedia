"""Endpoints of /api/v1/multimedia."""

from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, Path, Request, Response, UploadFile
from starlette.concurrency import run_in_threadpool

from app.api.schemas import ErrorResponse, ImageResponse
from app.service import ImageService
from app.storage.metadata import MetadataStore
from app.storage.objects import ObjectStore

PREFIX = "/api/v1/multimedia"
UPLOAD_PATH = f"{PREFIX}/images"

router = APIRouter(prefix=PREFIX, tags=["multimedia"])


def get_service(request: Request) -> ImageService:
    settings = request.app.state.settings
    return ImageService(settings, ObjectStore(settings), MetadataStore(settings))


def _errors(*codes: int) -> dict:
    return {code: {"model": ErrorResponse} for code in codes}


@router.post(
    "/images",
    status_code=201,
    response_model=ImageResponse,
    summary="UploadImage",
    description=(
        "Stores a JPEG or PNG image (max 3,670,016 bytes) with optional capture data and returns its "
        "definitive URL. Embedded metadata (EXIF, XMP, IPTC) is removed; only the orientation is kept."
    ),
    responses=_errors(400, 413, 415, 503),
)
async def upload_image(
    response: Response,
    service: Annotated[ImageService, Depends(get_service)],
    image: Annotated[UploadFile, File(description="JPEG or PNG image")],
    captured_at: Annotated[str | None, Form(alias="capturedAt", description="ISO 8601 with UTC offset")] = None,
    lat: Annotated[str | None, Form(description="Capture latitude, sent together with lon")] = None,
    lon: Annotated[str | None, Form(description="Capture longitude, sent together with lat")] = None,
) -> ImageResponse:
    data = await image.read()
    document = await run_in_threadpool(service.upload_image, data, captured_at, lat, lon)
    response.headers["Location"] = f"{PREFIX}/images/{document['_id']}/metadata"
    return service.to_response(document)


@router.get(
    "/images/{imageId}/metadata",
    response_model=ImageResponse,
    summary="GetImageMetadata",
    description="Returns the metadata of a stored image. The image itself is read from its imageUrl.",
    responses=_errors(404, 503),
)
async def get_image_metadata(
    image_id: Annotated[str, Path(alias="imageId", description="Image id (UUID) returned by UploadImage")],
    service: Annotated[ImageService, Depends(get_service)],
) -> ImageResponse:
    document = await run_in_threadpool(service.get_metadata, image_id)
    return service.to_response(document)
