"""Baker — Bakery shop operations tracker."""

from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("baker")
except PackageNotFoundError:
    __version__ = "0.0.0"
