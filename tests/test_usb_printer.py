"""Tests for USB thermal printer module."""

import importlib
import io
import os
import sys
from unittest.mock import patch, mock_open, MagicMock

import pytest
from PIL import Image

sys.path.insert(0, "src")

from baker import usb_printer


class TestPngToTspl:
    """Test PNG to TSPL bitmap conversion."""

    def test_basic_conversion(self):
        """Verify basic TSPL command structure is generated correctly."""
        # Create a simple 576x10 grayscale test image
        img = Image.new("L", (576, 10), 0)  # all black
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        png_bytes = buf.getvalue()

        tspl = usb_printer.png_to_tspl(png_bytes)

        # Verify it contains all required TSPL commands
        tspl_str = tspl.decode("latin-1")
        assert "SIZE 76 mm" in tspl_str
        assert "GAP 3 mm" in tspl_str
        assert "SPEED 3" in tspl_str
        assert "DENSITY 8" in tspl_str
        assert "DIRECTION 0,0" in tspl_str
        assert "CLS" in tspl_str
        assert "BITMAP 0,0,72,10,0," in tspl_str
        assert "PRINT 1,1" in tspl_str

    def test_bitmap_threshold_white(self):
        """White pixels (>= 128) should be bit 1 (no print)."""
        # Create 576x1 image, all white
        img = Image.new("L", (576, 1), 255)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        png_bytes = buf.getvalue()

        tspl = usb_printer.png_to_tspl(png_bytes)
        tspl_str = tspl.decode("latin-1")

        # All bits should be set (white = 1 in TSPL bitmap)
        # The bitmap data follows "BITMAP 0,0,72,1,0,"
        bitmap_start = tspl_str.find("BITMAP 0,0,72,1,0,") + len("BITMAP 0,0,72,1,0,")
        bitmap_end = tspl_str.find("\r\nPRINT")
        bitmap_data = tspl_str[bitmap_start:bitmap_end]

        # Each byte should be 0xFF (all 8 bits set = all white)
        assert all(b == "\xff" for b in bitmap_data)

    def test_bitmap_threshold_black(self):
        """Black pixels (< 128) should be bit 0 (print)."""
        # Create 576x1 image, all black
        img = Image.new("L", (576, 1), 0)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        png_bytes = buf.getvalue()

        tspl = usb_printer.png_to_tspl(png_bytes)
        tspl_str = tspl.decode("latin-1")

        # Each byte should be 0x00 (all bits clear = all black)
        bitmap_start = tspl_str.find("BITMAP 0,0,72,1,0,") + len("BITMAP 0,0,72,1,0,")
        bitmap_end = tspl_str.find("\r\nPRINT")
        bitmap_data = tspl_str[bitmap_start:bitmap_end]

        assert all(b == "\x00" for b in bitmap_data)

    def test_bitmap_threshold_gray(self):
        """Gray pixels at threshold (128) should be treated as white."""
        # Create 576x1 image at threshold
        img = Image.new("L", (576, 1), 128)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        png_bytes = buf.getvalue()

        tspl = usb_printer.png_to_tspl(png_bytes)
        tspl_str = tspl.decode("latin-1")

        # Threshold 128 -> >= 128 = white
        bitmap_start = tspl_str.find("BITMAP 0,0,72,1,0,") + len("BITMAP 0,0,72,1,0,")
        bitmap_end = tspl_str.find("\r\nPRINT")
        bitmap_data = tspl_str[bitmap_start:bitmap_end]

        # All bits should be set (white = 1 at threshold)
        assert all(b == "\xff" for b in bitmap_data)

    def test_mixed_bitmap(self):
        """Test mixed black/white image produces correct bitmap."""
        # Create 576x1: left half black (0), right half white (255)
        img = Image.new("L", (576, 1))
        for x in range(288):
            img.putpixel((x, 0), 0)  # black
        for x in range(288, 576):
            img.putpixel((x, 0), 255)  # white

        buf = io.BytesIO()
        img.save(buf, format="PNG")
        png_bytes = buf.getvalue()

        tspl = usb_printer.png_to_tspl(png_bytes)
        tspl_str = tspl.decode("latin-1")

        bitmap_start = tspl_str.find("BITMAP 0,0,72,1,0,") + len("BITMAP 0,0,72,1,0,")
        bitmap_end = tspl_str.find("\r\nPRINT")
        bitmap_data = tspl_str[bitmap_start:bitmap_end]

        # First 36 bytes should be 0x00 (black), last 36 bytes should be 0xFF (white)
        # But actually, left half = black = bit 0, right half = white = bit 1
        # Left 288 pixels = 36 bytes of 0x00
        # Right 288 pixels = 36 bytes of 0xFF
        assert bitmap_data[:36] == "\x00" * 36
        assert bitmap_data[36:] == "\xff" * 36

    def test_height_mm_calculation(self):
        """Verify height in mm is calculated correctly (height / 8.0)."""
        # Create 80-pixel tall image (80 / 8 = 10 mm)
        img = Image.new("L", (576, 80), 128)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        png_bytes = buf.getvalue()

        tspl = usb_printer.png_to_tspl(png_bytes)
        tspl_str = tspl.decode("latin-1")

        # Should contain "SIZE 76 mm,10.0 mm"
        assert "SIZE 76 mm,10.0 mm" in tspl_str

    def test_crlf_line_endings(self):
        """Verify TSPL commands use CRLF line endings."""
        img = Image.new("L", (576, 10), 0)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        png_bytes = buf.getvalue()

        tspl = usb_printer.png_to_tspl(png_bytes)

        # Should contain CRLF after each command
        assert b"\r\n" in tspl

    def test_invalid_png_raises(self):
        """Invalid PNG data should raise an image decoding error."""
        from PIL import UnidentifiedImageError
        with pytest.raises(UnidentifiedImageError):
            usb_printer.png_to_tspl(b"not a valid png")


