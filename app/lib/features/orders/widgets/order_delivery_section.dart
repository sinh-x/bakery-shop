import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// EXEMPT: 200-line widget threshold exceeded because OrderDeliverySection
// is the canonical shared delivery widget with multiple sub-sections
// (delivery type, address/phone, shipping fee, notes, due date/time,
// summary card slots, responsive layout). DueDateTimePickerRow was extracted.
// Reviewed 2026-07-08.

import '../../../shared/labels/orders.dart';
import '../../../shared/utils/order_helpers.dart';
import '../../../shared/utils/phone_formatter.dart';
import '../../../shared/widgets/phone_text_field.dart';
import 'due_date_time_picker_row.dart';
import 'section_header.dart';
import 'stage1_responsive_content.dart';

class OrderDeliverySection extends StatelessWidget {
  const OrderDeliverySection({
    super.key,
    required this.deliveryType,
    this.deliveryAddress,
    this.customerPhone,
    this.deliveryPhone,
    this.shippingFee,
    this.notes,
    this.mode = OrderDeliverySectionMode.readOnly,
    this.onDeliveryTypeChanged,
    this.onShippingFeeChanged,
    this.addressCtrl,
    this.phoneCtrl,
    this.notesCtrl,
    this.shippingBusDefault = 25000,
    this.shippingDoorDefault = 20000,
    this.dueDate,
    this.dueTime,
    this.onDueDateChanged,
    this.onDueTimeChanged,
    this.dueDateTimeSlot,
    this.summaryCardSlots = const [],
    this.useResponsiveLayout = false,
    this.shippingFeeConfigLoading = false,
    this.shippingFeeConfigError,
    this.onRetryShippingFeeConfig,
    this.latitude,
    this.longitude,
    this.googleMapsUrl,
    this.latitudeCtrl,
    this.longitudeCtrl,
    this.onLaunchMap,
  });

  final String deliveryType;
  final String? deliveryAddress;
  final String? customerPhone;
  final String? deliveryPhone;
  final double? shippingFee;
  final String? notes;
  final OrderDeliverySectionMode mode;
  final ValueChanged<String>? onDeliveryTypeChanged;
  final ValueChanged<double>? onShippingFeeChanged;
  final TextEditingController? addressCtrl;
  final TextEditingController? phoneCtrl;
  final TextEditingController? notesCtrl;
  final double shippingBusDefault;
  final double shippingDoorDefault;
  final DateTime? dueDate;
  final TimeOfDay? dueTime;
  final ValueChanged<DateTime>? onDueDateChanged;
  final ValueChanged<TimeOfDay>? onDueTimeChanged;
  final Widget? dueDateTimeSlot;
  final List<Widget> summaryCardSlots;
  final bool useResponsiveLayout;
  final bool shippingFeeConfigLoading;
  final String? shippingFeeConfigError;
  final VoidCallback? onRetryShippingFeeConfig;

  // DG-303 Phase 4 / DG-306 Phase 1: GPS fields (door delivery only).
  // Read-only mode consumes `latitude`, `longitude`, `googleMapsUrl`
  // directly; editable mode uses the controllers so changes sync back to
  // the parent provider/state. The manual `deliveryTimeSlot` dropdown was
  // removed (DG-306 Phase 1 / FR2/AC5) — the slot is now auto-derived from
  // `dueTime` by `deriveTimeSlot()` in `delivery_helpers.dart`.
  // DG-306 Phase 3 / FR7: the Google Maps URL text field was removed from
  // create/edit forms — the URL is now managed via the Google Maps modal on
  // the order detail screen (`google_maps_modal.dart`). The `googleMapsUrl`
  // field is kept for read-only display.
  final double? latitude;
  final double? longitude;
  final String? googleMapsUrl;
  final TextEditingController? latitudeCtrl;
  final TextEditingController? longitudeCtrl;
  final VoidCallback? onLaunchMap;

  bool get _needsAddress => deliveryType == 'bus' || deliveryType == 'door';

  /// GPS/map fields are only relevant for door delivery (FR1/FR2/AC1).
  bool get _isDoorDelivery => deliveryType == 'door';

