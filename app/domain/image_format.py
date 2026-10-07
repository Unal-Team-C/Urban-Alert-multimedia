"""Image format detection by content signature (plan D-006, RF-002, RF-004).

The client's file name and declared content type are ignored: only the leading bytes count.
"""

from enum import Enum

JPEG_SIGNATURE = b"\xff\xd8\xff"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class ImageFormat(Enum):
    JPEG = ("image/jpeg", "jpg")
    PNG = ("image/png", "png")

    @property
    def content_type(self) -> str:
        return self.value[0]

    @property
    def extension(self) -> str:
        return self.value[1]


ALLOWED_CONTENT_TYPES = tuple(fmt.content_type for fmt in ImageFormat)


def detect(data: bytes) -> ImageFormat | None:
    """Return the format of an accepted image, or None for anything else (HEIC, AVIF, WebP, PDF…)."""
    if data.startswith(PNG_SIGNATURE):
        return ImageFormat.PNG
    if data.startswith(JPEG_SIGNATURE):
        return ImageFormat.JPEG
    return None
