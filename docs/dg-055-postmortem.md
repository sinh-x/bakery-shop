# DG-055 Post-Mortem: Phone Input Cursor-Jump Bug

> **Incident ID:** DG-055
> **Date:** 2026-03-30 (discovered ~2026-03-29)
> **Severity:** High
> **Status:** Fixed and deployed
> **Author:** builder/team-manager

---

## §1 Incident Description

### What Happened

When bakery staff typed a phone number into the **Order Create** or **Order Edit** screen, the cursor jumped to an incorrect position after each digit was entered. For example, typing `0123456789` would result in a misformatted or incorrectly positioned cursor, making data entry frustrating and error-prone.

### When Discovered

The bug was discovered on **2026-03-29** during normal bakery operations. Staff reported that typing phone numbers in the order form was difficult because the cursor kept jumping away from the intended insertion point.

### User Impact

- **High daily operational impact** — affected every delivery order (which requires a phone number)
- Staff frustration and slower order processing
- Potential for mis-entered phone numbers leading to delivery issues

---

## §2 Root Cause Analysis

### Technical Root Cause

The `PhoneInputFormatter` class in `app/lib/shared/utils/phone_formatter.dart` used a **naive cursor offset approach** when applying auto-formatting to phone numbers.

**The Problem:**

The formatter applied formatting (e.g., `0123-456-789`) by simply calculating an offset from the raw digit count, without remapping the cursor position through the formatted string structure. This caused the cursor to land at an incorrect position after each keystroke.

### Affected Files

- `app/lib/shared/utils/phone_formatter.dart` (L40-59) — the buggy `formatEditUpdate()` implementation
- `app/lib/features/orders/order_create_screen.dart` (L270) — primary usage
- `app/lib/features/orders/order_edit_screen.dart` (L270) — secondary usage

### Why It Reached Production

- No pre-release testing protocol existed for critical form fields
- No automated or manual test covered keystroke-by-keystroke cursor position during auto-formatting
- The bug was subtle — it required typing a full 10-digit number to notice the cursor drift

---

## §3 Fix Description

### Solution: Digit-Position Mapping

The fix rewrites the `formatEditUpdate()` method in `PhoneInputFormatter` to use **digit-position mapping** for cursor placement:

1. Count digit positions before the cursor in the new (unformatted) value
2. Walk through the formatted string, counting digit characters
3. When the target digit count is reached, place the cursor after that digit in the formatted string

### Key Code Location

`app/lib/shared/utils/phone_formatter.dart` — lines 40-59 contain the cursor mapping fix.

### Verification

After the fix, typing `0123456789` produces `0123-456-789` with the cursor correctly positioned after the last digit.

---

## §4 Timeline

| Date | Event |
|------|-------|
| ~2026-03-29 | Bug discovered during normal operations |
| 2026-03-30 | Bug reported as DG-055 |
| 2026-03-30 | Root cause identified: naive cursor offset in `PhoneInputFormatter` |
| 2026-03-30 | Fix implemented: digit-position mapping in `formatEditUpdate()` |
| 2026-03-30 | Fix deployed to production |
| 2026-04-16 | Process fix: DG-061 pre-release testing checklist created |

---

## §5 Lessons Learned

### What Process Failed

- **No pre-release testing for critical form fields** — the app had no structured testing protocol for fields where subtle bugs (like cursor placement) could slip through
- **No automated widget tests** for form input interactions — `flutter_test` existed but was not used to test `PhoneInputFormatter` behavior

### What Went Well

- Root cause was isolated to a single, well-understood file
- Fix was straightforward once the cursor mapping issue was identified
- Staff reported the bug quickly once they noticed it

### What to Improve

- **Process:** A pre-release testing checklist for critical form fields (implemented as DG-061)
- **Process:** Consider adding a `flutter_test` widget test for `PhoneInputFormatter` to prevent regression:
  ```dart
  test('PhoneInputFormatter places cursor correctly when typing 10 digits', () {
    // Type 0123456789 → verify cursor ends at position 13 (after last digit in 0123-456-789)
  });
  ```

---

## §6 Related Tickets

| Ticket | Description |
|--------|-------------|
| DG-055 | Original bug report — phone input cursor-jump |
| DG-061 | This ticket — pre-release testing checklist to prevent recurrence |
