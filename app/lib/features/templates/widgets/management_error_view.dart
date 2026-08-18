import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/providers/template_providers.dart';
import '../../../../shared/labels/shared.dart';

/// Error view for the template management screen. Offers a retry button that
/// re-fetches templates (which falls back to bundled defaults when the
/// backend is still unavailable).
class ManagementErrorView extends ConsumerWidget {
  const ManagementErrorView({super.key, required this.error});

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
            onPressed: () => ref.read(templateListProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text(SharedLabels.retry),
          ),
        ],
      ),
    );
  }
}