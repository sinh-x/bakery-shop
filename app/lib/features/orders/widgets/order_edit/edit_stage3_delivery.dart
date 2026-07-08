import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/order_draft.dart';
import '../../../../shared/utils/date_formatting.dart';
import '../../../../shared/utils/phone_formatter.dart';
import '../hour_picker.dart';
import '../order_delivery_section.dart';
import '../order_wizard.dart';
import '../stage_summary_card.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// Stage 3 of the order edit wizard — delivery.
///
/// Uses the canonical shared `OrderDeliverySection` (DG-216 Phase 3).
/// Edit-specific features — the `formatDisplayDate` date label, the
/// `HourPickerDialog` time picker, and `HourPresetChips` — are preserved via
/// the composable `dueDateTimeSlot`.
class EditStage3Delivery extends ConsumerWidget {
  const EditStage3Delivery({
    super.key,
    required this.deliveryType,
    required this.shippingFee,
    required this.addressCtrl,
    required this.deliveryPhoneCtrl,
    required this.customerPhone,
    required this.notesCtrl,
    required this.shippingBusDefault,
    required this.shippingDoorDefault,
    required this.onDeliveryTypeChanged,
    required this.onShippingFeeChanged,
    required this.dueDate,
    required this.dueTime,
    required this.onPickDate,
    required this.onPickTime,
    required this.onDueTimeChanged,
    required this.wizardSnapshot,
    required this.summaryItems,
    required this.onBack,
    required this.onContinue,
  });

  final String deliveryType;
  final double shippingFee;
  final TextEditingController addressCtrl;
  final TextEditingController deliveryPhoneCtrl;
  final String customerPhone;
  final TextEditingController notesCtrl;
  final double shippingBusDefault;
  final double shippingDoorDefault;
  final ValueChanged<String> onDeliveryTypeChanged;
  final ValueChanged<double> onShippingFeeChanged;
  final DateTime? dueDate;
  final TimeOfDay? dueTime;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final ValueChanged<TimeOfDay> onDueTimeChanged;
  final OrderWizardData wizardSnapshot;
  final List<DraftOrderItem> summaryItems;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: OrderDeliverySection(
              mode: OrderDeliverySectionMode.editable,
              useResponsiveLayout: true,
              deliveryType: deliveryType,
              shippingFee: shippingFee,
              addressCtrl: addressCtrl,
              phoneCtrl: deliveryPhoneCtrl,
              phoneInputFormatters: [PhoneInputFormatter()],
              notesCtrl: notesCtrl,
              shippingBusDefault: shippingBusDefault,
              shippingDoorDefault: shippingDoorDefault,
              onDeliveryTypeChanged: (type) {
                // FR7: prefill delivery phone from customer phone for bus/door
                // when the delivery phone is empty; never overwrite a
                // user-entered value.
                if (type == 'bus' || type == 'door') {
                  if (deliveryPhoneCtrl.text.trim().isEmpty &&
                      customerPhone.trim().isNotEmpty) {
                    deliveryPhoneCtrl.text = customerPhone.trim();
                  }
                }
                onDeliveryTypeChanged(type);
              },
              onShippingFeeChanged: onShippingFeeChanged,
              dueDate: dueDate,
              dueTime: dueTime,
              dueDateTimeSlot: _buildEditDueDateTime(context),
              summaryCardSlots: [
                ProductSummaryCard(items: summaryItems),
                CustomerSummaryCard(
                  wizardData: wizardSnapshot,
                  source: wizardSnapshot.source,
                ),
                DeliverySummaryCard(
                  wizardData: wizardSnapshot,
                  dueDate: dueDate,
                  dueTime: dueTime,
                ),
              ],
            ),
          ),
        ),
        _buildStageNavigation(),
      ],
    );
  }

  // Edit-specific due date/time controls: date label uses formatDisplayDate,
  // time uses the hour-only HourPickerDialog (F5), and HourPresetChips offer
  // quick time-slot selection. Passed to OrderDeliverySection.dueDateTimeSlot.
  Widget _buildEditDueDateTime(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(
                  dueDate != null ? formatDisplayDate(dueDate) : VN.dueDate,
                ),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickTime,
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(
                  dueTime != null ? _formatTime(dueTime!) : VN.dueTime,
                ),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        HourPresetChips(
          selectedTime: dueTime,
          onSelected: onDueTimeChanged,
        ),
      ],
    );
  }

  String _formatTime(TimeOfDay t) => formatHourMinute(t.hour, t.minute);

  Widget _buildStageNavigation() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: onBack,
            child: const Text(OrdersLabels.backLabel),
          ),
          const Spacer(),
          FilledButton(
            onPressed: onContinue,
            child: const Text(OrdersLabels.continueLabel),
          ),
        ],
      ),
    );
  }
}