class TestOpenPrinter:
    """Test USB printer device opening."""

    @patch("os.open")
    def test_opens_with_default_path(self, mock_os_open):
        """Should open with DEFAULT_DEVICE when no path specified."""
        mock_os_open.return_value = 42
        fd = usb_printer.open_printer()
        mock_os_open.assert_called_once_with(
            usb_printer.DEFAULT_DEVICE,
            os.O_RDWR | os.O_NOCTTY,
        )
        assert fd == 42

    @patch("os.open")
    def test_opens_with_custom_path(self, mock_os_open):
        """Should open with custom path when specified."""
        mock_os_open.return_value = 99
        fd = usb_printer.open_printer("/dev/thermal-printer")
        mock_os_open.assert_called_once_with(
            "/dev/thermal-printer",
            os.O_RDWR | os.O_NOCTTY,
        )
        assert fd == 99

    @patch("os.open")
    def test_raises_file_not_found(self, mock_os_open):
        """Should raise FileNotFoundError when device doesn't exist."""
        mock_os_open.side_effect = FileNotFoundError()
        with pytest.raises(FileNotFoundError):
            usb_printer.open_printer()

    @patch("os.open")
    def test_raises_permission_error(self, mock_os_open):
        """Should raise PermissionError when access denied."""
        mock_os_open.side_effect = PermissionError()
        with pytest.raises(PermissionError):
            usb_printer.open_printer()


class TestPrintReceipt:
    """Test full print receipt flow with mocked USB device."""

    @patch("baker.usb_printer.open_printer")
    @patch("os.write")
    @patch("os.close")
    def test_full_flow_converts_and_writes(self, mock_close, mock_write, mock_open_printer):
        """print_receipt should convert PNG to TSPL and write to device."""
        mock_open_printer.return_value = 7

        # Create a simple test image
        img = Image.new("L", (576, 10), 128)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        png_bytes = buf.getvalue()

        usb_printer.print_receipt(
            device_path="/dev/usb/lp0",
            png_bytes=png_bytes,
        )

        mock_open_printer.assert_called_once_with("/dev/usb/lp0")
        mock_write.assert_called_once()
        mock_close.assert_called_once_with(7)

    @patch("baker.usb_printer.open_printer")
    @patch("os.write")
    @patch("os.close")
    def test_raises_when_no_png_bytes(self, mock_close, mock_write, mock_open_printer):
        """Should raise ValueError when png_bytes is None."""
        with pytest.raises(ValueError, match="png_bytes is required"):
            usb_printer.print_receipt(
                device_path="/dev/usb/lp0",
                png_bytes=None,
            )


