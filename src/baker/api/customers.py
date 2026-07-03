"""Customer management API routes (DG-182 Phase 1, DG-205 Phase 2)."""

from typing import Optional

from fastapi import APIRouter, HTTPException, Query

_BS = "\\"


def _escape_like(value: str) -> str:
    return value.replace("%", _BS + "%").replace("_", _BS + "_")
from pydantic import BaseModel, field_validator, model_validator

from baker.db.connection import get_db
from baker.models.customer import (
    Customer,
    _load_customer_phones_for_many,
    _primary_phone,
    load_year_summary,
)
from baker.models.order import Order


router = APIRouter(prefix="/api/customers", tags=["customers"])


class PhoneInput(BaseModel):
    phone: str
    isPrimary: bool = False

    @field_validator("phone")
    @classmethod
    def normalize(cls, v: str) -> str:
        return (v or "").strip()


class CustomerCreate(BaseModel):
    name: str
    phone: str = ""
    phones: Optional[list[PhoneInput]] = None

    @field_validator("name")
    @classmethod
    def name_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Tên khách hàng không được để trống")
        return v.strip()

    @field_validator("phone")
    @classmethod
    def normalize_phone(cls, v: str) -> str:
        return (v or "").strip()

    @model_validator(mode="after")
    def resolve_phones(self) -> "CustomerCreate":
        if self.phones is None:
            if self.phone:
                self.phones = [PhoneInput(phone=self.phone, isPrimary=True)]
            else:
                self.phones = []
        elif self.phones:
            if not any(p.isPrimary for p in self.phones):
                raise ValueError("Ít nhất một số điện thoại phải là số chính (isPrimary=true)")
        return self


