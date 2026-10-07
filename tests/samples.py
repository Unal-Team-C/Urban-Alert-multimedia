"""Test file generators: real JPEG/PNG images (Pillow) padded to an exact size, and foreign headers."""

import io
import struct
import zlib

from PIL import Image

MB = 1024 * 1024


def _image(width: int = 32, height: int = 16) -> Image.Image:
    image = Image.new("RGB", (width, height))
    image.putdata([((x * 8) % 256, (y * 16) % 256, 128) for y in range(height) for x in range(width)])
    return image


def _png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def jpeg(size: int | None = None, **save_options) -> bytes:
    """A decodable JPEG. With `size`, padded with bytes after EOI (ignored by decoders) to exactly `size`."""
    buffer = io.BytesIO()
    _image().save(buffer, "JPEG", quality=90, **save_options)
    return _pad(buffer.getvalue(), size)


def png(size: int | None = None, extra_chunks: list[tuple[bytes, bytes]] = (), **save_options) -> bytes:
    """A decodable PNG. Extra chunks go before IDAT; with `size`, padded with a private ancillary chunk."""
    buffer = io.BytesIO()
    _image().save(buffer, "PNG", **save_options)
    data = buffer.getvalue()
    if extra_chunks:
        ihdr_end = 8 + 25
        data = data[:ihdr_end] + b"".join(_png_chunk(kind, body) for kind, body in extra_chunks) + data[ihdr_end:]
    if size is None:
        return data
    padding = size - len(data) - 12
    assert padding >= 0, "size too small for a padded PNG"
    iend = data.rindex(b"IEND") - 4
    return data[:iend] + _png_chunk(b"paDd", b"\0" * padding) + data[iend:]


def _pad(data: bytes, size: int | None) -> bytes:
    if size is None:
        return data
    assert size >= len(data), "size too small"
    return data + b"\0" * (size - len(data))


def heic(size: int = 1024) -> bytes:
    return _pad(b"\0\0\0\x18ftypheic\0\0\0\0mif1heic", size)


def avif(size: int = 1024) -> bytes:
    return _pad(b"\0\0\0\x1cftypavif\0\0\0\0avifmif1miaf", size)


def webp(size: int = 1024) -> bytes:
    return _pad(b"RIFF\0\0\0\0WEBPVP8 ", size)


def pdf(size: int = 1024) -> bytes:
    return _pad(b"%PDF-1.7\n", size)


def exe(size: int = 1024) -> bytes:
    return _pad(b"MZ\x90\0\x03\0\0\0", size)


# --- Images with personal metadata (RF-017) ------------------------------------------------------

GPS_IFD = 0x8825
PERSONAL_STRINGS = (b"iPhone 15 Pro", b"Juan Perez", b"2026:10:06 16:12:05", b"secret-xmp", b"Photoshop 3.0")


def personal_exif(orientation: int | None = 6) -> Image.Exif:
    """EXIF with GPS, capture date, device and author, as a phone camera would write it."""
    exif = Image.Exif()
    exif[0x010F] = "Apple"
    exif[0x0110] = "iPhone 15 Pro"
    exif[0x013B] = "Juan Perez"
    exif[0x0132] = "2026:10:06 16:12:05"
    if orientation is not None:
        exif[0x0112] = orientation
    exif.get_ifd(GPS_IFD).update({1: "N", 2: (4.0, 36.0, 35.0), 3: "W", 4: (74.0, 4.0, 54.0)})
    return exif


def jpeg_with_personal_metadata(orientation: int | None = 6) -> bytes:
    """JPEG with EXIF (GPS, date, device, author), XMP, a comment, IPTC (APP13) and a trailing
    MPF-style secondary image after EOI that carries its own EXIF."""
    xmp = b'<x:xmpmeta xmlns:x="adobe:ns:meta/">secret-xmp</x:xmpmeta>'
    data = jpeg(exif=personal_exif(orientation).tobytes(), xmp=xmp, comment=b"Juan Perez comment")
    iptc = b"Photoshop 3.0\0" + b"8BIM\x04\x04\0\0\0\0\0\x0aJuan Perez"
    app13 = b"\xff\xed" + struct.pack(">H", len(iptc) + 2) + iptc
    secondary = jpeg(exif=personal_exif(None).tobytes())
    return data[:2] + app13 + data[2:] + secondary


def png_with_personal_metadata(orientation: int | None = 6) -> bytes:
    from PIL.PngImagePlugin import PngInfo

    info = PngInfo()
    info.add_text("Author", "Juan Perez")
    info.add_itxt("XML:com.adobe.xmp", "secret-xmp")
    return png(pnginfo=info, exif=personal_exif(orientation).tobytes()) + b"trailing Juan Perez"
