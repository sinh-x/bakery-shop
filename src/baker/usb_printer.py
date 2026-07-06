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
print_lock = threading.Lock()

# Paper mode configuration
# PAPER_MODE env var: server default for printer paper type.
#   "label" — label paper with gaps (default, backward compatible)
#   "roll"  — continuous roll paper (no fixed length)
# This is a configuration label only — no TSPL command changes.
PAPER_MODES = ("label", "roll")
DEFAULT_PAPER_MODE = "label"
# app_config key for runtime override (DB value takes precedence over env var)
PAPER_MODE_CONFIG_KEY = "paper_mode"

# Trail length configuration (DG-184)
# TRAIL_MM env var: trailing blank paper feed in mm for roll mode.
#   Valid range: 0–200 mm (inclusive). Default: 20 mm.
#   Only applied when paper_mode=roll; ignored in label mode.
TRAIL_MM_MIN = 0
TRAIL_MM_MAX = 200
DEFAULT_TRAIL_MM_VALUE = 20
# app_config key for runtime override (DB value takes precedence over env var)
TRAIL_MM_CONFIG_KEY = "trail_mm"


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


def _validate_trail_mm_env() -> int:
    """Read and validate TRAIL_MM env var at module load (fail fast).

    Defaults to 20 mm when unset. Raises ValueError on invalid value
    (non-integer, out of range 0–200) analogous to PAPER_MODE validation (NFR5).

    Returns:
        Validated trail length in mm as an integer.
    """
    raw = os.environ.get("TRAIL_MM", str(DEFAULT_TRAIL_MM_VALUE)).strip()
    try:
        value = int(raw)
    except ValueError:
        raise ValueError(
            f"Invalid TRAIL_MM={raw!r}: must be an integer "
            f"in range {TRAIL_MM_MIN}–{TRAIL_MM_MAX}."
        ) from None
    if value < TRAIL_MM_MIN or value > TRAIL_MM_MAX:
        raise ValueError(
            f"Invalid TRAIL_MM={value!r}: must be in range "
            f"{TRAIL_MM_MIN}–{TRAIL_MM_MAX}."
        )
    return value


# Server default trail length from env var — validated at import time (fail fast)
DEFAULT_TRAIL_MM = _validate_trail_mm_env()


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


def get_trail_mm(conn) -> int:
    """Return the effective trail length in mm for the current print call.

    DB override (app_config.trail_mm) takes precedence over the env var
    default (FR8). Read on each call so Settings-screen changes take effect
    on the next print without a server restart.

    Args:
        conn: SQLite connection (from get_db() context manager).

    Returns:
        Effective trail length in mm (0–200).
    """
    row = conn.execute(
        "SELECT config_value FROM app_config WHERE config_key = ? AND active = 1",
        (TRAIL_MM_CONFIG_KEY,),
    ).fetchone()
    if row is not None:
        raw = (row["config_value"] or "").strip()
        try:
            value = int(raw)
            if TRAIL_MM_MIN <= value <= TRAIL_MM_MAX:
                return value
        except ValueError:
            pass
    return DEFAULT_TRAIL_MM


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


def png_to_tspl(
    png_bytes: bytes,
    paper_mode: str = DEFAULT_PAPER_MODE,
    trail_mm: int = DEFAULT_TRAIL_MM,
) -> bytes:
    """Convert a receipt PNG image to TSPL BITMAP command bytes.

    Ported from Dart printer_service.dart printImage() method.

    GAP is conditional on paper mode (DG-183): 3 mm for label paper
    (backward compatible) and 0 mm for roll paper (eliminates wasted
    paper after each print on continuous roll stock).

    Args:
        png_bytes: PNG image data (Pillow/Rendered receipt PNG).
        paper_mode: Effective paper mode ("label" or "roll"). Controls the
            TSPL GAP command. Defaults to DEFAULT_PAPER_MODE ("label") for
            backward compatibility when callers do not pass a mode.
        trail_mm: Trail length in mm for blank paper feed after receipt content
            in roll mode (DG-184). Applied as a FEED command after PRINT 1,1
            only when paper_mode=roll and trail_mm > 0. Defaults to
            DEFAULT_TRAIL_MM (20 mm). Ignored in label mode.

    Returns:
        Complete TSPL command bytes ready to send to printer.

    Raises:
        ValueError: If image cannot be decoded or is invalid.
    """
    # Normalize paper mode; treat unknown values as the safe default (label)
    # so a corrupt runtime value never produces a malformed TSPL sequence.
    if paper_mode not in PAPER_MODES:
        paper_mode = DEFAULT_PAPER_MODE

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
    # GAP is conditional on paper mode (DG-183):
    #   label paper — 3 mm gap between labels (backward compatible)
    #   roll paper  — 0 mm gap (continuous roll, no wasted paper)
    gap_mm = 3 if paper_mode == "label" else 0
    tspl_cmd(f"GAP {gap_mm} mm,0 mm")
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

    # Trailing blank paper feed for roll mode (DG-184, FR1, NFR1)
    # Only applied when paper_mode=roll and trail_mm > 0.
    # Label mode is bit-identical to pre-change behavior (FR6).
    if paper_mode == "roll" and trail_mm > 0:
        tspl_cmd(f"FEED {trail_mm} mm")

    return bytes(commands)


def print_receipt(
    device_path: Optional[str] = None,
    png_bytes: Optional[bytes] = None,
    paper_mode: str = DEFAULT_PAPER_MODE,
    trail_mm: int = DEFAULT_TRAIL_MM,
) -> None:
    """Full print flow: convert PNG to TSPL and send to USB printer.

    Serializes access via thread lock (one print job at a time).

    Args:
        device_path: USB device path (default: /dev/usb/lp0).
        png_bytes: PNG image data to print.
        paper_mode: Effective paper mode ("label" or "roll"). Controls the
            TSPL GAP command via png_to_tspl. Defaults to DEFAULT_PAPER_MODE
            for backward compatibility.
        trail_mm: Trail length in mm for blank paper feed after receipt content
            in roll mode (DG-184). Defaults to DEFAULT_TRAIL_MM (20 mm).

    Raises:
        FileNotFoundError: USB device not found.
        PermissionError: Cannot access USB device.
        ValueError: Invalid PNG data.
        OSError: Write to USB device failed.
    """
    if png_bytes is None:
        raise ValueError("png_bytes is required")

    tspl_data = png_to_tspl(png_bytes, paper_mode=paper_mode, trail_mm=trail_mm)

    with print_lock:
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
