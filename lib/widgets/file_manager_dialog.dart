import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device_file_model.dart';
import '../providers/app_provider.dart';
import '../services/device_file_parser.dart';
import '../theme/app_theme.dart';
import 'draggable_dialog.dart';

/// Column geometry shared by the sort header and the rows below it. Both use
/// the same padding and widths, so the labels sit directly over their values.
const EdgeInsets _rowPadding = EdgeInsets.symmetric(horizontal: 16);
const double _leadingColumnWidth = 40; // icon + gap
const double _sizeColumnWidth = 90;
const double _columnGap = 20;
// Fits 'YYYY-MM-DD HH:MM:SS', the longest form the ls parser produces.
const double _modifiedColumnWidth = 150;
const double _actionsColumnWidth = 144; // three IconButtons
const double _arrowSlotWidth = 18;

class FileManagerDialog extends StatefulWidget {
  final String deviceSerial;

  const FileManagerDialog({super.key, required this.deviceSerial});

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
  DeviceFileSort _sort = DeviceFileSort.name;
  bool _ascending = true;
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

  bool get _deviceSessionActive =>
      _provider.selectedDevice?.serial == widget.deviceSerial;

  bool get _busy => _loading || _transferring || !_deviceSessionActive;

  Future<void> _navigateTo(String path, {bool fallbackToRoot = false}) async {
    final target = path.trim().isEmpty ? '/' : joinRemotePath('/', path.trim());
    setState(() => _loading = true);
    try {
      final entries = await _provider.listDeviceFiles(
        widget.deviceSerial,
        target,
      );
      if (!mounted) return;
      sortDeviceFiles(entries, sort: _sort, ascending: _ascending);
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

  /// Re-orders the loaded entries locally; tapping the active column flips the
  /// direction instead of changing it.
  void _applySort(DeviceFileSort sort) {
    setState(() {
      if (_sort == sort) {
        _ascending = !_ascending;
      } else {
        _sort = sort;
        _ascending = true;
      }
      sortDeviceFiles(_entries, sort: _sort, ascending: _ascending);
    });
  }

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
      widget.deviceSerial,
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
    final path = await _provider.downloadDeviceEntry(
      widget.deviceSerial,
      entry,
    );
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
    final ok = await _provider.createDeviceFolder(
      widget.deviceSerial,
      _currentPath,
      name,
    );
    _setStatus(
      ok ? "Created folder $name" : "Could not create folder $name",
      isError: !ok,
    );
    if (ok) await _refresh();
  }

  Future<void> _rename(DeviceFileEntry entry) async {
    final name = await _promptForName("Rename", "Rename", initial: entry.name);
    if (name == null || name == entry.name || !mounted) return;
    final ok = await _provider.renameDeviceEntry(
      widget.deviceSerial,
      entry,
      name,
    );
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

    final ok = await _provider.deleteDeviceEntry(widget.deviceSerial, entry);
    _setStatus(
      ok ? "Deleted ${entry.name}" : "Could not delete ${entry.name}",
      isError: !ok,
    );
    if (ok) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    context.select<AppProvider, String?>(
      (provider) => provider.selectedDevice?.serial,
    );
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
          _buildSortHeader(),
          Expanded(child: _buildFileList()),
        ],
      ),
    );
  }

  Widget _buildSortHeader() {
    final colorScheme = Theme.of(context).colorScheme;

    Widget cell(String label, DeviceFileSort sort, {bool alignEnd = false}) {
      final active = _sort == sort;
      final text = Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: active
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
          ),
        ),
      );
      final arrow = SizedBox(
        width: _arrowSlotWidth,
        child: active
            ? Icon(
                _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: colorScheme.onSurface,
              )
            : null,
      );

      return InkWell(
        onTap: _busy ? null : () => _applySort(sort),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: alignEnd
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            // The arrow sits on the outside of the column so the label stays
            // flush with the values it labels.
            children: alignEnd ? [arrow, text] : [text, arrow],
          ),
        ),
      );
    }

    return Container(
      color: colorScheme.surfaceContainerHighest,
      padding: _rowPadding,
      child: Row(
        children: [
          const SizedBox(width: _leadingColumnWidth),
          Expanded(child: cell("Name", DeviceFileSort.name)),
          SizedBox(
            width: _sizeColumnWidth,
            child: cell("Size", DeviceFileSort.size, alignEnd: true),
          ),
          const SizedBox(width: _columnGap),
          SizedBox(
            width: _modifiedColumnWidth,
            child: cell("Modified", DeviceFileSort.modified),
          ),
          const SizedBox(width: _actionsColumnWidth),
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
    final defaultText = !_deviceSessionActive
        ? "The selected device changed. Close and reopen File Manager."
        : "${_entries.length} item${_entries.length == 1 ? '' : 's'} in "
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
    final detailStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant);

    final disabledColor = colorScheme.onSurface.withValues(alpha: 0.38);

    // Laid out as an explicit Row rather than a ListTile so the columns line
    // up with _buildSortHeader by construction instead of depending on
    // ListTile's internal leading/gap geometry.
    return InkWell(
      onTap: enabled ? onOpen : null,
      child: Padding(
        padding: _rowPadding,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              SizedBox(
                width: _leadingColumnWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    entry.isDirectory
                        ? Icons.folder
                        : entry.isSymlink
                        ? Icons.link
                        : Icons.insert_drive_file_outlined,
                    color: !enabled
                        ? disabledColor
                        : entry.isDirectory
                        ? colorScheme.secondary
                        : null,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  entry.name,
                  overflow: TextOverflow.ellipsis,
                  style: enabled ? null : TextStyle(color: disabledColor),
                ),
              ),
              SizedBox(
                width: _sizeColumnWidth,
                child: Text(
                  entry.sizeBytes == null
                      ? ''
                      : formatFileSize(entry.sizeBytes!),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: detailStyle,
                ),
              ),
              const SizedBox(width: _columnGap),
              SizedBox(
                width: _modifiedColumnWidth,
                child: Text(
                  entry.modified ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: detailStyle,
                ),
              ),
              SizedBox(
                width: _actionsColumnWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
