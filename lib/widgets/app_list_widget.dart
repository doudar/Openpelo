import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class AppListWidget extends StatefulWidget {
  const AppListWidget({super.key});

  @override
  State<AppListWidget> createState() => _AppListWidgetState();
}

class _AppListWidgetState extends State<AppListWidget> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        if (provider.availableApps.isEmpty) {
          return Center(
            child: Text(
              provider.selectedDevice == null 
                ? "Select a device to view compatible applications."
                : "No compatible applications found for this device.",
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }

        final apps = provider.availableApps.values.toList();
        return Scrollbar(
          thumbVisibility: true,
          trackVisibility: true,
          controller: _scrollController,
          child: ListView.builder(
            controller: _scrollController,
            itemCount: apps.length,
            itemBuilder: (context, index) {
              final app = apps[index];
              return CheckboxListTile(
                title: Text(app.name),
                subtitle: Text(app.description),
                value: app.isSelected,
                onChanged: (val) {
                  app.isSelected = val ?? false;
                  provider.notifyListeners(); // A bit hacky to modify object then notify
                },
              );
            },
          ),
        );
      },
    );
  }
}
