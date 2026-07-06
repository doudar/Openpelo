import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/installed_app_model.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import 'draggable_dialog.dart';
import 'screen_mirror_dialog.dart';

class InstalledAppManagerDialog extends StatefulWidget {
  const InstalledAppManagerDialog({super.key});

  @override
  State<InstalledAppManagerDialog> createState() =>
      _InstalledAppManagerDialogState();
}

class _InstalledAppManagerDialogState extends State<InstalledAppManagerDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<InstalledAppModel> _apps = [];
  bool _includeSystemApps = false;
  bool _loading = true;
  String _query = '';
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadApps());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    setState(() => _loading = true);
    final provider = Provider.of<AppProvider>(context, listen: false);
    final apps = await provider.listInstalledApps(
      includeSystemApps: _includeSystemApps,
    );
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  List<InstalledAppModel> get _filteredApps {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _apps;
    return _apps.where((app) {
      return app.label.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _showResult(
    bool success,
    String successText,
    String failureText,
  ) async {
    if (!mounted) return;
    setState(() {
      _statusMessage = success ? successText : failureText;
      _statusIsError = !success;
    });
  }

  void _showRemoteControl() {
    showDialog(
      context: context,
      builder: (_) => const ScreenMirrorDialog(),
    );
  }

  Future<void> _confirmClearData(InstalledAppModel app) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear App Data"),
        content: Text(
          "Clear all data for ${app.label}?\n\n"
          "This resets the app as if it was freshly installed.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: const Text("Clear Data"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final provider = Provider.of<AppProvider>(context, listen: false);
    final ok = await provider.clearInstalledAppData(app.packageName);
    await _showResult(
      ok,
      "Cleared ${app.label}",
      "Could not clear ${app.label}",
    );
  }

  Future<void> _confirmUninstall(InstalledAppModel app) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Uninstall App"),
        content: Text(
          "Uninstall ${app.label}?\n\n"
          "${app.packageName}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: const Text("Uninstall"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final provider = Provider.of<AppProvider>(context, listen: false);
    final ok = await provider.uninstallInstalledApp(app.packageName);
    await _showResult(
      ok,
      "Uninstalled ${app.label}",
      "Could not uninstall ${app.label}",
    );
    if (ok) await _loadApps();
  }

  Future<void> _exportApps() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final path = await provider.exportInstalledApps(_filteredApps);
    if (!mounted || path == null) return;
    setState(() {
      _statusMessage = "Exported app list to $path";
      _statusIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredApps = _filteredApps;

    return DraggableDialog(
      width: 900,
      height: 680,
      leading: const Icon(Icons.apps),
      title: const Text(
        "Installed App Manager",
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        IconButton(
          tooltip: "Refresh",
          onPressed: _loading ? null : _loadApps,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: "Export visible list",
          onPressed: _loading || filteredApps.isEmpty ? null : _exportApps,
          icon: const Icon(Icons.file_download),
        ),
        IconButton(
          tooltip: "Close",
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ],
      footer: _buildStatusBar(filteredApps.length),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: "Search apps",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  selected: _includeSystemApps,
                  label: const Text("System apps"),
                  avatar: const Icon(Icons.admin_panel_settings, size: 18),
                  onSelected: _loading
                      ? null
                      : (value) async {
                          setState(() => _includeSystemApps = value);
                          await _loadApps();
                        },
                ),
              ],
            ),
          ),
          Expanded(child: _buildAppList(filteredApps)),
        ],
      ),
    );
  }

  Widget _buildAppList(List<InstalledAppModel> filteredApps) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (filteredApps.isEmpty) {
      return const Center(child: Text("No apps match your search."));
    }

    return ListView.separated(
      itemCount: filteredApps.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final app = filteredApps[index];
        return _InstalledAppTile(
          app: app,
          onLaunch: () async {
            final provider = Provider.of<AppProvider>(
              context,
              listen: false,
            );
            final ok = await provider.launchInstalledApp(
              app.packageName,
            );
            await _showResult(
              ok,
              "Launched ${app.label}",
              "Could not launch ${app.label}",
            );
            if (ok && mounted) _showRemoteControl();
          },
          onForceStop: () async {
            final provider = Provider.of<AppProvider>(
              context,
              listen: false,
            );
            final ok = await provider.forceStopInstalledApp(
              app.packageName,
            );
            await _showResult(
              ok,
              "Force stopped ${app.label}",
              "Could not force stop ${app.label}",
            );
          },
          onClearData: () => _confirmClearData(app),
          onSettings: () async {
            final provider = Provider.of<AppProvider>(
              context,
              listen: false,
            );
            final ok = await provider.openAppSettings(
              app.packageName,
            );
            await _showResult(
              ok,
              "Opened settings for ${app.label}",
              "Could not open settings for ${app.label}",
            );
            if (ok && mounted) _showRemoteControl();
          },
          onUninstall: () => _confirmUninstall(app),
        );
      },
    );
  }

  Widget _buildStatusBar(int filteredCount) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _statusMessage ?? "$filteredCount of ${_apps.length} apps shown",
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _statusIsError ? colorScheme.error : null,
                    fontWeight: _statusMessage == null
                        ? FontWeight.normal
                        : FontWeight.w600,
                  ),
            ),
          ),
          if (_statusMessage != null)
            IconButton(
              tooltip: "Clear status",
              onPressed: () => setState(() => _statusMessage = null),
              icon: const Icon(Icons.close, size: 18),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _InstalledAppTile extends StatelessWidget {
  final InstalledAppModel app;
  final VoidCallback onLaunch;
  final VoidCallback onForceStop;
  final VoidCallback onClearData;
  final VoidCallback onSettings;
  final VoidCallback onUninstall;

  const _InstalledAppTile({
    required this.app,
    required this.onLaunch,
    required this.onForceStop,
    required this.onClearData,
    required this.onSettings,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(app.isSystemApp ? Icons.android : Icons.apps),
      title: Text(app.label, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        app.packageName,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: "Launch",
            onPressed: onLaunch,
            icon: const Icon(Icons.play_arrow),
          ),
          IconButton(
            tooltip: "Force stop",
            onPressed: onForceStop,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
          IconButton(
            tooltip: "Clear data",
            onPressed: onClearData,
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
          IconButton(
            tooltip: "App settings",
            onPressed: onSettings,
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: "Uninstall",
            onPressed: app.isSystemApp ? null : onUninstall,
            color: AppColors.danger,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
