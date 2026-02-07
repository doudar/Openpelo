import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class PelotonUninstallerDialog extends StatefulWidget {
  const PelotonUninstallerDialog({super.key});

  @override
  State<PelotonUninstallerDialog> createState() => _PelotonUninstallerDialogState();
}

class _PelotonUninstallerDialogState extends State<PelotonUninstallerDialog> {
  List<String> packages = [];
  final Set<String> _selected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPackages();
    });
  }

  void _loadPackages() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final pd = await provider.scanPelotonPackages();
    if (mounted) {
      setState(() {
        packages = pd;
        _loading = false;
      });
    }
  }

  void _toggleAll(bool select) {
    setState(() {
      if (select) {
        _selected.addAll(packages);
      } else {
        _selected.clear();
      }
    });
  }

  void _confirmAndUninstall() async {
    if (_selected.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Uninstall"),
        content: Text("Are you sure you want to uninstall ${_selected.length} packages?\n\nThis action is IRREVERSIBLE and could BRICK your device.\n\nProceed only if you know what you are doing."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Proceed"),
          ),
        ],
      )
    );

    if (confirm == true && mounted) {
       final provider = Provider.of<AppProvider>(context, listen: false);
       Navigator.of(context).pop(); // Close list dialog
       
       final result = await provider.uninstallPelotonPackages(_selected.toList());
       
       // Show result snackbar or dialog? The provider logs it, but a summary is nice.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Uninstall Peloton Apps"),
      content: SizedBox(
        width: 500,
        height: 600,
        child: Column(
          children: [
            // Warning
             Container(
              padding: const EdgeInsets.all(10),
              color: Colors.red[50], // Light red background
              child: const Column(
                children: [
                   Text("⚠️ WARNING: IRREVERSIBLE ACTION ⚠️", 
                     style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                   SizedBox(height: 5),
                   Text("Uninstalling core Peloton system applications may render your tablet completely UNUSABLE (brick it).",
                     textAlign: TextAlign.center, style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
            
            const SizedBox(height: 10),
            
            // Toolbar
            Row(
              children: [
                TextButton(onPressed: () => _toggleAll(true), child: const Text("Select All")),
                TextButton(onPressed: () => _toggleAll(false), child: const Text("Deselect All")),
              ],
            ),
            
            const Divider(),

            // List
            Expanded(
              child: _loading 
                ? const Center(child: CircularProgressIndicator())
                : packages.isEmpty 
                   ? const Center(child: Text("No Peloton packages found matching criteria."))
                   : ListView.builder(
                       itemCount: packages.length,
                       itemBuilder: (ctx, i) {
                         final pkg = packages[i];
                         final isSelected = _selected.contains(pkg);
                         return CheckboxListTile(
                            value: isSelected,
                            title: Text(pkg, style: const TextStyle(fontSize: 13)),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selected.add(pkg);
                                } else {
                                  _selected.remove(pkg);
                                }
                              });
                            },
                         );
                       },
                   ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ElevatedButton.icon(
          onPressed: _selected.isNotEmpty ? _confirmAndUninstall : null,
          icon: const Icon(Icons.delete),
          label: const Text("UNINSTALL SELECTED"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red, 
            foregroundColor: Colors.white
          ),
        ),
      ],
    );
  }
}
