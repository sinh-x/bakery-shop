// DG-150 Phase 4 temporary exemption: screen coordinator remains above 300 lines until technical tab extraction can be isolated from connection side effects; review in Phase 5 (2026-05-29).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/api/api_client.dart';
import '../../features/auth/auth_provider.dart';
import '../../providers/events_provider.dart';
import '../../providers/staff_provider.dart';
import '../../providers/user_binding_provider.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'widgets/settings_sections.dart';
import 'catalog_tags_settings_tab.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Server URL section
  late TextEditingController _urlController;
  bool _testing = false;
  ConnectionResult? _testResult;

  // Staff section
  late TextEditingController _manualNameCtrl;

  // Version info
  String _appVersion = '';
  String _serverVersion = VN.serverVersionLoading;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    _isAdmin = auth.isAuthenticated && auth.isAdmin;
    _tabController = TabController(length: _isAdmin ? 4 : 3, vsync: this);
    _urlController = TextEditingController();
    _manualNameCtrl = TextEditingController();
    _loadAppVersion();
  }

  late final bool _isAdmin;

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
    _tabController.dispose();
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
          _testResult = ConnectionResult(success: response.statusCode == 200);
          // Also update server version when test succeeds
          _serverVersion = (data?['version'] as String?) ?? '—';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _testing = false;
          _testResult = const ConnectionResult(success: false);
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

  Future<void> _selectBinding(int? staffId) async {
    await ref.read(staffBindingProvider.notifier).updateBinding(staffId);
    if (mounted) showTopSnackBar(context, VN.staffBindingSaved);
  }

  List<Widget> _buildStaffBindingSection() {
    final bindingAsync = ref.watch(staffBindingProvider);
    final staffAsync = ref.watch(staffListProvider);

    return [
      Text(VN.staffBindingTitle,
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(
        VN.staffBindingHelp,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Colors.grey),
      ),
      const SizedBox(height: 8),
      bindingAsync.when(
        data: (binding) => staffAsync.when(
          data: (staffList) => DropdownButtonFormField<int?>(
            initialValue: binding.staffId,
            hint: const Text(VN.staffBindingNone),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text(VN.staffBindingNone),
              ),
              ...staffList.map(
                (s) => DropdownMenuItem<int?>(
                  value: s.id,
                  child: Text(s.name),
                ),
              ),
            ],
            onChanged: (id) {
              if (id != binding.staffId) _selectBinding(id);
            },
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
          ),
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, _) => Text(
            VN.staffBindingNone,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (_, _) => Text(
          VN.staffBindingNone,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    ];
  }

  List<Widget> _buildGraceStaffPicker() {
    final staffAsync = ref.watch(staffListProvider);
    final currentStaff = ref.watch(loggedByProvider);

    return [
      Text(VN.staffPicker,
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      staffAsync.when(
        data: (staffList) => staffList.isEmpty
            ? ManualNameField(
                controller: _manualNameCtrl,
                onSave: _saveManualName,
              )
            : StaffDropdown(
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
        error: (_, _) => ManualNameField(
          controller: _manualNameCtrl,
          onSave: _saveManualName,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final currentUrl = ref.watch(apiBaseUrlProvider);
    final auth = ref.watch(authProvider);

    // Sync URL controller on first build
    if (_urlController.text.isEmpty && currentUrl.isNotEmpty) {
      _urlController.text = currentUrl;
      // Fetch server version when screen opens
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchServerVersion(currentUrl);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.settings),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(icon: Icon(Icons.person), text: VN.generalSettings),
            if (_isAdmin)
              const Tab(
                icon: Icon(Icons.settings),
                text: VN.technicalSettings,
              ),
            const Tab(icon: Icon(Icons.card_giftcard), text: VN.extrasSettings),
            const Tab(
              icon: Icon(Icons.label_outline),
              text: VN.catalogTagEditor,
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Tab 1: Cài đặt chung ─────────────────────────────────
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (auth.isAuthenticated && auth.isAdmin)
                ..._buildStaffBindingSection(),
              if (!auth.isAuthenticated) ..._buildGraceStaffPicker(),
            ],
          ),

          // ── Tab 2: Kỹ thuật (admin-only, FR16/AC10) ─────────────
          if (_isAdmin)
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // App version
                InfoRow(
                  label: VN.appVersion,
                  value: _appVersion.isEmpty ? '...' : _appVersion,
                ),
                const SizedBox(height: 8),
                // Server version
                InfoRow(label: VN.serverVersion, value: _serverVersion),
                const SizedBox(height: 16),
                // Printer paper mode (DG-183 Phase 2)
                const PaperModeSection(),
                const SizedBox(height: 16),
                // Server URL
                Text(
                  VN.apiUrlLabel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  VN.apiUrlHelp,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
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
                    if (_testResult != null) {
                      setState(() => _testResult = null);
                    }
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
                    color: _testResult!.success
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            _testResult!.success
                                ? Icons.check_circle
                                : Icons.error,
                            color: _testResult!.success
                                ? Colors.green
                                : Colors.red,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _testResult!.success
                                ? VN.connectionSuccess
                                : VN.connectionFailed,
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
                const SizedBox(height: 24),
                // Audit log entry (admin-only — this tab is admin-gated).
                ListTile(
                  leading: const Icon(Icons.history_edu),
                  title: const Text(VN.openAuditLog),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/audit-log'),
                ),
                // Duplicate finder (admin-only — DG-252 Phase 7 — FR7/AC4).
                ListTile(
                  leading: const Icon(Icons.merge_type),
                  title: const Text(CustomersLabels.duplicateFinderTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/customers/duplicates'),
                ),
              ],
            ),

          // ── Tab 3: Phụ kiện đi kèm ────────────────────────────────
          const ExtrasSettingsTab(),

          // ── Tab 4: Thẻ ảnh ────────────────────────────────────────
          const CatalogTagsSettingsTab(),
        ],
      ),
    );
  }
}