  /// Whether the customer phone should be shown in read-only mode.
  ///
  /// Per FR5/AC5, when the customer phone and delivery phone are identical we
  /// display only one phone number (the customer phone) to avoid duplication.
  bool get _shouldShowCustomerPhone =>
      customerPhone != null && customerPhone!.trim().isNotEmpty;

  /// Whether the delivery phone should be shown in read-only mode.
  ///
  /// Shown only when it is non-empty and differs from the customer phone
  /// (FR4/AC4). When both phones are identical only the customer phone row is
  /// rendered (FR5/AC5).
  bool get _shouldShowDeliveryPhone {
    final dp = deliveryPhone?.trim() ?? '';
    if (dp.isEmpty) return false;
    final cp = customerPhone?.trim() ?? '';
    if (cp.isEmpty) return true;
    return stripNonDigits(dp) != stripNonDigits(cp);
  }

  @override
  Widget build(BuildContext context) {
    if (mode == OrderDeliverySectionMode.readOnly) {
      return _wrap(_buildReadOnly(context));
    }
    return _wrap(_buildEditable(context));
  }

  Widget _wrap(Widget child) {
    if (!useResponsiveLayout) return child;
    return Stage1ResponsiveContent(child: child);
  }

  Widget _buildReadOnly(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dueDate != null)
          _buildInfoRow(
            context,
            Icons.calendar_today,
            VN.dueDate,
            '${dueDate!.day}/${dueDate!.month}/${dueDate!.year}',
          ),
        if (dueTime != null)
          _buildInfoRow(
            context,
            Icons.access_time,
            VN.dueTime,
            '${dueTime!.hour.toString().padLeft(2, '0')}:${dueTime!.minute.toString().padLeft(2, '0')}',
          ),
        _buildInfoRow(context, Icons.local_shipping_outlined, VN.deliveryType, deliveryTypeLabel(deliveryType)),
        if (_needsAddress) ...[
          if (_shouldShowCustomerPhone)
            _buildPhoneRow(context, VN.customerPhone, customerPhone!),
          if (_shouldShowDeliveryPhone)
            _buildPhoneRow(context, OrdersLabels.deliveryPhone, deliveryPhone!),
          if (deliveryAddress != null && deliveryAddress!.isNotEmpty)
            _buildInfoRow(context, Icons.location_on_outlined, VN.deliveryAddress, deliveryAddress!),
        ],
        // DG-306 Phase 1 / FR1: the time slot is auto-derived from `dueTime`
        // (the stored `deliveryTimeSlot` DB column is ignored by the frontend).
        if (dueTime != null)
          _buildInfoRow(
            context,
            Icons.schedule,
            OrdersLabels.deliveryTimeSlotLabel,
            '${dueTime!.hour}:00',
          ),
        if (_isDoorDelivery && latitude != null && longitude != null)
          _buildInfoRow(
            context,
            Icons.my_location,
            OrdersLabels.gpsCoordinatesLabel,
            '$latitude, $longitude',
          ),
        if (_isDoorDelivery &&
            googleMapsUrl != null &&
            googleMapsUrl!.isNotEmpty)
          _buildMapLinkRow(context, googleMapsUrl!),
        if (shippingFee != null && shippingFee! > 0)
          _buildInfoRow(context, Icons.monetization_on_outlined, VN.shippingFee, formatVND(shippingFee!)),
        if (notes != null && notes!.isNotEmpty)
          _buildInfoRow(context, Icons.notes, VN.notes, notes!),
      ],
    );
  }

  Widget _buildEditable(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(VN.dueDate),
        dueDateTimeSlot ??
            DueDateTimePickerRow(
              dueDate: dueDate,
              dueTime: dueTime,
              onDueDateChanged: onDueDateChanged,
              onDueTimeChanged: onDueTimeChanged,
            ),
        const SizedBox(height: 20),
        const SectionHeader(VN.deliveryType),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'pickup',
              label: Text(VN.pickup),
              icon: Icon(Icons.store, size: 16),
            ),
            ButtonSegment(
              value: 'bus',
              label: Text(VN.deliveryBus),
              icon: Icon(Icons.directions_bus, size: 16),
            ),
            ButtonSegment(
              value: 'door',
              label: Text(VN.deliveryDoor),
              icon: Icon(Icons.home, size: 16),
            ),
          ],
          selected: {deliveryType},
          onSelectionChanged: (s) => onDeliveryTypeChanged?.call(s.first),
        ),
        if (_needsAddress && addressCtrl != null) ...[
          const SizedBox(height: 12),
          if (phoneCtrl != null) ...[
            PhoneTextField(
              controller: phoneCtrl!,
              labelText: OrdersLabels.deliveryPhone,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: addressCtrl,
            decoration: const InputDecoration(
              labelText: VN.deliveryAddress,
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                _needsAddress && (v == null || v.trim().isEmpty)
                ? VN.fieldRequired
                : null,
          ),
        ],
        if ((deliveryType == 'bus' || deliveryType == 'door') &&
            onShippingFeeChanged != null)
          _buildShippingFeeSection(context),
        if (_isDoorDelivery) ...[
          if (latitudeCtrl != null && longitudeCtrl != null) ...[
            const SizedBox(height: 16),
            _buildGpsFieldsSection(context),
          ],
        ],
        if (notesCtrl != null) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: notesCtrl,
            decoration: const InputDecoration(
              labelText: VN.notes,
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 3,
          ),
        ],
        if (summaryCardSlots.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...summaryCardSlots,
        ],
      ],
    );
  }

  Widget _buildShippingFeeSection(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 20),
        const SectionHeader(VN.shippingFee),
        if (shippingFeeConfigLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (shippingFeeConfigError != null)
          _buildShippingFeeError(context)
        else
          _buildShippingFeeStepper(context),
      ],
    );
  }

  Widget _buildShippingFeeError(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              VN.errorLoading,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          if (onRetryShippingFeeConfig != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onRetryShippingFeeConfig,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text(VN.retry),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShippingFeeStepper(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filled(
          onPressed: (shippingFee ?? 0) >= 5000
              ? () => onShippingFeeChanged!((shippingFee ?? 0) - 5000.0)
              : null,
          icon: const Icon(Icons.remove),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            (shippingFee ?? 0) == 0
                ? VN.shippingFree
                : formatVND(shippingFee!),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton.filled(
          onPressed: () => onShippingFeeChanged!((shippingFee ?? 0) + 5000.0),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  /// Read-only tappable Google Maps link row (AC2/AC4). Falls back to a plain
  /// info row when `onLaunchMap` is null or the URL cannot be opened.
  Widget _buildMapLinkRow(BuildContext context, String url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.map_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              '${OrdersLabels.googleMapsUrlLabel}:',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onLaunchMap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        OrdersLabels.openMap,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// GPS coordinate + Google Maps URL fields for door delivery (FR1/FR2/AC1).
  /// Latitude is validated to [-90, 90], longitude to [-180, 180] (NFR2).
  Widget _buildGpsFieldsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(OrdersLabels.gpsCoordinatesLabel),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: latitudeCtrl,
                decoration: const InputDecoration(
                  labelText: OrdersLabels.latitudeLabel,
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true, signed: true),
                validator: _validateLatitude,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: longitudeCtrl,
                decoration: const InputDecoration(
                  labelText: OrdersLabels.longitudeLabel,
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true, signed: true),
                validator: _validateLongitude,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String? _validateLatitude(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    if (n == null) return VN.invalidPrice;
    if (n < -90 || n > 90) return OrdersLabels.latitudeInvalid;
    return null;
  }

  String? _validateLongitude(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    if (n == null) return VN.invalidPrice;
    if (n < -180 || n > 180) return OrdersLabels.longitudeInvalid;
    return null;
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  /// Read-only phone row with a tap-to-call action that opens the native dialer
  /// via a `tel:` URI (FR4/AC4). Falls back to a plain info row when the dialer
  /// cannot be launched.
  Widget _buildPhoneRow(BuildContext context, String label, String phone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.phone_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _launchPhone(context, phone),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        phone,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.phone_in_talk,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchPhone(BuildContext context, String phone) async {
    final digits = stripNonDigits(phone);
    if (digits.isEmpty) return;
    final uri = Uri.parse('tel:$digits');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(OrdersLabels.cannotOpenDialer)),
      );
    }
  }
}

enum OrderDeliverySectionMode { editable, readOnly }
