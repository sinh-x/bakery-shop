# Pre-Release Testing Checklist

> **Purpose:** Verify critical form fields on the Flutter bakery app before APK or web deployment.
> **Audience:** Sinh (app owner/developer)
> **Last Updated:** 2026-04-16
> **Related:** See [DG-055 Post-Mortem](dg-055-postmortem.md) for the bug that prompted this checklist.

---

## When to Run This Checklist

Run **before every APK or web deployment**. Do not skip the "Must" items for regular releases. For urgent hotfixes, you may skip "Should" items but must complete all "Must" items.

### Triggers for Updating This Checklist

Update this checklist when:
- A **new input field** is added to the Order Create or Order Edit screen
- A **new custom formatter** is added (e.g., phone, date, currency formatting)
- A **new screen with critical data entry** is added to the app
- A bug is discovered in an existing form field

---

## §1 Build Verification

### Mobile (Android APK)

**Must — Build Debug APK:**

```bash
cd app
flutter build apk --debug
```

1. Verify build completes with no errors
2. Verify no warnings about missing assets or broken imports
3. Install on device: `adb install build/app/outputs/flutter-apk/app-debug.apk`
4. Launch the app — verify home screen appears

### Web (PWA)

**Must — Build Flutter Web:**

```bash
cd app
flutter build web
```

1. Verify build completes with no errors
2. Verify `build/web/` directory contains `index.html` and assets
3. Serve locally (optional): `cd build/web && python3 -m http.server 8080`
4. Open `http://localhost:8080` in Chrome — verify app loads

### Build Warnings Check

**Should — Run Flutter Analyze:**

```bash
cd app && flutter analyze
```

1. Verify no new errors or warnings introduced
2. Known harmless warning: `CupertinoIcons` font warning during release build (transitive dependency)

---

## §2 Critical Form Fields — Order Create Screen

Test each field on the **Order Create** screen (`/orders/create`). All test steps are written for the Order Create screen unless noted as "Order Edit screen only."

### FR3.1 — Phone Input [Must]

**Purpose:** Verify auto-formatting and cursor behavior

1. Tap the phone input field
2. Type: `0`
   - Expected: cursor stays after `0`, no auto-format yet
3. Type: `123456789`
   - Expected: field shows `0123-456-789`
   - **Critical:** cursor must be positioned after the last `9`, not jumped to the end or middle
4. Press backspace twice
   - Expected: `0123-456-78` with cursor after `8`
5. Type: `90`
   - Expected: `0123-456-790` with cursor after `0`

### FR3.2 — Customer Name [Must]

1. Tap the customer name field
2. Type: `Nguyễn Văn Minh`
3. Verify text appears correctly with Vietnamese characters intact
4. Verify no truncation at 50+ characters

### FR3.3 — Order Source [Must]

1. Tap the "Zalo" source chip (or first available source chip)
   - Expected: chip becomes selected/ highlighted
2. Tap the same chip again
   - Expected: chip becomes deselected
3. Tap a different source chip
   - Expected: new chip is selected, previous chip is deselected

### FR3.4 — Due Date [Must]

1. Tap the date button/field
   - Expected: date picker opens
2. Select a future date (e.g., 3 days from today)
3. Tap "Confirm" or equivalent
   - Expected: date displays in the field in correct format (e.g., `15/04/2026`)

### FR3.5 — Due Time [Must]

1. Tap a time preset chip (e.g., "8:00", "14:00")
   - Expected: chip becomes selected
2. Tap the hour label next to the chip
   - Expected: hour picker opens
3. Select a different hour and confirm
   - Expected: hour updates, chip remains or updates accordingly

### FR3.6 — Delivery Type [Must]

1. Select "Pickup" delivery type
   - Expected: conditional fields (address, shipping fee) are hidden or disabled
2. Switch to "Bus" delivery type
   - Expected: address field appears/shows, shipping fee field appears
3. Switch to "Door" delivery type
   - Expected: address field appears/shows, shipping fee field appears

### FR3.7 — Address [Must] (Bus/Door only)

1. With delivery type set to "Bus" or "Door"
2. Tap the address field
3. Type: `123 Nguyễn Trãi, Quận 1`
4. Verify text appears, field is not empty
5. Verify field is marked as required (form cannot be submitted with empty address when delivery is Bus/Door)

### FR3.8 — Shipping Fee [Must] (Bus/Door only)

1. With delivery type set to "Bus" or "Door"
2. Find the shipping fee display
3. Tap the `+` button once
   - Expected: fee increases by 5,000đ (e.g., from 0 to 5,000đ)
4. Tap the `+` button again
   - Expected: fee increases to 10,000đ
5. Tap the `-` button once
   - Expected: fee decreases to 5,000đ
6. Verify fee displays correctly with `đ` suffix

### FR3.9 — Notes [Should] (Non-pickup only)

1. With delivery type set to "Bus" or "Door"
2. Find the notes field
3. Type a multi-line note:
   ```
   Giao hàng lúc 14:00
   Gọi trước khi giao
   ```
4. Verify both lines are visible and stored correctly

### FR3.10 — Deposit Toggle [Must]

1. Find the deposit checkbox/toggle
2. Tap to enable deposit
   - Expected: deposit sub-form appears (amount field, method selection)
3. Tap to disable deposit
   - Expected: deposit sub-form hides/disables

### FR3.11 — Deposit Amount [Must]

1. Enable deposit toggle (FR3.10)
2. Tap the deposit amount field
3. Type: `50000`
4. Verify field shows `50.000đ` or `50000đ` suffix
5. Try to save with amount = 0
   - Expected: validation error (deposit amount must be > 0)
