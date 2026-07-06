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
    final colorScheme = Theme.of(context).colorScheme;
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        if (provider.availableApps.isEmpty) {
          return Center(
            child: Text(
              provider.selectedDevice == null 
                ? "Select a device to view compatible applications."
                : "No compatible applications found for this device.",
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          );
        }

        final apps = provider.availableApps.values.toList();
        return Scrollbar(
          thumbVisibility: true,
          trackVisibility: true,
          controller: _scrollController,
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: apps.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              indent: 16,
              endIndent: 56,
              color: colorScheme.outlineVariant.withValues(alpha: 0.58),
            ),
            itemBuilder: (context, index) {
              final app = apps[index];
              return CheckboxListTile(
                contentPadding: const EdgeInsets.only(left: 16, right: 24),
                visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
                title: Text(
                  app.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                subtitle: Text(
                  app.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
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
