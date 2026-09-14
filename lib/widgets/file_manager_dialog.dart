import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device_file_model.dart';
import '../providers/app_provider.dart';
import '../services/device_file_parser.dart';
import '../theme/app_theme.dart';
import 'draggable_dialog.dart';

class FileManagerDialog extends StatefulWidget {
  const FileManagerDialog({super.key});

  @override
  State<FileManagerDialog> createState() => _FileManagerDialogState();
}

class _FileManagerDialogState extends State<FileManagerDialog> {
  static const _startPath = '/sdcard';
  static const _shortcuts = <String, String>{
    'sdcard': '/sdcard',
    'Download': '/sdcard/Download',
    'DCIM': '/sdcard/DCIM',
    'Movies': '/sdcard/Movies',
  };

  final TextEditingController _pathController = TextEditingController(
    text: _startPath,
  );
  String _currentPath = _startPath;
  List<DeviceFileEntry> _entries = [];
  bool _loading = true;
  bool _transferring = false;
  String? _transferLabel;
  double? _transferProgress;
  String? _statusMessage;
  bool _statusIsError = false;
  String? _lastDownloadPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _navigateTo(_startPath, fallbackToRoot: true),
    );
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  AppProvider get _provider => Provider.of<AppProvider>(context, listen: false);

  bool get _busy => _loading || _transferring;

  Future<void> _navigateTo(String path, {bool fallbackToRoot = false}) async {
    final target = path.trim().isEmpty ? '/' : joinRemotePath('/', path.trim());
    setState(() => _loading = true);
    try {
      final entries = await _provider.listDeviceFiles(target);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _currentPath = target;
        _pathController.text = target;
        _statusMessage = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (fallbackToRoot && target != '/') {
        await _navigateTo('/');
        return;
      }
      setState(() {
        _pathController.text = _currentPath;
        _loading = false;
        _statusMessage = "Could not open $target: ${_shortError(e)}";
        _statusIsError = true;
      });
    }
  }

  String _shortError(Object e) {
    final text = e.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  Future<void> _refresh() => _navigateTo(_currentPath);

  void _goUp() => _navigateTo(parentRemotePath(_currentPath));

  void _setStatus(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  Future<void> _upload() async {
    setState(() {
      _transferring = true;
      _transferLabel = "Waiting for file selection...";
      _transferProgress = null;
      _lastDownloadPath = null;
    });
    final count = await _provider.uploadFilesToDevice(
      _currentPath,
      onProgress: (done, total, name) {
        if (!mounted) return;
        setState(() {
          _transferLabel = total == 1
              ? "Uploading $name..."
              : "Uploading ${done + 1} of $total: $name";
          _transferProgress = total == 1 ? null : done / total;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _transferring = false;
      _transferLabel = null;
    });
    if (count == null) return;
    _setStatus(
      count == 0
          ? "Upload failed. See the log for details."
          : "Uploaded $count file${count == 1 ? '' : 's'} to $_currentPath",
      isError: count == 0,
    );
    await _refresh();
  }

  Future<void> _download(DeviceFileEntry entry) async {
    if (_provider.saveLocation.isEmpty) {
      _setStatus(
        "Choose a save location on the main screen first.",
        isError: true,
      );
      return;
    }
    setState(() {
      _transferring = true;
      _transferLabel = "Downloading ${entry.name}...";
      _transferProgress = null;
      _lastDownloadPath = null;
    });
    final path = await _provider.downloadDeviceEntry(entry);
    if (!mounted) return;
    setState(() {
      _transferring = false;
      _transferLabel = null;
      _lastDownloadPath = path;
    });
    _setStatus(
      path == null ? "Could not download ${entry.name}" : "Saved to $path",
      isError: path == null,
    );
  }

  Future<String?> _promptForName(
    String title,
    String actionLabel, {
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void submit() {
            final value = controller.text.trim();
            if (value.isEmpty || value == '.' || value == '..') {
              setDialogState(() => error = "Enter a name.");
              return;
            }
            if (value.contains('/')) {
              setDialogState(() => error = "Names cannot contain '/'.");
              return;
            }
            Navigator.pop(ctx, value);
          }

          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 360,
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: "Name",
                  isDense: true,
                  errorText: error,
                ),
                onSubmitted: (_) => submit(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              TextButton(onPressed: submit, child: Text(actionLabel)),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _createFolder() async {
    final name = await _promptForName("New Folder", "Create");
    if (name == null || !mounted) return;
    final ok = await _provider.createDeviceFolder(_currentPath, name);
    _setStatus(
      ok ? "Created folder $name" : "Could not create folder $name",
      isError: !ok,
    );
    if (ok) await _refresh();
  }

  Future<void> _rename(DeviceFileEntry entry) async {
    final name = await _promptForName("Rename", "Rename", initial: entry.name);
    if (name == null || name == entry.name || !mounted) return;
    final ok = await _provider.renameDeviceEntry(entry, name);
    _setStatus(
      ok ? "Renamed ${entry.name} to $name" : "Could not rename ${entry.name}",
      isError: !ok,
    );
    if (ok) await _refresh();
  }

  Future<void> _confirmDelete(DeviceFileEntry entry) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(entry.isDirectory ? "Delete Folder" : "Delete File"),
        content: Text(
          entry.isDirectory
              ? "Delete ${entry.name} and everything inside it?\n\n"
                    "This cannot be undone."
              : "Delete ${entry.name}?\n\nThis cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await _provider.deleteDeviceEntry(entry);
    _setStatus(
      ok ? "Deleted ${entry.name}" : "Could not delete ${entry.name}",
      isError: !ok,
    );
    if (ok) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableDialog(
      width: 900,
      height: 680,
      leading: const Icon(Icons.folder_open),
      title: const Text(
        "File Manager",
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      actions: [
        IconButton(
          tooltip: "Upload files here",
          onPressed: _busy ? null : _upload,
          icon: const Icon(Icons.upload_file),
        ),
        IconButton(
          tooltip: "New folder",
          onPressed: _busy ? null : _createFolder,
          icon: const Icon(Icons.create_new_folder_outlined),
        ),
        IconButton(
          tooltip: "Refresh",
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: "Close",
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ],
      footer: _buildStatusBar(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  tooltip: "Up one level",
                  onPressed: _busy || _currentPath == '/' ? null : _goUp,
                  icon: const Icon(Icons.arrow_upward),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.folder),
                      labelText: "Device path",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (value) => _navigateTo(value),
                  ),
                ),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 6,
                  children: _shortcuts.entries
                      .map(
                        (shortcut) => ActionChip(
                          label: Text(shortcut.key),
                          onPressed: _busy
                              ? null
                              : () => _navigateTo(shortcut.value),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          Expanded(child: _buildFileList()),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_entries.isEmpty) {
      return const Center(child: Text("This folder is empty."));
    }

    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return _DeviceFileTile(
          entry: entry,
          enabled: !_busy,
          onOpen: entry.isDirectory || entry.isSymlink
              ? () => _navigateTo(entry.path)
              : null,
          onDownload: () => _download(entry),
          onRename: () => _rename(entry),
          onDelete: () => _confirmDelete(entry),
        );
      },
    );
  }

  Widget _buildStatusBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodySmall;
    final defaultText =
        "${_entries.length} item${_entries.length == 1 ? '' : 's'} in "
        "$_currentPath";

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_transferring)
          LinearProgressIndicator(value: _transferProgress, minHeight: 2),
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _transferLabel ?? _statusMessage ?? defaultText,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle?.copyWith(
                    color: _statusIsError && _transferLabel == null
                        ? colorScheme.error
                        : null,
                    fontWeight: _statusMessage == null && _transferLabel == null
                        ? FontWeight.normal
                        : FontWeight.w600,
                  ),
                ),
              ),
              if (_lastDownloadPath != null && _statusMessage != null)
                IconButton(
                  tooltip: "Open save folder",
                  onPressed: _provider.openSaveLocation,
                  icon: const Icon(Icons.folder, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              if (_statusMessage != null && !_transferring)
                IconButton(
                  tooltip: "Clear status",
                  onPressed: () => setState(() {
                    _statusMessage = null;
                    _lastDownloadPath = null;
                  }),
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeviceFileTile extends StatelessWidget {
  final DeviceFileEntry entry;
  final bool enabled;
  final VoidCallback? onOpen;
  final VoidCallback onDownload;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _DeviceFileTile({
    required this.entry,
    required this.enabled,
    required this.onOpen,
    required this.onDownload,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final details = <String>[
      if (entry.sizeBytes != null) formatFileSize(entry.sizeBytes!),
      if (entry.modified != null) entry.modified!,
    ];

    return ListTile(
      enabled: enabled,
      onTap: enabled ? onOpen : null,
      leading: Icon(
        entry.isDirectory
            ? Icons.folder
            : entry.isSymlink
            ? Icons.link
            : Icons.insert_drive_file_outlined,
        color: entry.isDirectory ? colorScheme.secondary : null,
      ),
      title: Text(entry.name, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty
          ? null
          : Text(
              details.join('  ·  '),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: "Download to save location",
            onPressed: enabled ? onDownload : null,
            icon: const Icon(Icons.download),
          ),
          IconButton(
            tooltip: "Rename",
            onPressed: enabled ? onRename : null,
            icon: const Icon(Icons.drive_file_rename_outline),
          ),
          IconButton(
            tooltip: "Delete",
            onPressed: enabled ? onDelete : null,
            color: AppColors.danger,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
