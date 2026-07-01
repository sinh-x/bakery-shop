"""Customer management API routes (DG-182 Phase 1)."""

from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, field_validator

from baker.db.connection import get_db
from baker.models.customer import Customer
from baker.models.order import Order


router = APIRouter(prefix="/api/customers", tags=["customers"])


class CustomerCreate(BaseModel):
    name: str
    phone: str = ""

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


class CustomerUpdate(BaseModel):
    name: Optional[str] = None
    phone: Optional[str] = None

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


def _find_customers_sharing_phone(conn, phone: str, exclude_id: int) -> list[dict]:
    """Return other customers sharing the given phone (excluding exclude_id)."""
    if not phone:
        return []
    rows = conn.execute(
        "SELECT * FROM customers WHERE phone = ? AND phone != '' AND id != ? ORDER BY id",
        (phone, exclude_id),
    ).fetchall()
    return [Customer.from_row(r).to_api_dict() for r in rows]


def _customer_response(conn, customer: Customer) -> dict:
    """Build API response including phone-sharing visibility (FR2a)."""
    result = customer.to_api_dict()
    result["sharedPhoneCustomers"] = _find_customers_sharing_phone(
        conn, customer.phone, customer.id
    )
    return result


@router.get("")
def list_customers(search: Optional[str] = Query(None, description="Tìm theo tên hoặc SĐT")):
    """Danh sách khách hàng, hỗ trợ tìm kiếm partial theo tên/SĐT (FR1)."""
    with get_db() as conn:
        if search and search.strip():
            like = f"%{search.strip()}%"
            rows = conn.execute(
                "SELECT * FROM customers "
                "WHERE name LIKE ? OR phone LIKE ? "
                "ORDER BY id DESC",
                (like, like),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM customers ORDER BY id DESC"
            ).fetchall()
        return [Customer.from_row(r).to_api_dict() for r in rows]


@router.post("", status_code=201)
def create_customer(body: CustomerCreate):
    """Tạo khách hàng mới. Trả về danh sách khách hàng khác cùng SĐT (FR2, FR2a)."""
    with get_db() as conn:
        customer = Customer(name=body.name, phone=body.phone)
        customer.save(conn)
        row = conn.execute("SELECT * FROM customers WHERE id = ?", (customer.id,)).fetchone()
        loaded = Customer.from_row(row)
        return _customer_response(conn, loaded)


@router.get("/{customer_id}")
def get_customer(customer_id: int):
    """Chi tiết một khách hàng (FR3)."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM customers WHERE id = ?", (customer_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy khách hàng")
        return Customer.from_row(row).to_api_dict()


@router.patch("/{customer_id}")
def update_customer(customer_id: int, body: CustomerUpdate):
    """Cập nhật tên và/hoặc SĐT. Trả về khách hàng khác cùng SĐT (FR4, FR2a)."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM customers WHERE id = ?", (customer_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy khách hàng")

        customer = Customer.from_row(row)
        if body.name is None and body.phone is None:
            return _customer_response(conn, customer)

        customer.update(conn, name=body.name, phone=body.phone)
        updated_row = conn.execute(
            "SELECT * FROM customers WHERE id = ?", (customer_id,)
        ).fetchone()
        loaded = Customer.from_row(updated_row)
        return _customer_response(conn, loaded)


@router.delete("/{customer_id}")
def delete_customer(customer_id: int):
    """Xóa khách hàng (hard-delete). Đơn hàng liên kết giữ customer_id nhưng
    không còn tham chiếu hợp lệ — staff có thể reassign sau (FR5)."""
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