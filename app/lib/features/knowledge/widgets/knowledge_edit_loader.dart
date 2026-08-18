import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/knowledge_provider.dart';
import '../knowledge_form_screen.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Loads a knowledge entry from the API before showing the edit form.
class KnowledgeEditLoader extends ConsumerWidget {
  const KnowledgeEditLoader({super.key, required this.entryId});

  final int entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryAsync = ref.watch(knowledgeEntryDetailProvider(entryId));
    return entryAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, stackTrace) {
        return Scaffold(
          appBar: AppBar(title: const Text(VN.editKnowledge)),
          body: const Center(child: Text(VN.apiError)),
        );
      },
      data: (entry) {
        if (entry == null) {
          return Scaffold(
            appBar: AppBar(title: const Text(VN.editKnowledge)),
            body: const Center(child: Text(VN.apiError)),
          );
        }
        return KnowledgeFormScreen(entry: entry);
      },
    );
  }
}