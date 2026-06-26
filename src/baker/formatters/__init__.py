"""Shared formatters for display output."""


def format_phone(phone: str) -> str:
    """Format phone: 10 digits → xxxx-xxx-xxx, 9 digits → xxx-xxx-xxx, else as-is."""
    digits = "".join(c for c in phone if c.isdigit())
    if len(digits) == 10:
        return f"{digits[:4]}-{digits[4:7]}-{digits[7:]}"
    elif len(digits) == 9:
        return f"{digits[:3]}-{digits[3:6]}-{digits[6:]}"
    return phone


def format_vnd_amount(amount: float) -> str:
    """Format a VND amount with Vietnamese thousand separators (dot) and no decimals.

    VND is conventionally whole-dong; decimals are not used in practice.
    Example: 1500000 -> "1.500.000".
    """
    return f"{int(round(amount)):,}".replace(",", ".")