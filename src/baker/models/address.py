"""Address library models (DG-385 Phase 2).

Pydantic request/response models for the address library CRUD endpoints
(``POST/PATCH /api/addresses/library``) and the autocomplete response shape
(``GET /api/addresses/autocomplete``). Address normalization (trim, lowercase,
strip Vietnamese diacritics) is reused from ``baker.db.schema._strip_diacritics``
so the matching form stays consistent with the rest of the codebase
(NFR3, FR1).

The ``Address`` dataclass mirrors the ``address_library`` table row created in
the v101 migration (Phase 1) and is used by the service layer to materialize
query results before serialization to the API response models.
"""

from dataclasses import dataclass
from typing import Optional

from pydantic import BaseModel, field_validator

from baker.db.schema import _strip_diacritics


def normalize_address(address: str) -> str:
    """Normalize an address for matching.

    Trim leading/trailing whitespace, lowercase, and strip Vietnamese
    diacritics so ``"123 Nguyễn Huệ"`` and ``"123 nguyen hue"`` resolve to
    the same key. The original display text is preserved separately on
    ``address_library.display_address``.

    >>> normalize_address("  123 Nguyễn Huệ  ")
    '123 nguyen hue'
    >>> normalize_address("123 NGUYỄN HUỆ")
    '123 nguyen hue'
    >>> normalize_address("")
    ''
    """
    if not address:
        return ""
    return _strip_diacritics(address.strip())


@dataclass
class Address:
    """Row-level representation of an ``address_library`` entry.

    ``normalized_address`` is the matching key (trim + lowercase +
    diacritics stripped); ``display_address`` is the original user-facing
    text. ``google_maps_url`` is nullable because library entries may exist
    without a known link (FR10).
    """

    id: int
    normalized_address: str
    display_address: str
    google_maps_url: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

    @staticmethod
    def from_row(row) -> "Address":
        return Address(
            id=row["id"],
            normalized_address=row["normalized_address"],
            display_address=row["display_address"],
            google_maps_url=row["google_maps_url"] if "google_maps_url" in row.keys() else None,
            created_at=row["created_at"] if "created_at" in row.keys() else None,
            updated_at=row["updated_at"] if "updated_at" in row.keys() else None,
        )

    def to_api_dict(self) -> dict:
        return {
            "id": self.id,
            "displayAddress": self.display_address,
            "googleMapsUrl": self.google_maps_url,
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
        }


class AddressLibraryCreate(BaseModel):
    """Request body for ``POST /api/addresses/library`` (FR8)."""

    displayAddress: str
    googleMapsUrl: Optional[str] = None

    @field_validator("displayAddress")
    @classmethod
    def not_empty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("Địa chỉ không được để trống")
        return v.strip()


class AddressLibraryUpdate(BaseModel):
    """Request body for ``PATCH /api/addresses/library/{id}`` (FR8).

    Both fields are optional; the endpoint applies only the supplied
    fields. ``displayAddress`` is re-normalized when changed so the
    matching key stays in sync with the display text.
    """

    displayAddress: Optional[str] = None
    googleMapsUrl: Optional[str] = None

    @field_validator("displayAddress")
    @classmethod
    def not_empty(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not v.strip():
            raise ValueError("Địa chỉ không được để trống")
        return v.strip() if v is not None else None


class AutocompleteSuggestion(BaseModel):
    """One entry in the ``GET /api/addresses/autocomplete`` response (FR7/FR2).

    ``googleMapsUrl`` is included so the frontend can auto-bind the link
    when the user selects a suggestion (FR2 / AC2).
    """

    id: int
    displayAddress: str
    googleMapsUrl: Optional[str] = None
    isCustomerAddress: bool = False