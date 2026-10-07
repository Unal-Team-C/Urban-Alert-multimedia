"""Upload orchestration (plan §4): validate → strip metadata → store object → store metadata."""

import logging
from datetime import UTC, datetime, timedelta, timezone
from uuid import UUID, uuid4

from app.api.errors import ImageNotFound, ImageTooLarge, InvalidParameter, StorageUnavailable, UnsupportedImageFormat
from app.api.schemas import Capture, Coordinate, ErrorDetail, ImageResponse
from app.config import Settings
from app.domain import capture as capture_rules
from app.domain.image_format import ALLOWED_CONTENT_TYPES, detect
from app.domain.sanitize import MalformedImage, strip_metadata
from app.storage.metadata import MetadataStore, MetadataStoreError
from app.storage.objects import ObjectStore, ObjectStoreError

logger = logging.getLogger(__name__)


def _millis(value: datetime) -> datetime:
    """MongoDB stores milliseconds: truncate so the response matches what is stored."""
    return value.replace(microsecond=value.microsecond // 1000 * 1000)


def _utc_now() -> datetime:
    return datetime.now(UTC)


class ImageService:
    def __init__(self, settings: Settings, objects: ObjectStore, metadata: MetadataStore, clock=_utc_now):
        self.settings = settings
        self.objects = objects
        self.metadata = metadata
        self.clock = clock

    def upload_image(self, data: bytes, captured_at: str | None, lat: str | None, lon: str | None) -> dict:
        if not data:
            raise InvalidParameter([ErrorDetail(field="image", reason="must not be empty")])
        max_bytes = self.settings.max_image_bytes
        if len(data) > max_bytes:
            raise ImageTooLarge([ErrorDetail(field="image", reason=f"maximum size is {max_bytes} bytes")])
        fmt = detect(data)
        if fmt is None:
            raise UnsupportedImageFormat(
                [ErrorDetail(field="image", reason=f"allowed formats: {', '.join(ALLOWED_CONTENT_TYPES)}")]
            )
        now = _millis(self.clock())
        try:
            capture = capture_rules.parse(captured_at, lat, lon, now)
        except capture_rules.InvalidCapture as error:
            raise InvalidParameter([ErrorDetail(field=error.field, reason=error.reason)]) from None
        try:
            clean = strip_metadata(data, fmt)
        except MalformedImage as error:
            raise UnsupportedImageFormat([ErrorDetail(field="image", reason=f"damaged image structure: {error}")]) from None

        image_id = str(uuid4())
        object_key = f"{image_id}.{fmt.extension}"
        document = {
            "_id": image_id,
            "objectKey": object_key,
            "contentType": fmt.content_type,
            "sizeBytes": len(clean),
            "uploadedAt": now,
            "capture": self._capture_document(capture),
        }
        try:
            self.objects.put(object_key, clean, fmt.content_type)
        except ObjectStoreError as error:
            logger.error("object storage unavailable", extra={"fields": {"objectKey": object_key, "error": str(error)}})
            raise StorageUnavailable() from None
        try:
            self.metadata.insert(document)
        except MetadataStoreError as error:
            logger.error("metadata storage unavailable", extra={"fields": {"objectKey": object_key, "error": str(error)}})
            self._compensate(object_key)
            raise StorageUnavailable() from None
        logger.info(
            "image stored",
            extra={"fields": {"imageId": image_id, "objectKey": object_key, "sizeBytes": len(clean), "receivedBytes": len(data)}},
        )
        return document

    def get_metadata(self, image_id: str) -> dict:
        try:
            canonical = str(UUID(image_id))
        except ValueError:
            raise ImageNotFound() from None
        try:
            document = self.metadata.find(canonical)
        except MetadataStoreError as error:
            logger.error("metadata storage unavailable", extra={"fields": {"imageId": canonical, "error": str(error)}})
            raise StorageUnavailable() from None
        if document is None:
            raise ImageNotFound()
        return document

    def _compensate(self, object_key: str) -> None:
        """RF-016: an object without its metadata document must not remain."""
        try:
            self.objects.delete(object_key)
        except ObjectStoreError as error:
            # Left for the deferred orphan cleanup (HU-6): the key was never returned and is unguessable.
            logger.error("compensation failed: orphan object", extra={"fields": {"objectKey": object_key, "error": str(error)}})

    @staticmethod
    def _capture_document(capture: capture_rules.Capture | None) -> dict | None:
        if capture is None:
            return None
        return {
            "capturedAt": _millis(capture.captured_at.astimezone(UTC)) if capture.captured_at else None,
            "utcOffsetMinutes": capture.utc_offset_minutes,
            "coordinate": {"lat": capture.lat, "lon": capture.lon} if capture.lat is not None else None,
        }

    def to_response(self, document: dict) -> ImageResponse:
        capture = document.get("capture")
        response_capture = None
        if capture is not None:
            captured_at = capture.get("capturedAt")
            if captured_at is not None:
                offset = timezone(timedelta(minutes=capture.get("utcOffsetMinutes") or 0))
                captured_at = captured_at.astimezone(offset)
            coordinate = capture.get("coordinate")
            response_capture = Capture(
                captured_at=captured_at,
                coordinate=Coordinate(**coordinate) if coordinate else None,
            )
        return ImageResponse(
            image_id=document["_id"],
            image_url=f"{self.settings.public_image_base_url}/{document['objectKey']}",
            content_type=document["contentType"],
            size_bytes=document["sizeBytes"],
            uploaded_at=document["uploadedAt"],
            capture=response_capture,
        )
