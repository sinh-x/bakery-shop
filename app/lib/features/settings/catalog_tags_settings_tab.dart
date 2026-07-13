import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/labels/shared.dart';
import '../../providers/catalog_provider.dart';
import 'widgets/catalog_tags_dialogs.dart';
import 'widgets/tag_list.dart';

class CatalogTagsSettingsTab extends ConsumerWidget {
  const CatalogTagsSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(catalogTagDefsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAddDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: tagsAsync.when(
        data: (tags) => TagList(tags: tags),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => const Center(
          child: Text(VN.errorLoading),
        ),
      ),
    );
  }
}







