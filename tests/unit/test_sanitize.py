import io
import struct

import pytest
from PIL import Image

from app.domain.image_format import ImageFormat
from app.domain.sanitize import MalformedImage, strip_metadata
from tests import samples


def _pixels(data: bytes) -> bytes:
    return Image.open(io.BytesIO(data)).convert("RGB").tobytes()


def _png_chunk_types(data: bytes) -> list[bytes]:
    types, position = [], 8
    while position < len(data):
        (length,) = struct.unpack(">I", data[position:position + 4])
        types.append(data[position + 4:position + 8])
        position += 12 + length
    return types


@pytest.mark.parametrize(
    ("make", "fmt"),
    [(samples.jpeg_with_personal_metadata, ImageFormat.JPEG), (samples.png_with_personal_metadata, ImageFormat.PNG)],
)
def test_personal_metadata_removed_and_pixels_unchanged(make, fmt):
    original = make()
    clean = strip_metadata(original, fmt)
    for personal in samples.PERSONAL_STRINGS:
        assert personal not in clean
    assert b"Juan Perez" not in clean
    exif = Image.open(io.BytesIO(clean)).getexif()
    assert dict(exif) == {0x0112: 6}  # only the orientation survives (HU-3.6)
    assert not exif.get_ifd(samples.GPS_IFD)  # no GPS (HU-3.5)
    assert _pixels(clean) == _pixels(original)
    assert len(clean) < len(original)


def test_jpeg_without_orientation_keeps_no_exif_at_all():
    clean = strip_metadata(samples.jpeg_with_personal_metadata(orientation=None), ImageFormat.JPEG)
    assert b"Exif" not in clean
    assert dict(Image.open(io.BytesIO(clean)).getexif()) == {}


def test_jpeg_xmp_comment_iptc_and_trailing_image_removed():
    clean = strip_metadata(samples.jpeg_with_personal_metadata(), ImageFormat.JPEG)
    image = Image.open(io.BytesIO(clean))
    assert "xmp" not in image.info and "comment" not in image.info
    assert b"8BIM" not in clean
    assert clean.endswith(b"\xff\xd9") and clean.count(b"\xff\xd8") == 1


def test_png_metadata_chunks_removed():
    clean = strip_metadata(samples.png_with_personal_metadata(), ImageFormat.PNG)
    kinds = _png_chunk_types(clean)
    assert not {b"tEXt", b"zTXt", b"iTXt", b"tIME"} & set(kinds)
    assert kinds.count(b"eXIf") == 1  # minimal one, orientation only
    assert kinds[-1] == b"IEND" and clean.endswith(b"IEND\xaeB`\x82")


@pytest.mark.parametrize(("data", "fmt"), [(samples.jpeg(), ImageFormat.JPEG), (samples.png(), ImageFormat.PNG)])
def test_images_without_metadata_are_unchanged(data, fmt):
    assert strip_metadata(data, fmt) == data


def test_padding_after_end_of_image_is_dropped():
    assert strip_metadata(samples.jpeg(size=50_000), ImageFormat.JPEG) == samples.jpeg()


def test_truncated_scan_is_kept_as_is():
    data = samples.jpeg()
    scan_start = data.index(b"\xff\xda")
    truncated = data[: (scan_start + len(data)) // 2]  # cut in the middle of the entropy-coded data
    assert strip_metadata(truncated, ImageFormat.JPEG) == truncated


@pytest.mark.parametrize(
    ("data", "fmt"),
    [
        (samples.jpeg_with_personal_metadata()[:40], ImageFormat.JPEG),  # APP1 cut in the middle
        (b"\xff\xd8\xff\xe1\x00\x01", ImageFormat.JPEG),  # length < 2
        (b"\xff\xd8\x00\x00", ImageFormat.JPEG),  # not a marker
        (samples.png()[:20], ImageFormat.PNG),  # IHDR cut
        (samples.png()[:8] + struct.pack(">I", 10_000) + b"tEXt" + b"x", ImageFormat.PNG),
    ],
)
def test_damaged_structure_is_rejected(data, fmt):
    with pytest.raises(MalformedImage):
        strip_metadata(data, fmt)
