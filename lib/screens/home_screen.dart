import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/log_panel.dart';
import '../widgets/app_list_widget.dart';
import '../widgets/file_manager_dialog.dart';
import '../widgets/guide_dialog.dart';
import '../widgets/installed_app_manager_dialog.dart';
import '../widgets/peloton_uninstaller_dialog.dart';
import '../widgets/recessed_pane.dart';
import '../widgets/screen_mirror_dialog.dart';
import '../widgets/device_capabilities_tile.dart';
import '../theme/app_theme.dart';
import 'wireless_connect_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final statusIsError = provider.statusMessage.contains('❌');
    final statusText = provider.statusMessage
        .replaceFirst('✅ ', '')
        .replaceFirst('❌ ', '');

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: const Text('OpenPelo', overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 12),
            Text(
              'v${provider.currentAppVersion ?? '…'}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onPrimary.withValues(alpha: 0.86),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Open tools menu',
            onSelected: (value) async {
              if (value == 'uninstall') {
                if (provider.selectedDevice == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No device selected")),
                  );
                } else {
                  showDialog(
                    context: context,
                    builder: (_) => const PelotonUninstallerDialog(),
                  );
                }
              } else if (value == 'installed_apps') {
                if (provider.selectedDevice == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No device selected")),
                  );
                } else {
                  showDialog(
                    context: context,
                    builder: (_) => const InstalledAppManagerDialog(),
                  );
                }
              } else if (value == 'file_manager') {
                final deviceSerial = provider.selectedDevice?.serial;
                if (deviceSerial == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No device selected")),
                  );
                } else {
                  showDialog(
                    context: context,
                    builder: (_) =>
                        FileManagerDialog(deviceSerial: deviceSerial),
                  );
                }
              } else if (value == 'dev_options') {
                if (provider.selectedDevice == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No device selected")),
                  );
                } else {
                  _showDeveloperOptionsDialog(context, provider);
                }
              } else if (value == 'default_launcher') {
                if (provider.selectedDevice == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No device selected")),
                  );
                } else {
                  _showDefaultLauncherDialog(context, provider);
                }
              } else if (value == 'rotate_screen') {
                if (provider.selectedDevice == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No device selected")),
                  );
                } else {
                  _showRotateScreenDialog(context, provider);
                }
              } else if (value == 'builtin_netflix') {
                if (provider.selectedDevice == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No device selected")),
                  );
                } else {
                  _showBuiltinNetflixDialog(context, provider);
                }
              } else if (value == 'check_updates') {
                await provider.checkForUpdates();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'installed_apps',
                child: Text('Installed App Manager'),
              ),
              const PopupMenuItem(
                value: 'file_manager',
                child: Text('File Manager'),
              ),
              const PopupMenuItem(
                value: 'uninstall',
                child: Text('Uninstall Peloton Apps'),
              ),
              const PopupMenuItem(
                value: 'dev_options',
                child: Text('Enable Developer Settings'),
              ),
              const PopupMenuItem(
                value: 'default_launcher',
                child: Text('Set Default Launcher'),
              ),
              const PopupMenuItem(
                value: 'rotate_screen',
                child: Text('Rotate Screen'),
              ),
              const PopupMenuItem(
                value: 'builtin_netflix',
                child: Text('Enable/Disable Built-in Netflix'),
              ),
              const PopupMenuItem(
                value: 'check_updates',
                child: Text('Check For Updates'),
              ),
            ],
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: colorScheme.onPrimary.withValues(alpha: 0.14),
                border: Border.all(
                  color: colorScheme.onPrimary.withValues(alpha: 0.36),
                ),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.build, size: 18, color: colorScheme.onPrimary),
                  const SizedBox(width: 6),
                  Text(
                    "Tools",
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_drop_down, color: colorScheme.onPrimary),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: provider.isBusy ? null : () => provider.refresh(),
            tooltip: "Refresh Devices",
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          final content = Padding(
            padding: EdgeInsets.all(isDesktop ? 16 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _UpdateNotice(provider: provider),
                if (provider.isCheckingForUpdate)
                  const LinearProgressIndicator(minHeight: 2),
                if (provider.isUpdateAvailable ||
                    provider.updateCheckError != null ||
                    provider.isCheckingForUpdate)
                  const SizedBox(height: 10),
                _StatusBanner(message: statusText, isError: statusIsError),
                const SizedBox(height: 12),
                if (isDesktop)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 310,
                          child: SingleChildScrollView(
                            primary: false,
                            child: _DeviceRail(provider: provider),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _CatalogAndLog(
                            provider: provider,
                            listHeight: 400,
                            fitHeight: true,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  _DeviceRail(provider: provider),
                  const SizedBox(height: 16),
                  _CatalogAndLog(provider: provider, listHeight: 300),
                ],
              ],
            ),
          );
          return isDesktop ? content : SingleChildScrollView(child: content);
        },
      ),
    );
  }
}

