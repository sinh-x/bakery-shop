from dataclasses import dataclass
from typing import Optional

# Predefined bakery roles: id → Vietnamese label
ROLES = {
    "tho-nuong":  "Thợ nướng bánh",    # Baker (phòng nướng)
    "tho-kem":    "Thợ kem/trang trí",  # Decorator (phòng kem)
    "phu-bep":    "Phụ bếp bánh",       # Baker's assistant
    "bep-truong": "Bếp trưởng",         # Head baker
    "thu-ngan":   "Thu ngân/bán hàng",  # Cashier/sales
    "giao-hang":  "Giao hàng",          # Delivery
    "quan-ly":    "Quản lý",            # Manager/supervisor
    "ho-tro":     "Nhân viên hỗ trợ",   # Support staff
    "ve-sinh":    "Dọn dẹp",            # Cleaner
}

# Short aliases → canonical role id
ROLE_ALIASES = {
    "nuong": "tho-nuong", "baker": "tho-nuong", "nướng": "tho-nuong",
    "kem": "tho-kem", "decorator": "tho-kem", "trangtrí": "tho-kem", "trang-tri": "tho-kem",
    "phu": "phu-bep", "phụ": "phu-bep", "assistant": "phu-bep",
    "truong": "bep-truong", "head": "bep-truong", "chef": "bep-truong",
    "cashier": "thu-ngan", "thungan": "thu-ngan", "banhang": "thu-ngan", "sales": "thu-ngan",
    "delivery": "giao-hang", "giao": "giao-hang", "ship": "giao-hang",
    "manager": "quan-ly", "mgr": "quan-ly", "quanly": "quan-ly", "supervisor": "quan-ly",
    "support": "ho-tro", "hotro": "ho-tro",
    "cleaner": "ve-sinh", "vesinh": "ve-sinh", "clean": "ve-sinh",
}


def resolve_role(role_input):
    """Resolve a role input to its canonical id. Returns as-is if not recognized."""
    key = role_input.lower().strip()
    if key in ROLES:
        return key
    return ROLE_ALIASES.get(key, role_input)


@dataclass
class Staff:
    name: str
    role: str = ""
    phone: str = ""
    active: bool = True
    id: Optional[int] = None
    created_at: Optional[str] = None

    def save(self, conn) -> int:
        cursor = conn.execute(
            "INSERT INTO staff (name, role, phone, active) VALUES (?, ?, ?, ?)",
            (self.name, self.role, self.phone, int(self.active)),
        )
        self.id = cursor.lastrowid
        return self.id

    @staticmethod
    def from_row(row) -> "Staff":
        return Staff(
            id=row["id"],
            name=row["name"],
            role=row["role"] or "",
            phone=row["phone"] or "",
            active=bool(row["active"]),
            created_at=row["created_at"],
        )