class TestCheckPrinterStatus:
    """Test printer status checking."""

    @patch("os.open")
    @patch("os.close")
    def test_returns_true_when_device_accessible(self, mock_close, mock_open):
        """Should return True when device can be opened."""
        mock_open.return_value = 5

        result = usb_printer.check_printer_status("/dev/usb/lp0")

        assert result is True
        mock_open.assert_called_once_with("/dev/usb/lp0", os.O_RDWR | os.O_NOCTTY)
        mock_close.assert_called_once_with(5)

    @patch("os.open")
    def test_returns_false_when_device_not_found(self, mock_open):
        """Should return False when device doesn't exist."""
        mock_open.side_effect = FileNotFoundError()

        result = usb_printer.check_printer_status("/dev/usb/lp0")

        assert result is False

    @patch("os.open")
    def test_returns_false_when_permission_denied(self, mock_open):
        """Should return False when permission denied."""
        mock_open.side_effect = PermissionError()

        result = usb_printer.check_printer_status("/dev/usb/lp0")

        assert result is False


class TestTsplFormatCompliance:
    """Verify TSPL output format matches Dart printer_service.dart exactly."""

    def test_tspl_command_sequence_matches_dart(self):
        """Verify exact command sequence and format from Dart code."""
        # 80px tall image = 10mm height
        img = Image.new("L", (576, 80), 0)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        png_bytes = buf.getvalue()

        tspl = usb_printer.png_to_tspl(png_bytes)
        tspl_str = tspl.decode("latin-1")

        # Exact command sequence from Dart printer_service.dart:
        # SIZE 76 mm,{heightMm} mm
        # GAP 3 mm,0 mm
        # SPEED 3
        # DENSITY 8
        # DIRECTION 0,0
        # CLS
        # BITMAP 0,0,72,{height},0,{bitmap_data}
        # PRINT 1,1

        lines = tspl_str.split("\r\n")
        # Filter out empty lines from split
        lines = [l for l in lines if l]

        assert lines[0] == "SIZE 76 mm,10.0 mm", f"Expected SIZE 76 mm,10.0 mm, got {lines[0]}"
        assert lines[1] == "GAP 3 mm,0 mm", f"Expected GAP 3 mm,0 mm, got {lines[1]}"
        assert lines[2] == "SPEED 3", f"Expected SPEED 3, got {lines[2]}"
        assert lines[3] == "DENSITY 8", f"Expected DENSITY 8, got {lines[3]}"
        assert lines[4] == "DIRECTION 0,0", f"Expected DIRECTION 0,0, got {lines[4]}"
        assert lines[5] == "CLS", f"Expected CLS, got {lines[5]}"
        assert lines[7] == "PRINT 1,1", f"Expected PRINT 1,1, got {lines[7]}"

    def test_bitmap_command_format(self):
        """BITMAP 0,0,72,{height},0, format must be exact."""
        img = Image.new("L", (576, 40), 0)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        png_bytes = buf.getvalue()

        tspl = usb_printer.png_to_tspl(png_bytes)
        tspl_str = tspl.decode("latin-1")

        # 40px = 5.0mm
        assert "SIZE 76 mm,5.0 mm" in tspl_str
        assert "BITMAP 0,0,72,40,0," in tspl_str

    def test_no_extra_commands(self):
        """No additional TSPL commands beyond what's specified."""
        img = Image.new("L", (576, 10), 0)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        png_bytes = buf.getvalue()

        tspl = usb_printer.png_to_tspl(png_bytes)
        tspl_str = tspl.decode("latin-1")

        # Only these commands should be present
        expected_commands = [
            "SIZE", "GAP", "SPEED", "DENSITY", "DIRECTION", "CLS", "BITMAP", "PRINT"
        ]
        for cmd in expected_commands:
            assert cmd in tspl_str

        # Should NOT contain SET, FEED, HOME, or other commands
        unexpected = ["SET", "HOME", "INIT", "OFFSET"]
        for cmd in unexpected:
            assert cmd not in tspl_str