class _UpdateNotice extends StatelessWidget {
  final AppProvider provider;

  const _UpdateNotice({required this.provider});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (provider.isUpdateAvailable) {
      return Card(
        color: colorScheme.tertiaryContainer,
        child: ListTile(
          dense: true,
          leading: Icon(
            Icons.system_update,
            color: colorScheme.onTertiaryContainer,
          ),
          title: Text(
            'Update available: ${provider.latestAppVersion}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'Current version: ${provider.currentAppVersion ?? 'unknown'}',
          ),
          trailing: TextButton(
            onPressed: provider.openReleasesPage,
            child: const Text('View release'),
          ),
        ),
      );
    }
    if (provider.updateCheckError != null) {
      return Card(
        color: colorScheme.errorContainer,
        child: ListTile(
          dense: true,
          leading: Icon(
            Icons.warning_amber_rounded,
            color: colorScheme.onErrorContainer,
          ),
          title: const Text('Could not check for updates'),
          subtitle: Text(provider.updateCheckError!),
          trailing: TextButton(
            onPressed: provider.isCheckingForUpdate
                ? null
                : provider.checkForUpdates,
            child: const Text('Retry'),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _DeviceRail extends StatelessWidget {
  final AppProvider provider;

  const _DeviceRail({required this.provider});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasDevice = provider.selectedDevice != null;
    final canUseDevice = hasDevice && !provider.isBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(
          icon: Icons.devices_outlined,
          label: 'Connected device',
        ),
        const SizedBox(height: 6),
        if (provider.devices.isNotEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey(provider.selectedDevice?.serial),
            initialValue: provider.selectedDevice?.serial,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Target device',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: provider.devices
                .map(
                  (device) => DropdownMenuItem(
                    value: device.serial,
                    child: Text(
                      device.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: provider.isBusy
                ? null
                : (serial) {
                    if (serial == null) return;
                    provider.selectDevice(
                      provider.devices.firstWhere(
                        (device) => device.serial == serial,
                      ),
                    );
                  },
          )
        else
          Text(
            'No ADB devices detected.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 8),
        DeviceCapabilitiesTile(
          device: provider.selectedDevice,
          resources: provider.selectedDeviceResources,
          refreshing: provider.isRefreshingDeviceResources,
          onRefresh: provider.isBusy || provider.isRefreshingDeviceResources
              ? null
              : () => provider.refreshDeviceResources(force: true),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final steps = await provider.loadGuide('usb_debug_steps.json');
                if (!context.mounted) return;
                showDialog(
                  context: context,
                  builder: (_) =>
                      GuideDialog(title: 'Developer Mode Guide', steps: steps),
                );
              },
              icon: const Icon(Icons.help_outline, size: 18),
              label: const Text('Setup guide'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const WirelessConnectScreen(),
                ),
              ),
              icon: const Icon(Icons.wifi_outlined, size: 18),
              label: const Text('Wi-Fi ADB'),
            ),
          ],
        ),
        const Divider(height: 28),
        const _SectionHeader(icon: Icons.perm_media_outlined, label: 'Media'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Tooltip(
                message: provider.saveLocation,
                child: Text(
                  provider.saveLocation,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.folder_outlined),
              onPressed: provider.openSaveLocation,
              tooltip: 'Open save folder',
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: provider.chooseSaveLocation,
              tooltip: 'Change save folder',
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: canUseDevice ? provider.takeScreenshot : null,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Screenshot'),
            ),
            OutlinedButton.icon(
              onPressed: canUseDevice
                  ? () => showDialog(
                      context: context,
                      builder: (_) => const ScreenMirrorDialog(),
                    )
                  : null,
              icon: const Icon(Icons.desktop_windows_outlined, size: 18),
              label: const Text('View'),
            ),
            OutlinedButton.icon(
              onPressed: canUseDevice ? provider.toggleRecording : null,
              icon: Icon(
                provider.isRecording ? Icons.stop : Icons.videocam_outlined,
                size: 18,
              ),
              label: Text(provider.isRecording ? 'Stop' : 'Record'),
              style: provider.isRecording
                  ? OutlinedButton.styleFrom(
                      backgroundColor: colorScheme.errorContainer,
                      foregroundColor: colorScheme.onErrorContainer,
                    )
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _CatalogAndLog extends StatelessWidget {
  final AppProvider provider;
  final double listHeight;
  final bool fitHeight;

  const _CatalogAndLog({
    required this.provider,
    required this.listHeight,
    this.fitHeight = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canInstall = provider.selectedDevice != null && !provider.isBusy;
    final appList = RecessedPane(
      child: AppListWidget(
        onInstallRecommended: canInstall
            ? () => provider.installRecommendedApps(
                (appName) => _showReinstallDialog(context, appName),
              )
            : null,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // In short windows or with large accessibility text, keep controls
        // reachable by scrolling instead of shrinking panels to nothing.
        final minimumHeight =
            420 * MediaQuery.textScalerOf(context).scale(14) / 14;
        final fitted = fitHeight && constraints.maxHeight >= minimumHeight;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: _SectionHeader(
                    icon: Icons.apps_outlined,
                    label: 'Compatible applications',
                  ),
                ),
                IconButton(
                  icon: provider.isCheckingCatalog
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onPressed:
                      provider.selectedDevice == null ||
                          provider.isCheckingCatalog
                      ? null
                      : provider.refreshCatalog,
                  tooltip: 'Refresh compatibility catalog',
                ),
              ],
            ),
            if (provider.catalogStatus != null) ...[
              const SizedBox(height: 2),
              Text(
                provider.catalogStatus!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 6),
            if (fitted)
              Expanded(flex: 3, child: appList)
            else
              SizedBox(height: listHeight, child: appList),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: canInstall && provider.selectedAppCount > 0
                      ? () => provider.installSelectedApps(
                          (appName) => _showReinstallDialog(context, appName),
                        )
                      : null,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text(
                    'Install selected (${provider.selectedAppCount})',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: canInstall
                      ? () => provider.installLocalApk(
                          (appName) => _showReinstallDialog(context, appName),
                        )
                      : null,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Install local APK'),
                ),
              ],
            ),
            const Divider(height: 28),
            Row(
              children: [
                const Expanded(
                  child: _SectionHeader(
                    icon: Icons.terminal_outlined,
                    label: 'ADB activity',
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      provider.logs.isEmpty || provider.isExportingAdbActivity
                      ? null
                      : () async {
                          final saved = await provider.exportAdbActivity();
                          if (!context.mounted || saved == null) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('ADB activity saved to $saved'),
                            ),
                          );
                        },
                  icon: const Icon(Icons.save_alt, size: 18),
                  label: Text(
                    provider.isExportingAdbActivity ? 'Exporting…' : 'Export',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (fitted)
              const Expanded(flex: 2, child: LogPanel())
            else
              const SizedBox(height: 170, child: LogPanel()),
          ],
        );
        return fitHeight && !fitted
            ? SingleChildScrollView(primary: false, child: content)
            : content;
      },
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String message;
  final bool isError;

  const _StatusBanner({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = isError ? colorScheme.error : AppColors.success;
    final background = isError
        ? colorScheme.errorContainer
        : AppColors.success.withValues(alpha: 0.10);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: foreground.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle,
            color: foreground,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

Future<bool> _showReinstallDialog(BuildContext context, String appName) async {
  final colorScheme = Theme.of(context).colorScheme;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Signature Mismatch'),
          content: Text(
            'The installed version of $appName has a different signature. '
            'Do you want to uninstall the old version and continue installing the new one?\n\n'
            'This will delete the app data.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: colorScheme.error),
              child: const Text('Uninstall & Reinstall'),
            ),
          ],
        ),
      ) ??
      false;
}

void _showRotateScreenDialog(BuildContext context, AppProvider provider) async {
  const labels = [
    '0° (Natural)',
    '90° (Landscape)',
    '180° (Inverted)',
    '270° (Landscape Flipped)',
  ];
  const icons = [
    Icons.stay_current_portrait,
    Icons.stay_current_landscape,
    Icons.stay_current_portrait,
    Icons.stay_current_landscape,
  ];

  int currentRotation = await provider.getRotation();
  bool autoRotate = await provider.getAutoRotation();

  if (!context.mounted) return;
  final colorScheme = Theme.of(context).colorScheme;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text("Rotate Screen"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icons[currentRotation],
              size: 64,
              color: autoRotate ? colorScheme.outline : colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              labels[currentRotation],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.rotate_right),
              label: const Text("Rotate"),
              onPressed: autoRotate
                  ? null
                  : () async {
                      final next = (currentRotation + 1) % 4;
                      final success = await provider.setRotation(next);
                      if (success) {
                        setDialogState(() {
                          currentRotation = next;
                          autoRotate = false;
                        });
                      }
                    },
            ),
            const SizedBox(height: 16),
            const Divider(),
            SwitchListTile(
              title: const Text("Auto-rotate"),
              subtitle: const Text("Use accelerometer to rotate"),
              value: autoRotate,
              onChanged: (value) async {
                final success = await provider.setAutoRotation(value);
                if (success) {
                  setDialogState(() {
                    autoRotate = value;
                  });
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Done"),
          ),
        ],
      ),
    ),
  );
}

void _showBuiltinNetflixDialog(BuildContext context, AppProvider provider) {
  final colorScheme = Theme.of(context).colorScheme;
  final serial = provider.selectedDevice!.serial;
  final deviceName = provider.selectedDevice!.name ?? serial;

  Future<void> runNetflixTool(bool enabled) async {
    Navigator.pop(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                enabled
                    ? "Enabling built-in Netflix..."
                    : "Restoring Netflix defaults...",
              ),
            ),
          ],
        ),
      ),
    );

    final results = await provider.setBuiltinNetflixEnabled(enabled);

    if (context.mounted) Navigator.pop(context);
    if (!context.mounted) return;

    final allOk = results.isNotEmpty && results.values.every((v) => v);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          allOk ? Icons.check_circle : Icons.warning_amber,
          color: allOk ? AppColors.success : AppColors.warning,
          size: 48,
        ),
        title: Text(allOk ? "Netflix Updated" : "Netflix Update Incomplete"),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: results.isEmpty
                ? [
                    const Text(
                      "No commands were run. Make sure a supported device is connected.",
                    ),
                  ]
                : results.entries
                      .map(
                        (entry) => Row(
                          children: [
                            Icon(
                              entry.value ? Icons.check : Icons.close,
                              color: entry.value
                                  ? AppColors.success
                                  : colorScheme.error,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(entry.key)),
                          ],
                        ),
                      )
                      .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Built-in Netflix"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Target device: $deviceName"),
          const SizedBox(height: 12),
          const Text(
            "Enable applies the Netflix Doze/appops exceptions and disables "
            "com.onepeloton.systempluginui so the built-in Netflix launcher "
            "is not killed by the OEM subscription check.",
          ),
          const SizedBox(height: 12),
          const Text(
            "Caution: disabling com.onepeloton.systempluginui can break "
            "OEM/system features. Restore defaults if anything misbehaves.",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () => runNetflixTool(false),
          child: const Text("Restore Defaults"),
        ),
        ElevatedButton(
          onPressed: () => runNetflixTool(true),
          child: const Text("Enable Netflix"),
        ),
      ],
    ),
  );
}

