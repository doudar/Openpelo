import 'package:flutter/material.dart';

import '../models/device_model.dart';
import '../models/device_resources.dart';

/// A concise, read-only summary of the currently selected Android device.
class DeviceCapabilitiesTile extends StatelessWidget {
  final DeviceModel? device;
  final DeviceResources resources;
  final bool refreshing;
  final VoidCallback? onRefresh;

  const DeviceCapabilitiesTile({
    super.key,
    required this.device,
    this.resources = const DeviceResources(),
    this.refreshing = false,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedDevice = device;

    if (selectedDevice == null) {
      return _CapabilitiesCard(
        child: Row(
          children: [
            Icon(Icons.devices_other_outlined, color: colorScheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Select a device to inspect its Android compatibility.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final androidVersion = selectedDevice.androidVersion;
    final apiLevel = selectedDevice.apiLevel;
    final abis = selectedDevice.supportedAbis;
    final cpu =
        selectedDevice.cpuDescription ??
        (abis.isNotEmpty
            ? abis.join(', ')
            : selectedDevice.abi ?? 'Not reported');

    return _CapabilitiesCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory_outlined, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selectedDevice.name ?? selectedDevice.serial,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (refreshing)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  onPressed: onRefresh,
                  tooltip: 'Refresh device details',
                  icon: const Icon(Icons.refresh, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _CapabilityRow(
            icon: Icons.android_outlined,
            label: 'Android',
            value: androidVersion ?? 'Not reported',
          ),
          const SizedBox(height: 8),
          _CapabilityRow(
            icon: Icons.tag_outlined,
            label: 'API level',
            value: apiLevel == null ? 'Not reported' : 'API $apiLevel',
          ),
          const SizedBox(height: 8),
          _CapabilityRow(
            icon: Icons.developer_board_outlined,
            label: 'CPU',
            value: cpu,
          ),
          if (selectedDevice.cpuDescription != null && abis.isNotEmpty) ...[
            const SizedBox(height: 8),
            _CapabilityRow(
              icon: Icons.memory_outlined,
              label: 'ABIs',
              value: abis.join(', '),
            ),
          ],
          const SizedBox(height: 8),
          _CapabilityRow(
            icon: Icons.speed_outlined,
            label: 'Max clock',
            value: resources.cpuMaxKhz == null
                ? _missing
                : '${(resources.cpuMaxKhz! / 1000000).toStringAsFixed(2)} GHz',
          ),
          const Divider(height: 20),
          _CapabilityRow(
            icon: Icons.memory_outlined,
            label: 'RAM',
            value: resources.ramTotalBytes == null
                ? _missing
                : '${_bytes(resources.ramTotalBytes!)} total'
                      '${resources.ramAvailableBytes == null ? '' : '\n${_bytes(resources.ramAvailableBytes!)} available'}',
          ),
          const SizedBox(height: 8),
          Tooltip(
            message:
                'App and user-data filesystem (/data), not the total physical flash capacity.',
            child: _CapabilityRow(
              icon: Icons.storage_outlined,
              label: 'Storage\n(/data)',
              value: resources.storageTotalBytes == null
                  ? _missing
                  : '${_bytes(resources.storageTotalBytes!)} total\n'
                        '${resources.storageUsedBytes == null ? 'Unknown' : _bytes(resources.storageUsedBytes!)} used\n'
                        '${resources.storageAvailableBytes == null ? 'Unknown' : _bytes(resources.storageAvailableBytes!)} available',
            ),
          ),
        ],
      ),
    );
  }

  String get _missing => refreshing ? 'Reading…' : 'Not reported';

  String _bytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MiB';
  }
}

class _CapabilitiesCard extends StatelessWidget {
  final Widget child;

  const _CapabilitiesCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _CapabilityRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        SizedBox(
          width: 66,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