class TestPaperModeEnvValidation:
    """Test PAPER_MODE env var reading and validation (FR1, FR2, NFR1, NFR3)."""

    def test_default_is_label_when_unset(self, monkeypatch):
        """PAPER_MODE defaults to 'label' when env var is unset (FR1/NFR1)."""
        monkeypatch.delenv("PAPER_MODE", raising=False)
        mode = usb_printer._validate_paper_mode_env()
        assert mode == "label"
        assert usb_printer.DEFAULT_PAPER_MODE == "label"

    def test_label_value_accepted(self, monkeypatch):
        """Explicit PAPER_MODE=label is accepted."""
        monkeypatch.setenv("PAPER_MODE", "label")
        assert usb_printer._validate_paper_mode_env() == "label"

    def test_roll_value_accepted(self, monkeypatch):
        """PAPER_MODE=roll is accepted."""
        monkeypatch.setenv("PAPER_MODE", "roll")
        assert usb_printer._validate_paper_mode_env() == "roll"

    def test_whitespace_trimmed(self, monkeypatch):
        """Surrounding whitespace is trimmed before validation."""
        monkeypatch.setenv("PAPER_MODE", "  roll  ")
        assert usb_printer._validate_paper_mode_env() == "roll"

    def test_invalid_value_raises(self, monkeypatch):
        """Invalid PAPER_MODE raises ValueError (FR2/NFR3)."""
        monkeypatch.setenv("PAPER_MODE", "invalid_value")
        with pytest.raises(ValueError, match="Invalid PAPER_MODE"):
            usb_printer._validate_paper_mode_env()

    def test_empty_string_raises(self, monkeypatch):
        """Empty PAPER_MODE string raises (not silently defaulted)."""
        monkeypatch.setenv("PAPER_MODE", "   ")
        with pytest.raises(ValueError, match="Invalid PAPER_MODE"):
            usb_printer._validate_paper_mode_env()

    def test_case_sensitive(self, monkeypatch):
        """PAPER_MODE is case-sensitive — 'Label' is invalid."""
        monkeypatch.setenv("PAPER_MODE", "Label")
        with pytest.raises(ValueError, match="Invalid PAPER_MODE"):
            usb_printer._validate_paper_mode_env()

    def test_module_load_fails_fast_on_invalid_env(self, monkeypatch):
        """Importing usb_printer with invalid PAPER_MODE fails fast (NFR3)."""
        monkeypatch.setenv("PAPER_MODE", "garbage")
        with pytest.raises(ValueError, match="Invalid PAPER_MODE"):
            importlib.reload(usb_printer)
        # Restore valid state for subsequent tests
        monkeypatch.delenv("PAPER_MODE", raising=False)
        importlib.reload(usb_printer)


class TestGetPaperMode:
    """Test get_paper_mode() DB-override precedence (AC6, FR3, NFR2)."""

    def _conn_with_config(self, key=None, value=None, active=1):
        """Build a mock connection row for app_config."""
        conn = MagicMock()
        if key is None:
            conn.execute.return_value.fetchone.return_value = None
        else:
            row = MagicMock()
            row.__getitem__ = lambda self, k: value if k == "config_value" else None
            conn.execute.return_value.fetchone.return_value = row
        return conn

    def test_returns_default_when_no_db_row(self):
        """No DB override → returns env var default."""
        conn = self._conn_with_config()
        assert usb_printer.get_paper_mode(conn) == usb_printer.PAPER_MODE_DEFAULT

    def test_db_roll_overrides_env_default(self):
        """DB override 'roll' takes precedence over env default 'label' (AC6)."""
        conn = self._conn_with_config("paper_mode", "roll")
        assert usb_printer.get_paper_mode(conn) == "roll"

    def test_db_label_overrides_env_roll(self, monkeypatch):
        """DB 'label' overrides even when env default is 'roll'."""
        monkeypatch.setenv("PAPER_MODE", "roll")
        importlib.reload(usb_printer)
        try:
            conn = self._conn_with_config("paper_mode", "label")
            assert usb_printer.get_paper_mode(conn) == "label"
        finally:
            monkeypatch.delenv("PAPER_MODE", raising=False)
            importlib.reload(usb_printer)

    def test_inactive_db_row_ignored(self):
        """Inactive app_config row is ignored → falls back to env default."""
        conn = MagicMock()
        row = MagicMock()
        conn.execute.return_value.fetchone.return_value = row
        # Simulate the query filtering active=1 already handled at SQL level;
        # here we ensure that when fetchone returns None (active=0 filtered out),
        # default is used.
        conn.execute.return_value.fetchone.return_value = None
        assert usb_printer.get_paper_mode(conn) == usb_printer.PAPER_MODE_DEFAULT

    def test_invalid_db_value_falls_back_to_default(self):
        """Corrupt DB value falls back to env default rather than crashing."""
        conn = self._conn_with_config("paper_mode", "corrupt")
        assert usb_printer.get_paper_mode(conn) == usb_printer.PAPER_MODE_DEFAULT
