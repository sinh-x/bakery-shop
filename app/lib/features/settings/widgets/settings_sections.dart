import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/config_service.dart';
import '../../../providers/config_provider.dart';
import '../../../shared/labels/shared.dart';

class ConnectionResult {
  const ConnectionResult({required this.success});

  final bool success;
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ', style: Theme.of(context).textTheme.bodyMedium),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class StaffDropdown extends StatelessWidget {
  const StaffDropdown({
    super.key,
    required this.staffList,
    required this.selected,
    required this.onSelected,
  });

  final List<String> staffList;
  final String? selected;
  final Future<void> Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: staffList.contains(selected) ? selected : null,
      hint: const Text(VN.staffPickerHint),
      items: staffList.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
      onChanged: (name) {
        if (name != null) onSelected(name);
      },
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.person),
      ),
    );
  }
}

class ManualNameField extends StatelessWidget {
  const ManualNameField({super.key, required this.controller, required this.onSave});

  final TextEditingController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: VN.staffNameManual,
              hintText: VN.staffNameHint,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
            textCapitalization: TextCapitalization.words,
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: onSave, child: const Text(VN.save)),
      ],
    );
  }
}

class ExtrasSettingsTab extends ConsumerStatefulWidget {
  const ExtrasSettingsTab({super.key});

  @override
  ConsumerState<ExtrasSettingsTab> createState() => _ExtrasSettingsTabState();
}

class _ExtrasSettingsTabState extends ConsumerState<ExtrasSettingsTab> {
  @override
  Widget build(BuildContext context) {
    final extrasAsync = ref.watch(orderExtrasProvider);
    return Scaffold(
      body: extrasAsync.when(
        data: (extras) => extras.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.card_giftcard, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(VN.noExtras, style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: extras.length,
                itemBuilder: (context, index) {
                  final extra = extras[index];
                  final parts = extra.split('|');
                  final name = parts.isNotEmpty ? parts[0] : extra;
                  final price = parts.length > 1 ? parts[1] : '';
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.card_giftcard, color: Colors.teal),
                      title: Text(name),
                      subtitle: price.isNotEmpty ? Text(formatVND(double.tryParse(price) ?? 0)) : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showEditDialog(context, extra, name, price),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _showDeleteDialog(context, extra),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text(VN.errorLoading)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(VN.addExtra),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: VN.extraName, hintText: VN.extraNameHint), textCapitalization: TextCapitalization.words),
            const SizedBox(height: 16),
            TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: VN.extraPrice, hintText: VN.extraPriceHint), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(VN.cancel)),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final price = priceCtrl.text.trim();
              if (name.isEmpty || price.isEmpty) return;
              try {
                await ref.read(configServiceProvider).createConfigValue('order_extra', '$name|$price');
                ref.invalidate(orderExtrasProvider);
                if (ctx.mounted) Navigator.pop(ctx);
                if (ctx.mounted) showTopSnackBar(context, VN.extraAdded);
              } catch (e) {
                if (ctx.mounted) showTopSnackBar(context, 'Error: $e', backgroundColor: Colors.red);
              }
            },
            child: const Text(VN.save),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, String oldValue, String name, String price) {
    final nameCtrl = TextEditingController(text: name);
    final priceCtrl = TextEditingController(text: price);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(VN.editExtra),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: VN.extraName), textCapitalization: TextCapitalization.words),
            const SizedBox(height: 16),
            TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: VN.extraPrice), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(VN.cancel)),
          FilledButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              final newPrice = priceCtrl.text.trim();
              if (newName.isEmpty || newPrice.isEmpty) return;
              try {
                await ref.read(configServiceProvider).updateConfigValue('order_extra', oldValue, '$newName|$newPrice');
                ref.invalidate(orderExtrasProvider);
                if (ctx.mounted) Navigator.pop(ctx);
                if (ctx.mounted) showTopSnackBar(context, VN.extraUpdated);
              } catch (e) {
                if (ctx.mounted) showTopSnackBar(context, 'Error: $e', backgroundColor: Colors.red);
              }
            },
            child: const Text(VN.save),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, String value) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(VN.remove),
        content: const Text(VN.deleteExtraConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(VN.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await ref.read(configServiceProvider).deleteConfigValue('order_extra', value);
                ref.invalidate(orderExtrasProvider);
                if (ctx.mounted) Navigator.pop(ctx);
                if (ctx.mounted) showTopSnackBar(context, VN.extraDeleted);
              } catch (e) {
                if (ctx.mounted) showTopSnackBar(context, 'Error: $e', backgroundColor: Colors.red);
              }
            },
            child: const Text(VN.remove),
          ),
        ],
      ),
    );
  }
}