void _showDefaultLauncherDialog(
  BuildContext context,
  AppProvider provider,
) async {
  final colorScheme = Theme.of(context).colorScheme;
  // Show loading dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text("Detecting installed launchers..."),
        ],
      ),
    ),
  );

  final launchers = await provider.getInstalledLaunchers();
  final currentDefaultComponent = await provider.getDefaultLauncherComponent();

  if (context.mounted) Navigator.pop(context); // Close loading
  if (!context.mounted) return;

  if (launchers.isEmpty) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("No Launchers Found"),
        content: const Text(
          "Could not detect any launcher apps on the device.\n\n"
          "Install a launcher (like Nova or Kvaesitso) from the app list first.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
    return;
  }

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Set Default Launcher"),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Select a launcher and OpenPelo will set it as the default HOME app using ADB.",
              style: TextStyle(fontSize: 13),
            ),
            if (currentDefaultComponent != null) ...[
              const SizedBox(height: 8),
              Text(
                "Current default: $currentDefaultComponent",
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...launchers.map((launcher) {
              final pkg = launcher['package'] ?? '';
              final label = launcher['label'] ?? pkg;
              final component = launcher['component'] ?? '';
              final isCurrentDefault =
                  currentDefaultComponent != null &&
                  component == currentDefaultComponent;

              return ListTile(
                tileColor: isCurrentDefault
                    ? AppColors.success.withValues(alpha: 0.12)
                    : null,
                leading: Icon(
                  isCurrentDefault ? Icons.check_circle : Icons.home_outlined,
                  color: isCurrentDefault ? AppColors.success : null,
                ),
                title: Text(
                  isCurrentDefault ? "$label (Current Default)" : label,
                  style: TextStyle(
                    fontWeight: isCurrentDefault
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  pkg,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    if (component.isEmpty) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              "Could not determine launcher activity component.",
                            ),
                            backgroundColor: colorScheme.error,
                          ),
                        );
                      }
                      return;
                    }

                    final beforeComponent = await provider
                        .getDefaultLauncherComponent();
                    final success = await provider.setDefaultLauncher(
                      component,
                    );
                    final afterComponent = await provider
                        .getDefaultLauncherComponent();
                    final verified = success && afterComponent == component;

                    String feedback;
                    if (verified) {
                      feedback =
                          "Default launcher updated.\nBefore: ${beforeComponent ?? 'Unknown'}\nAfter: ${afterComponent ?? 'Unknown'}";
                    } else if (success) {
                      feedback =
                          "Launcher command sent, but verification did not match.\nBefore: ${beforeComponent ?? 'Unknown'}\nAfter: ${afterComponent ?? 'Unknown'}\nExpected: $component";
                    } else {
                      feedback =
                          "Failed to set $label as default launcher.\nBefore: ${beforeComponent ?? 'Unknown'}\nAfter: ${afterComponent ?? 'Unknown'}";
                    }

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(feedback),
                          backgroundColor: verified
                              ? AppColors.success
                              : colorScheme.error,
                          duration: const Duration(seconds: 7),
                        ),
                      );
                    }
                  },
                  child: const Text("Set Default"),
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text("Close"),
        ),
      ],
    ),
  );
}

