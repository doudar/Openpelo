import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Select Discovered Device"),
        children: devices.map((d) {
          return SimpleDialogOption(
            onPressed: () {
               _ipController.text = d['ip'] ?? '';
               _connectPortController.text = d['port'] ?? '';
               Navigator.pop(ctx);
            },
            child: ListTile(
              title: Text(d['name'] ?? 'Unknown'),
              subtitle: Text("${d['ip']}:${d['port']}"),
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
            builder: (context, provider, _) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: provider.isBusy ? null : _startScan,
                  icon: const Icon(Icons.search),
                  label: const Text("Scan mDNS & Port 5555"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[50]),
                ),
                // Advanced scan specific port
                TextButton(
                  onPressed: provider.isBusy ? null : () async {
                    // Ask for port
                    final portStr = await showDialog<String>(
                      context: context, 
                      builder: (ctx) {
                        final controller = TextEditingController(text: "5555");
                        return AlertDialog(
                          title: const Text("Scan Network"),
                          content: TextField(
                             controller: controller,
                             decoration: const InputDecoration(labelText: "Port"),
                             keyboardType: TextInputType.number,
                          ),
                          actions: [
                             TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                             TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text("Scan")),
                          ],
                        );
                      }
                    );
                    
                    if (portStr != null && mounted) {
                       final port = int.tryParse(portStr);
                       if (port != null) {
                          final results = await provider.scanForWirelessDevices(port: port);
                          if (mounted && results.isNotEmpty) {
                            _showDeviceSelectionDialog(results);
                          } else if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No devices found on that port.")));
                          }
                       }
                    }
                  },
                  child: const Text("Scan Custom Port")
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
          const Text("Logs", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          // We can reuse LogPanel here or just rely on main screen logs? 
          // Python shows logs in the dialog status.
          // Let's verify connection status here.
          Consumer<AppProvider>(
            builder: (context, provider, _) {
              final isConnected = provider.statusMessage.contains('✅');
              return Column(
                children: [
                  Text(
                    provider.statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isConnected ? Colors.green : Colors.black
                    ),
                  ),
                  if (isConnected)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(16),
                          ),
                          child: const Text("Done - Back to Home", style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                ],
              );
            },
          )
        ],
      ),
    );
  }
}
