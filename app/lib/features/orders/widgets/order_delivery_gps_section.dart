import 'package:flutter/material.dart';

import '../../../shared/labels/orders.dart';
import 'section_header.dart';

/// Editable GPS coordinate fields (latitude + longitude) for door delivery
/// orders (FR1/FR2/AC1). Latitude validated to [-90, 90], longitude to
/// [-180, 180] per NFR2. Extracted from [OrderDeliverySection] to keep the
/// parent widget under the 400-line Flutter coding-standards limit.
class GpsFieldsSection extends StatelessWidget {
  const GpsFieldsSection({
    super.key,
    required this.latitudeCtrl,
    required this.longitudeCtrl,
  });

  final TextEditingController latitudeCtrl;
  final TextEditingController longitudeCtrl;

  @override
  Widget build(BuildContext context) {
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                validator: validateLatitude,
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                validator: validateLongitude,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String? validateLatitude(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  final n = double.tryParse(v.trim());
  if (n == null) return VN.invalidPrice;
  if (n < -90 || n > 90) return OrdersLabels.latitudeInvalid;
  return null;
}

String? validateLongitude(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  final n = double.tryParse(v.trim());
  if (n == null) return VN.invalidPrice;
  if (n < -180 || n > 180) return OrdersLabels.longitudeInvalid;
  return null;
}

/// Read-only tappable Google Maps link row (AC2/AC4).
/// Extracted from [OrderDeliverySection] to keep the parent widget under the
/// 400-line Flutter coding-standards limit.
class MapLinkRow extends StatelessWidget {
  const MapLinkRow({
    super.key,
    required this.url,
    required this.onTap,
  });

  final String url;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        OrdersLabels.openMap,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: theme.colorScheme.primary,
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
}