void _showDeveloperOptionsDialog(BuildContext context, AppProvider provider) {
  final colorScheme = Theme.of(context).colorScheme;
  final serial = provider.selectedDevice!.serial;
  final deviceName = provider.selectedDevice!.name ?? serial;

  // Track checkbox state in the dialog
  bool wirelessDebugging = true;
  bool stayAwake = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text("Enable Developer Settings"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Select settings to enable on $deviceName:",
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: wirelessDebugging,
              onChanged: (v) =>
                  setDialogState(() => wirelessDebugging = v ?? false),
              title: const Text("Wireless Debugging"),
              subtitle: const Text(
                "Adds quick settings tile & enables wireless ADB",
              ),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
            CheckboxListTile(
              value: stayAwake,
              onChanged: (v) => setDialogState(() => stayAwake = v ?? false),
              title: const Text("Stay Awake While Charging"),
              subtitle: const Text(
                "Prevents screen from sleeping when plugged in",
              ),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: (!wirelessDebugging && !stayAwake)
                ? null
                : () async {
                    Navigator.pop(ctx);

                    // Show progress
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const AlertDialog(
                        content: Row(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(width: 16),
                            Text("Applying settings..."),
                          ],
                        ),
                      ),
                    );

                    final results = await provider.enableDeveloperSettings(
                      serial: serial,
                      wirelessDebugging: wirelessDebugging,
                      stayAwake: stayAwake,
                    );

                    if (context.mounted) {
                      Navigator.pop(context); // Close progress
                    }

                    if (context.mounted) {
                      final allOk = results.values.every((v) => v);
                      showDialog(
                        context: context,
                        builder: (ctx2) => AlertDialog(
                          icon: Icon(
                            allOk ? Icons.check_circle : Icons.warning_amber,
                            color: allOk
                                ? AppColors.success
                                : AppColors.warning,
                            size: 48,
                          ),
                          title: Text(
                            allOk ? "Settings Applied" : "Partial Success",
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: results.entries
                                .map(
                                  (e) => Row(
                                    children: [
                                      Icon(
                                        e.value ? Icons.check : Icons.close,
                                        color: e.value
                                            ? AppColors.success
                                            : colorScheme.error,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(e.key)),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx2),
                              child: const Text("OK"),
                            ),
                          ],
                        ),
                      );
                    }
                  },
            child: const Text("Apply"),
          ),
        ],
      ),
    ),
  );
}
