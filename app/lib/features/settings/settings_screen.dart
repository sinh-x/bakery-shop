import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/api/api_client.dart';
import '../../providers/events_provider.dart';
import '../../providers/staff_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Server URL section
  late TextEditingController _urlController;
  bool _testing = false;
  _ConnectionResult? _testResult;

  // Staff section
  late TextEditingController _manualNameCtrl;

  // Version info
  String _appVersion = '';
  String _serverVersion = VN.serverVersionLoading;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _manualNameCtrl = TextEditingController();
    _loadAppVersion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pre-fill manual name from current logged-by value
    final currentName = ref.read(loggedByProvider);
    if (_manualNameCtrl.text.isEmpty && currentName.isNotEmpty) {
      _manualNameCtrl.text = currentName;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _manualNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = '${info.version}+${info.buildNumber}';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _appVersion = '—');
    }
  }

  Future<void> _fetchServerVersion(String baseUrl) async {
    if (baseUrl.isEmpty) {
      setState(() => _serverVersion = VN.serverVersionError);
      return;
    }
    setState(() => _serverVersion = VN.serverVersionLoading);
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final response = await dio.get('$baseUrl/api/health');
      if (mounted) {
        final data = response.data as Map<String, dynamic>?;
        setState(() {
          _serverVersion = (data?['version'] as String?) ?? '—';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _serverVersion = VN.serverVersionError);
    }
  }

  Future<void> _testConnection() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final response = await dio.get('$url/api/health');
      if (mounted) {
        final data = response.data as Map<String, dynamic>?;
        setState(() {
          _testing = false;
          _testResult = _ConnectionResult(success: response.statusCode == 200);
          // Also update server version when test succeeds
          _serverVersion = (data?['version'] as String?) ?? '—';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _testing = false;
          _testResult = const _ConnectionResult(success: false);
        });
      }
    }
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      showTopSnackBar(context, VN.urlEmpty);
      return;
    }
    await ref.read(apiBaseUrlProvider.notifier).setUrl(url);
    if (mounted) {
      showTopSnackBar(context, VN.urlSaved);
      _fetchServerVersion(url);
    }
  }

  Future<void> _selectStaff(String name) async {
    await ref.read(loggedByProvider.notifier).setName(name);
    if (mounted) showTopSnackBar(context, VN.staffSaved);
  }

  Future<void> _saveManualName() async {
    final name = _manualNameCtrl.text.trim();
    if (name.isEmpty) return;
    await ref.read(loggedByProvider.notifier).setName(name);
    if (mounted) showTopSnackBar(context, VN.staffSaved);
  }

  @override
  Widget build(BuildContext context) {
    final currentUrl = ref.watch(apiBaseUrlProvider);
    final currentStaff = ref.watch(loggedByProvider);
    final staffAsync = ref.watch(staffListProvider);

    // Sync URL controller on first build
    if (_urlController.text.isEmpty && currentUrl.isNotEmpty) {
      _urlController.text = currentUrl;
      // Fetch server version when screen opens
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchServerVersion(currentUrl);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text(VN.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Cài đặt chung ──────────────────────────────────────────
          _SectionTitle(VN.generalSettings),
          const SizedBox(height: 8),
          Text(VN.staffPicker, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),

          // Staff picker: dropdown if loaded, fallback text field on error
          staffAsync.when(
            data: (staffList) => staffList.isEmpty
                ? _ManualNameField(
                    controller: _manualNameCtrl,
                    onSave: _saveManualName,
                  )
                : _StaffDropdown(
                    staffList: staffList.map((s) => s.name).toList(),
                    selected: currentStaff.isNotEmpty ? currentStaff : null,
                    onSelected: _selectStaff,
                  ),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, _) => _ManualNameField(
              controller: _manualNameCtrl,
              onSave: _saveManualName,
            ),
          ),

          const SizedBox(height: 24),

          // ── Kỹ thuật ───────────────────────────────────────────────
          _SectionTitle(VN.technicalSettings),
          const SizedBox(height: 8),

          // App version
          _InfoRow(label: VN.appVersion, value: _appVersion.isEmpty ? '...' : _appVersion),
          const SizedBox(height: 8),

          // Server version
          _InfoRow(label: VN.serverVersion, value: _serverVersion),
          const SizedBox(height: 16),

          // Server URL
          Text(VN.apiUrlLabel, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            VN.apiUrlHelp,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              hintText: VN.apiUrlHint,
              prefixIcon: Icon(Icons.dns),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (_) {
              if (_testResult != null) setState(() => _testResult = null);
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find),
                  label: Text(_testing ? VN.testing : VN.testConnection),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saveUrl,
                  icon: const Icon(Icons.save),
                  label: const Text(VN.save),
                ),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 16),
            Card(
              color: _testResult!.success ? Colors.green.shade50 : Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      _testResult!.success ? Icons.check_circle : Icons.error,
                      color: _testResult!.success ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _testResult!.success ? VN.connectionSuccess : VN.connectionFailed,
                      style: TextStyle(
                        color: _testResult!.success
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _StaffDropdown extends StatelessWidget {
  const _StaffDropdown({
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
      value: staffList.contains(selected) ? selected : null,
      hint: const Text(VN.staffPickerHint),
      items: staffList
          .map((name) => DropdownMenuItem(value: name, child: Text(name)))
          .toList(),
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

class _ManualNameField extends StatelessWidget {
  const _ManualNameField({required this.controller, required this.onSave});
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

class _ConnectionResult {
  final bool success;
  const _ConnectionResult({required this.success});
}
