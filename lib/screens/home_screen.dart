import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/log_panel.dart';
import '../widgets/app_list_widget.dart';
import '../widgets/guide_dialog.dart';
import '../widgets/peloton_uninstaller_dialog.dart';
import '../widgets/screen_mirror_dialog.dart';
import 'wireless_connect_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Expanded(
              child: Text(
                "OpenPelo - Free Your Peloton",
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
}
