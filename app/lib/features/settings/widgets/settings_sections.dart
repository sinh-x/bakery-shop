import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.info_outline),
                    title: Text(VN.extrasSettingsDeprecatedTitle),
                    subtitle: Text(VN.extrasSettingsDeprecatedBody),
                  ),
                  SizedBox(height: 8),
                  Text(VN.extrasSettingsDeprecatedAction),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
