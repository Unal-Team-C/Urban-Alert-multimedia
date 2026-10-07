import pytest

from app.domain.image_format import ImageFormat, detect
from tests import samples


def test_jpeg_detected():
    assert detect(samples.jpeg()) is ImageFormat.JPEG
    assert ImageFormat.JPEG.content_type == "image/jpeg"
    assert ImageFormat.JPEG.extension == "jpg"


def test_png_detected():
    assert detect(samples.png()) is ImageFormat.PNG
    assert ImageFormat.PNG.content_type == "image/png"


def test_padded_samples_keep_signature_and_exact_size():
    assert len(samples.jpeg(size=3 * samples.MB)) == 3 * samples.MB
    assert len(samples.png(size=2 * samples.MB)) == 2 * samples.MB
    assert detect(samples.png(size=2 * samples.MB)) is ImageFormat.PNG


@pytest.mark.parametrize("make", [samples.heic, samples.avif, samples.webp, samples.pdf, samples.exe])
def test_other_formats_rejected(make):
    assert detect(make()) is None


def test_exe_named_jpg_is_rejected_by_content():
    # The name / declared type never reach detect(): only bytes count.
    assert detect(samples.exe()) is None


@pytest.mark.parametrize("data", [b"", b"\xff", b"\xff\xd8", b"\x89PNG\r\n"])
def test_empty_or_truncated_rejected(data):
    assert detect(data) is None
