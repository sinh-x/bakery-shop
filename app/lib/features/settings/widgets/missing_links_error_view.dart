import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/missing_links_provider.dart';
import 'package:bakery_app/shared/labels/shared.dart';

/// Error view for the missing-links screen (AC5). Offers a retry button
/// that re-fetches the list. Wrapped in a scrollable so
/// [RefreshIndicator] still works on the error state.
///
/// Extracted from `missing_links_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class MissingLinksErrorView extends ConsumerWidget {
  const MissingLinksErrorView({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  '${SharedLabels.apiError}: $error',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(missingLinksProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text(SharedLabels.retry),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}