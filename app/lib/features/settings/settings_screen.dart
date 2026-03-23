import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../shared/widgets/vietnamese_labels.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _urlController;
  bool _testing = false;
  _ConnectionResult? _testResult;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
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
        setState(() {
          _testing = false;
          _testResult = _ConnectionResult(
            success: response.statusCode == 200,
          );
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUrl = ref.watch(apiBaseUrlProvider);

    // Sync controller with current value on first build
    if (_urlController.text.isEmpty && currentUrl.isNotEmpty) {
      _urlController.text = currentUrl;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // API URL section
          Text(
            VN.apiUrlLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            VN.apiUrlHelp,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
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
              // Clear test result when URL changes
              if (_testResult != null) {
                setState(() => _testResult = null);
              }
            },
          ),
          const SizedBox(height: 16),

          // Action buttons
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

          // Test result
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
        ],
      ),
    );
  }
}

class _ConnectionResult {
  final bool success;

  const _ConnectionResult({required this.success});
}