class CustomerUpdate(BaseModel):
    name: Optional[str] = None
    phone: Optional[str] = None
    phones: Optional[list[PhoneInput]] = None

    @field_validator("name")
    @classmethod
    def name_not_empty(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not v.strip():
            raise ValueError("Tên khách hàng không được để trống")
        return v.strip() if v is not None else None

    @field_validator("phone")
    @classmethod
    def normalize_phone(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        return v.strip()

    @model_validator(mode="after")
    def resolve_phones(self) -> "CustomerUpdate":
        if self.phones is not None and self.phones:
            if not any(p.isPrimary for p in self.phones):
                raise ValueError("Ít nhất một số điện thoại phải là số chính (isPrimary=true)")
        return self


def _phones_to_dicts(phones: Optional[list[PhoneInput]]) -> list[dict]:
    if phones is None:
        return []
    return [{"phone": p.phone, "isPrimary": p.isPrimary} for p in phones]


def _find_customers_sharing_phone(conn, phone: str, exclude_id: int) -> list[dict]:
    """Return other customers sharing the given phone (excluding exclude_id)."""
    if not phone:
        return []
    # M-1: stored phones are normalized, so normalize the search value too.
    from baker.db.schema import _normalize_phone

    nphone = _normalize_phone(phone)
    if not nphone:
        return []
    rows = conn.execute(
        "SELECT DISTINCT c.* FROM customers c "
        "JOIN customer_phones cp ON cp.customer_id = c.id "
        "WHERE cp.phone = ? AND cp.phone != '' AND c.id != ? "
        "ORDER BY c.id",
        (nphone, exclude_id),
    ).fetchall()
    return [Customer.from_row(r, conn).to_api_dict() for r in rows]


def _customer_response(conn, customer: Customer) -> dict:
    """Build API response including phone-sharing visibility (FR2a) and phones array (FR6)."""
    result = customer.to_api_dict()
    result["sharedPhoneCustomers"] = _find_customers_sharing_phone(
        conn, customer.phone, customer.id
    )
    return result


@router.get("")
def list_customers(search: Optional[str] = Query(None, description="Tìm theo tên hoặc SĐT")):
    """Danh sách khách hàng, hỗ trợ tìm kiếm partial theo tên/SĐT (FR1, FR7)."""
    with get_db() as conn:
        if search and search.strip():
            escaped = _escape_like(search.strip())
            like = f"%{escaped}%"
            rows = conn.execute(
                "SELECT DISTINCT c.* FROM customers c "
                "LEFT JOIN customer_phones cp ON cp.customer_id = c.id "
                "WHERE c.name LIKE ? OR c.phone LIKE ? OR cp.phone LIKE ? "
                "ORDER BY c.id DESC",
                (like, like, like),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM customers ORDER BY id DESC"
            ).fetchall()
        # Mn-3: batch-load phones for all returned customers in a single query
        # instead of one query per customer via Customer.from_row(r, conn).
        customers = [Customer.from_row(r) for r in rows]
        phones_map = _load_customer_phones_for_many(conn, [c.id for c in customers if c.id is not None])
        for c in customers:
            if c.id is not None and c.id in phones_map:
                c.phones = phones_map[c.id]
        return [c.to_api_dict() for c in customers]


@router.post("", status_code=201)
def create_customer(body: CustomerCreate):
    """Tạo khách hàng mới. Trả về danh sách khách hàng khác cùng SĐT (FR2, FR2a, FR4)."""
    with get_db() as conn:
        phones_dicts = _phones_to_dicts(body.phones)
        primary = _primary_phone(phones_dicts)
        customer = Customer(name=body.name, phone=primary or body.phone, phones=phones_dicts)
        customer.save(conn)
        row = conn.execute("SELECT * FROM customers WHERE id = ?", (customer.id,)).fetchone()
        loaded = Customer.from_row(row, conn)
        return _customer_response(conn, loaded)


@router.get("/{customer_id}")
def get_customer(customer_id: int):
    """Chi tiết một khách hàng (FR3, FR6, FR7 — includes yearSummary)."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM customers WHERE id = ?", (customer_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy khách hàng")
        customer = Customer.from_row(row, conn)
        # DG-206 FR7/AC5: include the current year's order count + total volume.
        from datetime import datetime, timezone

        current_year = datetime.now(timezone.utc).year
        customer.year_summary = load_year_summary(conn, customer_id, current_year)
        return customer.to_api_dict()


@router.patch("/{customer_id}")
def update_customer(customer_id: int, body: CustomerUpdate):
    """Cập nhật tên và/hoặc SĐT. Trả về khách hàng khác cùng SĐT (FR4, FR2a, FR5)."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM customers WHERE id = ?", (customer_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy khách hàng")

        customer = Customer.from_row(row, conn)
        if body.name is None and body.phone is None and body.phones is None:
            return _customer_response(conn, customer)

        phones_dicts = _phones_to_dicts(body.phones) if body.phones is not None else None
        # Legacy phone field: sync customer_phones primary row to new value
        if body.phones is None and body.phone is not None:
            phones_dicts = [
                {"phone": p["phone"], "isPrimary": p["isPrimary"]}
                for p in customer.phones
            ]
            if phones_dicts:
                primary_idx = next(
                    (i for i, p in enumerate(phones_dicts) if p["isPrimary"]), 0
                )
                phones_dicts[primary_idx]["phone"] = body.phone
            else:
                phones_dicts = [{"phone": body.phone, "isPrimary": True}]
        customer.update(conn, name=body.name, phone=body.phone, phones=phones_dicts)
        updated_row = conn.execute(
            "SELECT * FROM customers WHERE id = ?", (customer_id,)
        ).fetchone()
        loaded = Customer.from_row(updated_row, conn)
        return _customer_response(conn, loaded)


@router.delete("/{customer_id}")
def delete_customer(customer_id: int):
    """Xóa khách hàng (hard-delete). Đơn hàng liên kết giữ customer_id nhưng
    không còn tham chiếu hợp lệ — staff có thể reassign sau (FR5, FR9)."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM customers WHERE id = ?", (customer_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy khách hàng")

        linked_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (customer_id,)
        ).fetchone()[0]

        # Clear customer_id on linked orders before delete (avoid FK violation;
        # orders retain customer_name/customer_phone for display via NFR3 fallback)
        conn.execute(
            "UPDATE orders SET customer_id = NULL WHERE customer_id = ?",
            (customer_id,),
        )
        # FR9: cascade-delete customer_phones rows (also handled by ON DELETE CASCADE,
        # but explicit DELETE ensures correctness even if FK enforcement is off)
        conn.execute("DELETE FROM customer_phones WHERE customer_id = ?", (customer_id,))
        conn.execute("DELETE FROM customers WHERE id = ?", (customer_id,))
        return {
            "ok": True,
            "id": customer_id,
            "linkedOrdersCleared": linked_orders,
        }


@router.get("/{customer_id}/orders")
def get_customer_orders(customer_id: int):
    """Lịch sử đơn hàng của khách hàng (FR6)."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM customers WHERE id = ?", (customer_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy khách hàng")

        order_rows = conn.execute(
            "SELECT * FROM orders WHERE customer_id = ? ORDER BY id DESC",
            (customer_id,),
        ).fetchall()
        return [Order.from_row(r, conn).to_api_dict() for r in order_rows]