"""USB thermal printer module for Baker API.

Converts receipt PNG images to TSPL commands and sends them to the Y41BT
printer via USB (using usblp kernel module at /dev/usb/lp0).
"""

import io
import os
import threading
from typing import Optional

from PIL import Image

# Default USB printer device path (override with USB_PRINTER_DEVICE env var)
DEFAULT_DEVICE = "/dev/usb/lp0"

# TSPL constants matching Dart printer_service.dart
PRINT_WIDTH = 576  # dots (72 bytes)
WIDTH_BYTES = PRINT_WIDTH // 8  # 72 bytes per row
THRESHOLD = 128  # 1-bit bitmap threshold

# Thread lock for serializing print requests
_print_lock = threading.Lock()

# Paper mode configuration
# PAPER_MODE env var: server default for printer paper type.
#   "label" — label paper with gaps (default, backward compatible)
#   "roll"  — continuous roll paper (no fixed length)
# This is a configuration label only — no TSPL command changes.
PAPER_MODES = ("label", "roll")
DEFAULT_PAPER_MODE = "label"
# app_config key for runtime override (DB value takes precedence over env var)
PAPER_MODE_CONFIG_KEY = "paper_mode"


def _validate_paper_mode_env() -> str:
    """Read and validate PAPER_MODE env var at module load (fail fast).

    Defaults to "label" when unset (backward compatible, FR1/NFR1).
    Raises ValueError on invalid value (FR2/NFR3) within 1 second of config load.
    """
    raw = os.environ.get("PAPER_MODE", DEFAULT_PAPER_MODE).strip()
    if raw not in PAPER_MODES:
        raise ValueError(
            f"Invalid PAPER_MODE={raw!r}: must be one of {PAPER_MODES}. "
            f"Valid values: 'label' (default) or 'roll'."
        )
    return raw


# Server default paper mode from env var — validated at import time (fail fast)
PAPER_MODE_DEFAULT = _validate_paper_mode_env()


def get_paper_mode(conn) -> str:
    """Return the effective paper mode for the current print/status call.

    DB override (app_config.paper_mode) takes precedence over the env var
    default (AC6). Read on each call so Settings-screen changes take effect
    on the next print without a server restart (NFR2).

    Args:
        conn: SQLite connection (from get_db() context manager).

    Returns:
        Effective paper mode: "label" or "roll".
    """
    row = conn.execute(
        "SELECT config_value FROM app_config WHERE config_key = ? AND active = 1",
        (PAPER_MODE_CONFIG_KEY,),
    ).fetchone()
    if row is not None:
        value = (row["config_value"] or "").strip()
        if value in PAPER_MODES:
            return value
    return PAPER_MODE_DEFAULT


def open_printer(device_path: Optional[str] = None) -> int:
    """Open USB printer device and return file descriptor.

    Args:
        device_path: USB device path (default: /dev/usb/lp0)

    Returns:
        File descriptor for the opened device.

    Raises:
        FileNotFoundError: Device does not exist.
        PermissionError: Cannot open device (check permissions or group membership).
    """
    path = device_path or DEFAULT_DEVICE
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY)
    return fd


def png_to_tspl(png_bytes: bytes) -> bytes:
    """Convert a receipt PNG image to TSPL BITMAP command bytes.

    Ported from Dart printer_service.dart printImage() method.

    Args:
        png_bytes: PNG image data (Pillow/Rendered receipt PNG).

    Returns:
        Complete TSPL command bytes ready to send to printer.

    Raises:
        ValueError: If image cannot be decoded or is invalid.
    """
    # Decode PNG
    img = Image.open(io.BytesIO(png_bytes))
    if img is None:
        raise ValueError("Failed to decode PNG image")

    # Resize to 576px width, maintain aspect ratio
    resized = img.resize((PRINT_WIDTH, img.height), Image.LANCZOS)

    # Convert to grayscale (mode 'L')
    grayscale = resized.convert("L")

    height = grayscale.height

    # Convert to 1-bit bitmap — threshold 128
    # TSPL: bit 1 = white (no print), bit 0 = black (print)
    # MSB first: bit 7 is leftmost pixel
    bitmap_data = bytearray(WIDTH_BYTES * height)
    offset = 0
    for y in range(height):
        for x_byte in range(WIDTH_BYTES):
            byte = 0
            for bit in range(8):
                x = x_byte * 8 + bit
                if x < PRINT_WIDTH:
                    pixel = grayscale.getpixel((x, y))
                    if pixel >= THRESHOLD:
                        byte |= (0x80 >> bit)
            bitmap_data[offset] = byte
            offset += 1

    # Label height in mm (203 DPI ≈ 8 dots/mm)
    height_mm = (height / 8.0)

    # Build TSPL command sequence
    commands = bytearray()

    def tspl_cmd(cmd: str) -> None:
        nonlocal commands
        commands.extend(cmd.encode("ascii"))
        commands.extend(b"\r\n")

    tspl_cmd(f"SIZE 76 mm,{height_mm:.1f} mm")
    tspl_cmd("GAP 3 mm,0 mm")
    tspl_cmd("SPEED 3")
    tspl_cmd("DENSITY 8")
    tspl_cmd("DIRECTION 0,0")
    tspl_cmd("CLS")

    # BITMAP command: BITMAP 0,0,72,{height},0,{bitmap_data}
    bitmap_header = f"BITMAP 0,0,{WIDTH_BYTES},{height},0,".encode("ascii")
    commands.extend(bitmap_header)
    commands.extend(bitmap_data)
    commands.extend(b"\r\n")

    tspl_cmd("PRINT 1,1")

    return bytes(commands)


def print_receipt(
    device_path: Optional[str] = None,
    png_bytes: Optional[bytes] = None,
) -> None:
    """Full print flow: convert PNG to TSPL and send to USB printer.

    Serializes access via thread lock (one print job at a time).

    Args:
        device_path: USB device path (default: /dev/usb/lp0).
        png_bytes: PNG image data to print.

    Raises:
        FileNotFoundError: USB device not found.
        PermissionError: Cannot access USB device.
        ValueError: Invalid PNG data.
        OSError: Write to USB device failed.
    """
    if png_bytes is None:
        raise ValueError("png_bytes is required")

    tspl_data = png_to_tspl(png_bytes)

    with _print_lock:
        fd = None
        try:
            fd = open_printer(device_path)
            # Write all TSPL data in one call
            os.write(fd, tspl_data)
        finally:
            if fd is not None:
                os.close(fd)


def check_printer_status(device_path: Optional[str] = None) -> bool:
    """Check if the USB printer device is accessible.

    Args:
        device_path: USB device path (default: /dev/usb/lp0).

    Returns:
        True if device exists and is accessible, False otherwise.
    """
    path = device_path or DEFAULT_DEVICE
    try:
        fd = os.open(path, os.O_RDWR | os.O_NOCTTY)
        os.close(fd)
        return True
    except (FileNotFoundError, PermissionError, OSError):
        return False