6. Clear the field and try to save
   - Expected: validation error (deposit amount required when deposit is enabled)

### FR3.12 — Deposit Method [Must]

1. Enable deposit toggle (FR3.10)
2. Find the deposit method chips (e.g., "Cash", "Transfer")
3. Tap "Transfer" chip
   - Expected: chip becomes selected
4. Tap "Cash" chip
   - Expected: "Cash" is selected, "Transfer" is deselected

### FR3.13 — Work Items: Add Product [Must]

1. Find the product picker/add button in work items section
2. Tap to open product picker
3. Select a product (e.g., "Bánh mì thịt")
4. Verify product appears in the work items list
5. Verify price is correct (matches selected product)
6. Verify quantity is 1 by default

### FR3.14 — Work Items: Extras [Should]

1. Add a product (FR3.13)
2. Find the extras option for that product
3. Add an extra item (e.g., "Extra cheese")
4. Verify extra appears with a badge label ("Paid" or "Gift")
5. Find quantity `+` and `-` buttons for the extra
6. Tap `+` once
   - Expected: extra quantity increases

### FR3.15 — Work Items: Remove [Must]

1. Add at least one product (FR3.13)
2. Find the remove/delete button for that item
3. Tap remove
   - Expected: item disappears from list
4. Verify total price recalculates (should not include removed item)

---

## §3 End-to-End Flow

### FR4.1 — Create Order with All Fields [Must]

1. Fill in ALL the following fields:
   - Customer name: `Test Khách Hàng`
   - Phone: `0987654321`
   - Order source: select one chip
   - Due date: select a future date
   - Due time: select a time
   - Delivery type: select "Door"
   - Address: `123 Test Street`
   - Shipping fee: tap `+` twice (10,000đ)
   - Notes: `Test order`
   - Deposit: enable, amount `50000`, method: Transfer
   - Work items: add 1 product
2. Tap "Save" or "Create" button
3. Expected: order saves successfully, success message appears or screen navigates away

### FR4.2 — Edit Order [Must]

1. Open the order just created (or any existing order)
2. Tap "Edit" or navigate to edit screen
3. Change customer name to: `Test Khách Hàng Updated`
4. Change shipping fee: tap `+` once more (15,000đ)
5. Tap "Save" button
6. Expected: changes persist, saved values shown on order detail

### FR4.3 — View Order Detail [Should]

1. Open the order from FR4.1 or FR4.2
2. Verify ALL of the following display correctly:
   - Customer name (updated name from FR4.2)
   - Phone number (formatted as `xxxx-xxx-xxx`)
   - Order source
   - Due date and time
   - Delivery type and address
   - Shipping fee
   - Notes
   - Deposit amount and method
   - Work items list with correct prices

### FR4.4 — Delete Test Order [Should]

1. Open the test order from FR4.1
2. Tap delete button
3. Confirm deletion
4. Expected: order is removed from list, no error

---

## §4 Platform-Specific Notes

### Mobile (Android APK)

- **Must test on physical Android device** — emulator may not accurately reproduce cursor behavior
- Date picker uses Material Design picker
- Time picker uses Material chips + optional hour picker
- Run through all 15 form field tests on the device

### Web (PWA)

- **Must test in Chrome** (or Chromium-based browser)
- Date picker uses **browser native date picker** (different from Material picker on mobile)
- Time picker may use browser-native input or Flutter web-specific picker
- Test in both portrait and landscape orientations
- Verify scroll behavior works for long forms

### Platform Differences to Note

| Feature | Mobile | Web |
|---------|--------|-----|
| Date picker | Material picker | Browser native `<input type="date">` |
| Time picker | Material chips + picker | May differ — test carefully |
| Phone auto-format | Yes | Yes (same formatter) |
| Scroll in form | Native scroll | Browser scroll |

---

## §5 Sign-Off

Complete this section after running the checklist.

### Pre-Release Sign-Off

| Check | Result | Notes |
|-------|--------|-------|
| Build verification (mobile) | pass / skip | |
| Build verification (web) | pass / skip | |
| Build warnings check | pass / skip | |
| All 15 form fields tested | pass / skip | |
| End-to-end create order | pass / skip | |
| End-to-end edit order | pass / skip | |
| Order detail view | pass / skip | |
| Test order deleted | pass / skip | |
| Platform differences noted | pass / skip | |

### Reviewer

- **Name:** Sinh
- **Date:** \_\_\_\_\_\_\_\_\_\_
- **Release version:** \_\_\_\_\_\_\_\_\_\_
- **Platforms tested:** Mobile (APK) ☐ / Web (PWA) ☐

---

## §6 Maintenance Guide

### When to Update This Checklist

Update immediately when any of these occur:

1. **New input field added** to Order Create or Order Edit screen
   - Add a new test entry to §2 with the field name, purpose, and test steps
   - Follow the same pattern: action → input → expected result

2. **New custom formatter added** (e.g., a new `XYZInputFormatter`)
   - Add a test entry for the formatter behavior
   - Include cursor position checks if the formatter affects cursor placement

3. **New screen with critical data entry** added
   - Create a new section for that screen following the same checklist format
   - Identify the top 5-10 most critical fields to test

4. **Bug discovered in existing field**
   - Add the field to the checklist if not already present
   - Write specific test steps to catch the bug

### How to Update

1. Edit `docs/pre-release-checklist.md`
2. Add or update the relevant section
3. Run the new/changed test steps as part of the next release
4. Update the "Last Updated" date at the top

### Version History

| Date | Change | Author |
|------|--------|--------|
| 2026-04-16 | Initial version — 15 critical form fields, mobile + web | builder/team-manager |
