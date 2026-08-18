import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/address_library_provider.dart';
import 'package:bakery_app/shared/labels/shared.dart';

/// Error view for the management screen. Offers a retry button that
/// re-fetches the library.
///
/// Extracted from `address_library_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class AddressLibraryErrorView extends ConsumerWidget {
  const AddressLibraryErrorView({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text('${SharedLabels.apiError}: $error', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => ref.read(addressLibraryProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text(SharedLabels.retry),
          ),
        ],
      ),
    );
  }
}