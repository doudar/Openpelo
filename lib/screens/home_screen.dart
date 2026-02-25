import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/log_panel.dart';
import '../widgets/app_list_widget.dart';
import '../widgets/guide_dialog.dart';
import '../widgets/peloton_uninstaller_dialog.dart';
import '../widgets/screen_mirror_dialog.dart';
import 'wireless_connect_screen.dart';

const _taglines = [
  'Your Machine, Your Apps',
  'Free Your Workout',
  'Unlock Your Machine',
  'Free Your Fitness Screen',
  'Ride Without Limits',
];

final _tagline = _taglines[Random().nextInt(_taglines.length)];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Text(
                "OpenPelo - $_tagline",
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Version: ${provider.currentAppVersion ?? '...'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'uninstall') {
                if (provider.selectedDevice == null) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No device selected")));
                } else {
                   showDialog(context: context, builder: (_) => const PelotonUninstallerDialog());
                }
              } else if (value == 'dev_options') {
                if (provider.selectedDevice == null) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No device selected")));
                } else {
                   _showDeveloperOptionsDialog(context, provider);
                }
              } else if (value == 'default_launcher') {
                if (provider.selectedDevice == null) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No device selected")));
                } else {
                   _showDefaultLauncherDialog(context, provider);
                }
              } else if (value == 'rotate_screen') {
                if (provider.selectedDevice == null) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No device selected")));
                } else {
                   _showRotateScreenDialog(context, provider);
                }
              } else if (value == 'check_updates') {
                await provider.checkForUpdates();
              }
            },
            itemBuilder: (context) => [
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
                value: 'check_updates',
                child: Text('Check For Updates'),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(child: Text("Tools", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: provider.isBusy ? null : () => provider.refresh(),
            tooltip: "Refresh Devices",
          ),
        ],
      ),
      // Use LayoutBuilder to decide between scrollable (mobile/small) and expanded (desktop/large)
      body: LayoutBuilder(
        builder: (context, constraints) {
          // If height is small (typical mobile landscape or bad resizing) or just generally mobile
          // we prefer scrolling. 
          // However, to strictly follow "overflow on Android" request, let's just use SingleChildScrollView 
          // everywhere but try to be smart about the list height.
          
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (provider.isUpdateAvailable)
                    Card(
                      color: Colors.amber[50],
                      child: ListTile(
                        leading: const Icon(Icons.system_update),
                        title: Text(
                          'Update available: ${provider.latestAppVersion}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Current version: ${provider.currentAppVersion ?? 'unknown'}',
                        ),
                        trailing: TextButton(
                          onPressed: provider.openReleasesPage,
                          child: const Text('View Release'),
                        ),
                      ),
                    ),
                  if (provider.updateCheckError != null)
                    Card(
                      color: Colors.red[50],
                      child: ListTile(
                        leading: const Icon(Icons.warning_amber_rounded),
                        title: const Text('Could not check for updates'),
                        subtitle: Text(provider.updateCheckError!),
                        trailing: TextButton(
                          onPressed: provider.isCheckingForUpdate
                              ? null
                              : provider.checkForUpdates,
                          child: const Text('Retry'),
                        ),
                      ),
                    ),
                  if (provider.isCheckingForUpdate)
                    const LinearProgressIndicator(minHeight: 2),
                  if (provider.isUpdateAvailable ||
                      provider.updateCheckError != null ||
                      provider.isCheckingForUpdate)
                    const SizedBox(height: 10),
                  // Status & Device Selection
                   Row(
                    children: [
                      Expanded(
                        child: Text(provider.statusMessage, 
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: provider.statusMessage.contains('❌') ? Colors.red : Colors.green[800],
                            overflow: TextOverflow.ellipsis
                          )),
                      ),
                      TextButton(
                        onPressed: () async {
                          final steps = await provider.loadGuide('usb_debug_steps.json');
                          if (context.mounted) {
                              showDialog(context: context, builder: (_) => GuideDialog(title: "Developer Mode Guide", steps: steps));
                          }
                        },
                        style: TextButton.styleFrom(backgroundColor: Colors.lightBlue[50]),
                        child: const Text("Developer Mode Guide"),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const WirelessConnectScreen())
                          );
                        },
                        style: TextButton.styleFrom(backgroundColor: Colors.amber[50]),
                        child: const Text("📶 Connect via WiFi"),
                      ),
                      if (provider.isBusy)
                        const Padding(
                          padding: EdgeInsets.only(left: 10.0),
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (provider.devices.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: provider.selectedDevice?.serial,
                      decoration: const InputDecoration(
                        labelText: "Target Device",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      ),
                      items: provider.devices.map((d) {
                        return DropdownMenuItem(
                          value: d.serial,
                          child: Text(d.displayName),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          final dev = provider.devices.firstWhere((d) => d.serial == val);
                          provider.selectDevice(dev);
                        }
                      },
                    ),
                  
                  const SizedBox(height: 10),
                  
                  // ADB Log
                  const Text("ADB Messages", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  const SizedBox(
                    height: 150,
                    child: LogPanel(),
                  ),
                  
                  const SizedBox(height: 10),
                  
                  // Apps
                  const Text("Available Apps", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  
                  // Use a fixed height container for the list so the page scrolls if needed
                  const SizedBox(
                    height: 300, 
                    child: Card(
                      child: AppListWidget(),
                    ),
                  ),
                  
                  const SizedBox(height: 10),
                  
                  // Action Buttons
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        onPressed: (!provider.isBusy && provider.selectedDevice != null) 
                          ? () => provider.installSelectedApps((appName) => _showReinstallDialog(context, appName))
                          : null,
                        icon: const Icon(Icons.download),
                        label: const Text("Install Selected Apps"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.lightGreen[100], foregroundColor: Colors.black),
                      ),
                      ElevatedButton.icon(
                        onPressed: (!provider.isBusy && provider.selectedDevice != null)
                          ? () => provider.installLocalApk((appName) => _showReinstallDialog(context, appName))
                          : null,
                        icon: const Icon(Icons.folder_open),
                        label: const Text("Install Local APK"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlue[100], foregroundColor: Colors.black),
                      ),
                    ],
                  ),
                  
                  const Divider(height: 30),
                  
                  // Media Settings
                  Text("Media Settings", style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Text("Save Location: "),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                          child: Text(provider.saveLocation, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.folder), onPressed: provider.openSaveLocation, tooltip: "Open Folder"),
                      IconButton(icon: const Icon(Icons.edit), onPressed: provider.chooseSaveLocation, tooltip: "Change Location"),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: (!provider.isBusy && provider.selectedDevice != null)
                          ? provider.takeScreenshot
                          : null,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text("Take Screenshot"),
                      ),
                      OutlinedButton.icon(
                        onPressed: (!provider.isBusy && provider.selectedDevice != null)
                          ? () {
                             showDialog(context: context, builder: (_) => const ScreenMirrorDialog());
                          }
                          : null,
                        icon: const Icon(Icons.monitor),
                        label: const Text("View Screen"),
                      ),
                      OutlinedButton.icon(
                        onPressed: (!provider.isBusy && provider.selectedDevice != null)
                          ? provider.toggleRecording
                          : null,
                            icon: Icon(provider.isRecording ? Icons.stop : Icons.videocam),
                          label: Text(provider.isRecording ? "Stop Rec" : "Record"),
                          style: provider.isRecording 
                            ? OutlinedButton.styleFrom(backgroundColor: Colors.red[50], foregroundColor: Colors.red)
                            : null,
                        ),
                      ],
                    ),
                  ],
                ),
            ),
          );
        }
      ),
    );
  }
}
  Future<bool> _showReinstallDialog(BuildContext context, String appName) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Signature Mismatch'),
        content: Text(
          'The installed version of $appName has a different signature. '
          'Do you want to uninstall the old version and continue installing the new one?\n\n'
          'This will delete the app data.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Uninstall & Reinstall'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showRotateScreenDialog(BuildContext context, AppProvider provider) async {
    const labels = ['0° (Natural)', '90° (Landscape)', '180° (Inverted)', '270° (Landscape Flipped)'];
    const icons = [Icons.stay_current_portrait, Icons.stay_current_landscape, Icons.stay_current_portrait, Icons.stay_current_landscape];

    int currentRotation = await provider.getRotation();
    bool autoRotate = await provider.getAutoRotation();

    if (!context.mounted) return;

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
                color: autoRotate ? Colors.grey : Colors.blue,
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
                onPressed: autoRotate ? null : () async {
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

  void _showDefaultLauncherDialog(BuildContext context, AppProvider provider) async {
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

    if (context.mounted) Navigator.pop(context); // Close loading
    if (!context.mounted) return;

    if (launchers.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("No Launchers Found"),
          content: const Text(
            "Could not detect any launcher apps on the device.\n\n"
            "Install a launcher (like Nova or Kvaesitso) from the app list first."
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
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
                "Select a launcher to open its settings on the device. "
                "From there, enable the \"Home app\" or \"Set as default\" permission.",
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              ...launchers.map((launcher) {
                final pkg = launcher['package'] ?? '';
                final label = launcher['label'] ?? pkg;

                return ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: Text(label),
                  subtitle: Text(
                    pkg,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  trailing: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final success = await provider.openAppSettings(pkg);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success
                                ? "Opened settings for $label on device. Set it as the default home app there."
                                : "Failed to open settings for $label."),
                            backgroundColor: success ? Colors.green : Colors.red,
                            duration: const Duration(seconds: 5),
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
              Text("Select settings to enable on $deviceName:",
                style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: wirelessDebugging,
                onChanged: (v) => setDialogState(() => wirelessDebugging = v ?? false),
                title: const Text("Wireless Debugging"),
                subtitle: const Text("Adds quick settings tile & enables wireless ADB"),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
              CheckboxListTile(
                value: stayAwake,
                onChanged: (v) => setDialogState(() => stayAwake = v ?? false),
                title: const Text("Stay Awake While Charging"),
                subtitle: const Text("Prevents screen from sleeping when plugged in"),
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

                      if (context.mounted) Navigator.pop(context); // Close progress

                      if (context.mounted) {
                        final allOk = results.values.every((v) => v);
                        showDialog(
                          context: context,
                          builder: (ctx2) => AlertDialog(
                            icon: Icon(
                              allOk ? Icons.check_circle : Icons.warning_amber,
                              color: allOk ? Colors.green : Colors.orange,
                              size: 48,
                            ),
                            title: Text(allOk ? "Settings Applied" : "Partial Success"),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: results.entries.map((e) => Row(
                                children: [
                                  Icon(e.value ? Icons.check : Icons.close,
                                    color: e.value ? Colors.green : Colors.red, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(e.key)),
                                ],
                              )).toList(),
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
