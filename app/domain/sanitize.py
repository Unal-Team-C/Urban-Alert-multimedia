"""Remove embedded metadata from stored images without decoding them (plan D-014, RF-017).

Only the structure is rewritten (JPEG segments, PNG chunks); image data is copied byte for byte,
so the visual content does not change. The orientation is the only metadata kept, re-written as a
minimal EXIF block, so portrait photos keep displaying upright.
"""

import struct
import zlib

from app.domain.image_format import PNG_SIGNATURE, ImageFormat

ORIENTATION_TAG = 0x0112
EXIF_HEADER = b"Exif\0\0"
ICC_HEADER = b"ICC_PROFILE\0"

SOI, EOI, SOS = 0xD8, 0xD9, 0xDA
APP0, APP1, APP2, APP14, COM = 0xE0, 0xE1, 0xE2, 0xEE, 0xFE
# Kept: JFIF (APP0), ICC colour profile (APP2 "ICC_PROFILE"), Adobe colour transform (APP14) and every
# non-APP/COM segment (tables, frame and scan headers). Everything else in APP0..APP15/COM is metadata
# (EXIF/XMP in APP1, MPF/FlashPix in APP2, IPTC/Photoshop in APP13, comments...).

PNG_METADATA_CHUNKS = {b"eXIf", b"tEXt", b"zTXt", b"iTXt", b"tIME"}


class MalformedImage(ValueError):
    """The metadata structure is damaged: the image cannot be cleaned safely."""


def strip_metadata(data: bytes, fmt: ImageFormat) -> bytes:
    if fmt is ImageFormat.JPEG:
        return _strip_jpeg(data)
    return _strip_png(data)


# --- EXIF orientation -------------------------------------------------------------------------

def _read_orientation(tiff: bytes) -> int | None:
    """Orientation (2..8) from a TIFF/EXIF block, or None if absent, 1 or unreadable."""
    try:
        order = {b"II": "<", b"MM": ">"}[tiff[:2]]
        (ifd_offset,) = struct.unpack(order + "I", tiff[4:8])
        (count,) = struct.unpack(order + "H", tiff[ifd_offset:ifd_offset + 2])
        for index in range(count):
            entry = tiff[ifd_offset + 2 + 12 * index: ifd_offset + 14 + 12 * index]
            tag, kind, _ = struct.unpack(order + "HHI", entry[:8])
            if tag == ORIENTATION_TAG and kind == 3:
                (value,) = struct.unpack(order + "H", entry[8:10])
                return value if 2 <= value <= 8 else None
    except (KeyError, struct.error):
        return None
    return None


def _orientation_tiff(orientation: int) -> bytes:
    """Big-endian TIFF block with a single IFD0 entry: Orientation (SHORT)."""
    return b"MM\0*" + struct.pack(">IHHHIHHI", 8, 1, ORIENTATION_TAG, 3, 1, orientation, 0, 0)


# --- JPEG -------------------------------------------------------------------------------------

def _keep_jpeg_segment(code: int, payload: bytes) -> bool:
    if code == APP2:
        return payload.startswith(ICC_HEADER)
    if code in (APP0, APP14):
        return True
    return not (APP0 <= code <= 0xEF or code == COM)


def _next_marker(data: bytes, start: int) -> int:
    """Position of the next marker inside entropy-coded data, or -1 if the data is truncated."""
    position = start
    while True:
        index = data.find(b"\xff", position)
        if index == -1 or index + 1 >= len(data):
            return -1
        following = data[index + 1]
        if following == 0x00 or 0xD0 <= following <= 0xD7:  # stuffed byte or restart marker
            position = index + 2
        elif following == 0xFF:  # fill byte
            position = index + 1
        else:
            return index


def _strip_jpeg(data: bytes) -> bytes:
    if not data.startswith(b"\xff\xd8"):
        raise MalformedImage("missing JPEG start of image")
    size = len(data)
    out = bytearray(b"\xff\xd8")
    insert_at = len(out)  # where the minimal EXIF goes: after SOI, or after a leading JFIF APP0
    orientation = None
    position = 2
    first_segment = True
    while position < size:
        if data[position] != 0xFF:
            raise MalformedImage(f"expected a marker at byte {position}")
        while position < size and data[position] == 0xFF:
            position += 1
        if position >= size:
            raise MalformedImage("truncated marker")
        code = data[position]
        position += 1
        if code == EOI:
            out += b"\xff\xd9"  # anything after EOI (MPF secondary images, trailers) is dropped
            break
        if 0xD0 <= code <= 0xD7 or code == 0x01:
            out += bytes((0xFF, code))
            continue
        if position + 2 > size:
            raise MalformedImage("truncated segment length")
        (length,) = struct.unpack(">H", data[position:position + 2])
        if length < 2 or position + length > size:
            raise MalformedImage(f"segment 0x{code:02X} exceeds the file")
        payload = data[position + 2:position + length]
        if code == APP1 and payload.startswith(EXIF_HEADER):
            orientation = orientation or _read_orientation(payload[len(EXIF_HEADER):])
        if _keep_jpeg_segment(code, payload):
            out += bytes((0xFF, code)) + data[position:position + length]
            if first_segment and code == APP0:
                insert_at = len(out)
        first_segment = False
        position += length
        if code == SOS:
            marker = _next_marker(data, position)
            if marker == -1:  # truncated scan: keep it as is (S-7, the image is not decoded)
                out += data[position:]
                break
            out += data[position:marker]
            position = marker
    if orientation:
        exif = EXIF_HEADER + _orientation_tiff(orientation)
        out[insert_at:insert_at] = b"\xff\xe1" + struct.pack(">H", len(exif) + 2) + exif
    return bytes(out)


# --- PNG --------------------------------------------------------------------------------------

def _png_chunk(kind: bytes, body: bytes) -> bytes:
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)


def _strip_png(data: bytes) -> bytes:
    if not data.startswith(PNG_SIGNATURE):
        raise MalformedImage("missing PNG signature")
    size = len(data)
    out = bytearray(PNG_SIGNATURE)
    orientation = None
    insert_at = None
    position = len(PNG_SIGNATURE)
    while position < size:
        if position + 8 > size:
            raise MalformedImage("truncated chunk header")
        (length,) = struct.unpack(">I", data[position:position + 4])
        kind = data[position + 4:position + 8]
        end = position + 12 + length
        if end > size:
            raise MalformedImage(f"chunk {kind!r} exceeds the file")
        if kind == b"eXIf":
            orientation = orientation or _read_orientation(data[position + 8:position + 8 + length])
        if kind not in PNG_METADATA_CHUNKS:
            out += data[position:end]
            if kind == b"IHDR":
                insert_at = len(out)
        position = end
        if kind == b"IEND":  # anything after IEND is dropped
            break
    if orientation and insert_at is not None:
        out[insert_at:insert_at] = _png_chunk(b"eXIf", _orientation_tiff(orientation))
    return bytes(out)
