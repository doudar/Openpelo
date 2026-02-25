import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device_model.dart';
import '../providers/app_provider.dart';

class WirelessConnectScreen extends StatefulWidget {
  const WirelessConnectScreen({super.key});

  @override
  State<WirelessConnectScreen> createState() => _WirelessConnectScreenState();
}

class _WirelessConnectScreenState extends State<WirelessConnectScreen> {
  List<Map<String, String>> steps = [];
  bool _showForm = false;
  
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _pairPortController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _connectPortController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSteps();
  }

  void _loadSteps() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final loaded = await provider.loadGuide('wireless_adb_steps.json');
    setState(() {
      steps = loaded;
    });
  }
  
  void _startScan() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final results = await provider.scanForWirelessDevices();
    if (results.isNotEmpty && mounted) {
       _showDeviceSelectionDialog(results);
    }
  }
  
  void _showDeviceSelectionDialog(List<Map<String, String>> devices) {
    // Group devices by IP so we can merge pairing + connect ports
    final Map<String, Map<String, String>> grouped = {};
    for (final d in devices) {
      final ip = d['ip'] ?? '';
      if (ip.isEmpty) continue;
      
      grouped.putIfAbsent(ip, () => {'ip': ip, 'name': d['name'] ?? 'Unknown'});
      
      final type = (d['type'] ?? '').toLowerCase();
      if (type.contains('pairing')) {
        grouped[ip]!['pairPort'] = d['port'] ?? '';
        // Prefer the name from the pairing entry (usually the most descriptive)
        grouped[ip]!['name'] = d['name'] ?? grouped[ip]!['name'] ?? 'Unknown';
      } else {
        // Connect port (_adb-tls-connect, _adb, or generic scan result)
        grouped[ip]!['connectPort'] = d['port'] ?? '';
        // Keep the name if we don't have one yet
        if (grouped[ip]!['name'] == 'Unknown') {
          grouped[ip]!['name'] = d['name'] ?? 'Unknown';
        }
      }
    }
    
    // Build display list
    final groupedDevices = grouped.values.toList();
    
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Select Discovered Device"),
        children: groupedDevices.map((d) {
          final ip = d['ip'] ?? '';
          final name = d['name'] ?? 'Unknown';
          final pairPort = d['pairPort'];
          final connectPort = d['connectPort'];
          
          return SimpleDialogOption(
            onPressed: () {
               _ipController.text = ip;
               if (pairPort != null) _pairPortController.text = pairPort;
               if (connectPort != null) _connectPortController.text = connectPort;
               Navigator.pop(ctx);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(ip, style: TextStyle(color: Colors.grey[700])),
                  if (pairPort != null)
                    Text('Pair port: $pairPort', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  if (connectPort != null)
                    Text('Connect port: $connectPort', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                ],
              ),
            ),
          );
        }).toList(),
      )
    );
  }

  void _connect() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    await provider.connectWireless(
      _ipController.text.trim(),
      _pairPortController.text.trim(),
      _codeController.text.trim(),
      _connectPortController.text.trim(),
    );
  }

  void _showPairViaUsbDialog() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    
    // Find USB-connected devices
    final usbDevices = provider.devices.where((d) => d.transport == 'usb').toList();
    
    if (usbDevices.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("No USB Device Found"),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("To use this feature:"),
              SizedBox(height: 12),
              Text("1. Enable Developer Mode on your Peloton\n"
                   "   (Settings → Device Preferences → tap Build Number 7 times)"),
              SizedBox(height: 8),
              Text("2. Enable USB Debugging\n"
                   "   (Settings → Developer Options → USB Debugging)"),
              SizedBox(height: 8),
              Text("3. Connect a USB cable from your computer to the Peloton"),
              SizedBox(height: 8),
              Text("4. Accept the \"Allow USB debugging\" prompt on the Peloton"),
              SizedBox(height: 8),
              Text("5. Press Refresh on the home screen, then try again"),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
          ],
        ),
      );
      return;
    }
    
    // If multiple USB devices, let user pick; otherwise use the only one
    if (usbDevices.length == 1) {
      _performUsbWirelessSetup(usbDevices.first);
    } else {
      showDialog(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text("Select USB Device"),
          children: usbDevices.map((d) => SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _performUsbWirelessSetup(d);
            },
            child: Text(d.displayName),
          )).toList(),
        ),
      );
    }
  }

  void _performUsbWirelessSetup(DeviceModel device) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    
    // Show a progress dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Enabling Wireless ADB"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text("Setting up wireless ADB on ${device.name ?? device.serial}...\n\n"
                 "Please keep the USB cable connected until this completes."),
          ],
        ),
      ),
    );
    
    final ip = await provider.enableWirelessViaUsb(device.serial);
    
    if (!mounted) return;
    Navigator.pop(context); // Close progress dialog
    
    if (ip != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text("Wireless ADB Enabled"),
          content: Text(
            "Successfully connected wirelessly to $ip:5555.\n\n"
            "You can now unplug the USB cable — ADB will continue over WiFi."
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.error_outline, color: Colors.red, size: 48),
          title: const Text("Setup Failed"),
          content: const Text(
            "Could not determine the device's WiFi IP address.\n\n"
            "Make sure the device is connected to a WiFi network, "
            "then try again."
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
  }

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Wireless Connection"),
        leading: _showForm 
          ? IconButton(
              icon: const Icon(Icons.arrow_back), 
              onPressed: () => setState(() => _showForm = false)
            ) 
          : null, // Default back button
      ),
      body: _showForm ? _buildConnectionForm() : _buildGuideView(),
    );
  }

  Widget _buildGuideView() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text("Follow these steps to enable Wireless Debugging:", 
                   style: Theme.of(context).textTheme.titleLarge),
                 const SizedBox(height: 20),
                 ...steps.asMap().entries.map((entry) {
                   final index = entry.key;
                   final step = entry.value;
                   return Padding(
                     padding: const EdgeInsets.only(bottom: 16.0),
                     child: ListTile(
                        leading: CircleAvatar(child: Text("${index + 1}")),
                        title: Text(step['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(step['description'] ?? ''),
                     ),
                   );
                 }).toList(),
               ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => _showForm = true),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white
              ),
              child: const Text("I'm Ready - Connect Device", style: TextStyle(fontSize: 16)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Enter Connection Details", style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          const Text("Enter the IP address, pairing code, and ports from the Wireless Debugging screen on your Peloton."),
          const SizedBox(height: 20),
          
          Consumer<AppProvider>(
            builder: (context, provider, _) => Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: provider.isBusy ? null : _startScan,
                    icon: const Icon(Icons.search),
                    label: const Text("Scan for Devices"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[50]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: provider.isBusy ? null : _showPairViaUsbDialog,
                    icon: const Icon(Icons.usb),
                    label: const Text("Pair using USB"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[50]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),

          TextField(
            controller: _ipController,
            decoration: const InputDecoration(labelText: "IP Address", border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pairPortController,
            decoration: const InputDecoration(
              labelText: "Pairing Port (from pairing dialog)", 
              border: OutlineInputBorder(),
              helperText: "Required only for initial pairing"
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: "Pairing Code", 
              border: OutlineInputBorder(),
              helperText: "6-digit code from pairing dialog"
            ),
            keyboardType: TextInputType.number,
          ),
           const SizedBox(height: 10),
          TextField(
            controller: _connectPortController,
            decoration: const InputDecoration(
              labelText: "Connection Port (from main wireless settings)", 
              border: OutlineInputBorder(),
              helperText: "Usually different from pairing port"
            ),
            keyboardType: TextInputType.number,
          ),

          const SizedBox(height: 30),
          Consumer<AppProvider>(
            builder: (context, provider, child) {
              return ElevatedButton.icon(
                onPressed: provider.isBusy ? null : _connect,
                icon: provider.isBusy 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                  : const Icon(Icons.wifi),
                label: const Text("Connect"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.lightGreen[100],
                  foregroundColor: Colors.black
                ),
              );
            },
          ),
          
          const SizedBox(height: 20),
          const Divider(),
          const Text("Status", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Consumer<AppProvider>(
            builder: (context, provider, _) {
              final hasConnected = provider.devices.isNotEmpty;
              
              // Group devices by name to combine USB + WiFi entries for the same physical device
              final Map<String, List<String>> grouped = {};
              for (final device in provider.devices) {
                final name = device.name ?? device.serial;
                grouped.putIfAbsent(name, () => []);
                if (device.transport == 'wifi' && device.ip != null) {
                  grouped[name]!.add('WiFi (${device.ip}${device.port != null ? ':${device.port}' : ''})');
                } else {
                  grouped[name]!.add('USB');
                }
              }
              final uniqueCount = grouped.length;
              
              return Column(
                children: [
                  if (!hasConnected)
                    Text(
                      provider.statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black),
                    ),
                  if (hasConnected) ...[
                    Text(
                      '$uniqueCount device${uniqueCount != 1 ? 's' : ''} connected:',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    ...grouped.entries.map((entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 18),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${entry.key} • ${entry.value.join(', ')}',
                              style: const TextStyle(color: Colors.green),
                            ),
                          ),
                        ],
                      ),
                    )),
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                // Clear form for another connection
                                _ipController.clear();
                                _pairPortController.clear();
                                _codeController.clear();
                                _connectPortController.clear();
                              },
                              icon: const Icon(Icons.add),
                              label: const Text("Connect Another"),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.all(14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.check),
                              label: const Text("Done"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.all(14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          )
        ],
      ),
    );
  }
}
