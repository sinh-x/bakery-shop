"""Address library API routes (DG-385 Phase 2, DG-388 Phase 2).

Endpoints:

- ``GET /api/addresses/autocomplete?q=&customerId=`` — autocomplete
  suggestions returned as a grouped ``{pastOrders, library}`` object
  (DG-388 Phase 2 / FR3 / AC3). ``pastOrders`` lists the caller
  customer's previous door-delivery addresses from past orders (capped
  at 10, F2); ``library`` lists ``address_library`` matches (up to 20),
  with the caller customer's own linked addresses ranked first when
  ``customerId`` is supplied (FR5) and each entry carrying
  ``googleMapsUrl`` so the frontend can auto-bind the link on selection
  (FR2 / AC2). The grouped shape is always returned so the frontend can
  render two labeled sections ("Địa chỉ đã giao" / "Thư viện địa chỉ").
- ``GET /api/addresses/library`` — list all library entries, optional
  ``search`` query for the management screen (FR6 / FR8).
- ``POST /api/addresses/library`` — create a new entry (FR8).
- ``PATCH /api/addresses/library/{id}`` — update display address and/or
  map link (FR8). Returns 409 when the new pair collides with another row.
- ``DELETE /api/addresses/library/{id}`` — hard-delete; ``customer_addresses``
  rows cascade via the v101 FK (FR8).

Normalization (trim, lowercase, strip Vietnamese diacritics) is delegated
to ``baker.services.address_library`` so the matching key derivation is
shared between the autocomplete query and the upsert path (NFR3).
"""

from typing import Optional

from fastapi import APIRouter, HTTPException, Query

from baker.db.connection import get_db
from baker.models.address import (
    AddressLibraryCreate,
    AddressLibraryUpdate,
)
from baker.services.address_library import (
    AUTOCOMPLETE_MIN_QUERY_LEN,
    autocomplete as _autocomplete,
    create_library_entry,
    delete_library_entry,
    get_library_entry,
    list_library,
    list_missing_links,
    update_library_entry,
)

router = APIRouter(prefix="/api/addresses", tags=["addresses"])

ADDRESS_NOT_FOUND_MSG = "Không tìm thấy địa chỉ trong thư viện"


@router.get("/autocomplete")
def autocomplete(
    q: str = Query(..., description="Từ khóa tìm địa chỉ (≥2 ký tự)"),
    customerId: Optional[int] = Query(None, description="ID khách hàng để lấy địa chỉ đã giao + ưu tiên thư viện"),
):
    """Gợi ý địa chỉ theo hai nhóm (DG-388 Phase 2 / FR3 / AC3).

    Trả về đối tượng ``{pastOrders, library}``:

    - ``pastOrders``: các địa chỉ giao tận nơi mà khách hàng đã dùng trong
      đơn trước (raw ``delivery_address`` + ``googleMapsUrl`` gần nhất),
      giới hạn 10 (F2). Rỗng khi không có ``customerId`` hoặc không khớp.
    - ``library``: các mục ``address_library`` khớp, tối đa 20, mỗi mục
      có ``googleMapsUrl`` (FR2/AC2) và ``isCustomerAddress`` (FR5). Khi
      có ``customerId``, địa chỉ của khách đó được xếp trước (FR5).

    Định dạng nhóm luôn cố định để frontend render hai section
    ("Địa chỉ đã giao" / "Thư viện địa chỉ") (FR4). Trả về
    ``{pastOrders: [], library: []}`` khi query quá ngắn.
    """
    if not q or len(q.strip()) < AUTOCOMPLETE_MIN_QUERY_LEN:
        return {"pastOrders": [], "library": []}
    with get_db() as conn:
        return _autocomplete(conn, q, customer_id=customerId)


@router.get("/missing-links")
def missing_links(
    limit: int = Query(100, ge=1, description="Số kết quả tối đa (mặc định 100)"),
):
    """Danh sách địa chỉ giao tận nơi chưa có liên kết Google Maps (FR5/AC6/NFR4).

    Trả về mảng JSON các đối tượng ``{"deliveryAddress", "orderCount"}``
    cho đơn ``delivery_type IN ('door','delivery')`` có ``delivery_address``
    không rỗng nhưng ``google_maps_url`` rỗng/NULL. Nhóm theo raw
    ``delivery_address``, sắp xếp theo ``orderCount`` giảm dần. Read-only
    SELECT — không ghi vào CSDL. Phân trang qua ``?limit=`` (mặc định 100).
    """
    with get_db() as conn:
        return list_missing_links(conn, limit=limit)


@router.get("/library")
def list_library_entries(search: Optional[str] = Query(None, description="Tìm theo địa chỉ")):
    """Danh sách toàn bộ thư viện địa chỉ (FR6/FR8)."""
    with get_db() as conn:
        entries = list_library(conn, search=search)
        return [e.to_api_dict() for e in entries]


@router.post("/library", status_code=201)
def create_library_entry_endpoint(body: AddressLibraryCreate):
    """Tạo một mục địa chỉ mới trong thư viện (FR8)."""
    with get_db() as conn:
        entry = create_library_entry(
            conn,
            display_address=body.displayAddress,
            google_maps_url=body.googleMapsUrl,
        )
        return entry.to_api_dict()


@router.patch("/library/{entry_id}")
def update_library_entry_endpoint(entry_id: int, body: AddressLibraryUpdate):
    """Cập nhật địa chỉ và/hoặc link Google Maps (FR8).

    Trả về 404 khi id không tồn tại; 409 khi cặp (địa chỉ, link) mới trùng
    với một mục khác đã có trong thư viện.
    """
    with get_db() as conn:
        if body.displayAddress is None and body.googleMapsUrl is None:
            entry = get_library_entry(conn, entry_id)
            if not entry:
                raise HTTPException(status_code=404, detail=ADDRESS_NOT_FOUND_MSG)
            return entry.to_api_dict()
        try:
            entry = update_library_entry(
                conn,
                entry_id,
                display_address=body.displayAddress,
                google_maps_url=body.googleMapsUrl,
            )
        except ValueError as exc:
            raise HTTPException(status_code=409, detail=str(exc))
        if not entry:
            raise HTTPException(status_code=404, detail=ADDRESS_NOT_FOUND_MSG)
        return entry.to_api_dict()


@router.delete("/library/{entry_id}")
def delete_library_entry_endpoint(entry_id: int):
    """Xóa một mục khỏi thư viện (FR8). Các liên kết customer_addresses cascade."""
    with get_db() as conn:
        existed = get_library_entry(conn, entry_id)
        if not existed:
            raise HTTPException(status_code=404, detail=ADDRESS_NOT_FOUND_MSG)
        delete_library_entry(conn, entry_id)
        return {"ok": True, "id": entry_id}