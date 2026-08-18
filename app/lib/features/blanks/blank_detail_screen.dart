import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/blanks_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'widgets/blank_detail_body.dart';
import 'widgets/blanks_states.dart';

/// View / edit / delete a single blank (FR1 / AC1).
///
/// Route: `/blanks/:id`. Displays all blank fields, with actions to edit
/// (opens [BlankForm] in edit mode), delete (with confirmation dialog), and
/// an audit log button. BOM mapping is keyed by price_chip (not blank), so
/// it is accessed from the product/price_chip flow rather than here.
///
/// DG-293 Phase 4 also surfaces stock summary (FR4), demand (FR5), and a
/// reverse lookup of linked products/work items (FR6 / AC3-AC4).
class BlankDetailScreen extends ConsumerWidget {
  const BlankDetailScreen({super.key, required this.blankId});

  final int blankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blankAsync = ref.watch(blankByIdProvider(blankId));
    return Scaffold(
      appBar: AppBar(
        title: const Text(BlanksLabels.screenDetail),
        actions: const [AppBarOverflowMenu()],
      ),
      body: blankAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => BlanksErrorView(
          onRetry: () => ref.invalidate(blankByIdProvider(blankId)),
        ),
        data: (blank) => BlankDetailBody(blankId: blank.id, blank: blank),
      ),
    );
  }
}