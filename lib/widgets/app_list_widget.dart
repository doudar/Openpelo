import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class AppListWidget extends StatefulWidget {
  final VoidCallback? onInstallRecommended;
  const AppListWidget({super.key, this.onInstallRecommended});

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
          final message = provider.selectedDevice == null
              ? 'Select a device to check compatible applications.'
              : provider.isCheckingCatalog
              ? 'Checking APK metadata for this device…'
              : provider.catalogStatus ??
                    'No compatible applications are currently available for this device.';
          return Center(
            child: SingleChildScrollView(
              primary: false,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (provider.isCheckingCatalog)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Icon(
                        provider.selectedDevice == null
                            ? Icons.devices_other_outlined
                            : Icons.find_in_page_outlined,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    if (provider.selectedDevice != null &&
                        !provider.isCheckingCatalog) ...[
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: provider.refreshCatalog,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Refresh catalog'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        final apps = provider.visibleApps;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(provider.selectedAppCategory),
                      initialValue: provider.selectedAppCategory,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                      items: [
                        for (final category in provider.appCategories)
                          DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          ),
                      ],
                      onChanged: (category) {
                        if (category == null) return;
                        provider.setAppCategory(category);
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(0);
                        }
                      },
                    ),
                  ),
                  if (provider.selectedAppCategory == 'Recommended')
                    TextButton.icon(
                      onPressed:
                          apps.isEmpty ||
                              provider.isBusy ||
                              provider.isCheckingCatalog
                          ? null
                          : widget.onInstallRecommended,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: Text('Install all recommended (${apps.length})'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: apps.isEmpty
                  ? const SingleChildScrollView(
                      primary: false,
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No recommended apps are currently compatible and available for this device. Choose another category to browse other apps.',
                      ),
                    )
                  : Scrollbar(
                      thumbVisibility: true,
                      trackVisibility: true,
                      controller: _scrollController,
                      child: ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: apps.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 56,
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.58,
                          ),
                        ),
                        itemBuilder: (context, index) {
                          final app = apps[index];
                          final metadata = app.metadata;
                          final compatibility = metadata == null
                              ? ''
                              : 'API ${metadata.minSdk}+ · ${metadata.nativeAbis.isEmpty ? 'Any CPU' : metadata.nativeAbis.join(', ')}';
                          return CheckboxListTile(
                            contentPadding: const EdgeInsets.only(
                              left: 12,
                              right: 16,
                            ),
                            visualDensity: const VisualDensity(
                              horizontal: 0,
                              vertical: -1,
                            ),
                            title: Text(
                              app.name,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              compatibility.isEmpty
                                  ? app.description
                                  : '${app.description}\n$compatibility',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.25,
                                  ),
                            ),
                            value: app.isSelected,
                            onChanged: (val) {
                              provider.setAppSelected(app.name, val ?? false);
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
