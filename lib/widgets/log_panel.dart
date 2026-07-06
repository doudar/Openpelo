import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import 'recessed_pane.dart';

class LogPanel extends StatefulWidget {
  const LogPanel({super.key});

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;
  int _lastLogCount = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_autoScroll && _scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Color _colorForTag(String tag, ColorScheme colorScheme) {
    switch (tag) {
      case 'error':
      case 'stderr':
        return colorScheme.error;
      case 'command':
        return colorScheme.primary;
      case 'status':
        return colorScheme.secondary;
      default:
        return colorScheme.onSurface;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return RecessedPane(
      child: Stack(
        children: [
          Consumer<AppProvider>(
            builder: (context, provider, child) {
              final logs = provider.logs;
              // Only scroll when new logs are added, not on every rebuild
              if (logs.length != _lastLogCount) {
                _lastLogCount = logs.length;
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
              }

              return Scrollbar(
                thumbVisibility: true,
                trackVisibility: true,
                controller: _scrollController,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(top: 8, left: 8, right: 8, bottom: 40),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final entry = logs[index];
                    final color = _colorForTag(entry.tag, colorScheme);

                    return Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: "${entry.timestamp} ",
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                          TextSpan(text: entry.message, style: TextStyle(color: color)),
                        ],
                      ),
                      style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                    );
                  },
                ),
              );
            },
          ),
          Positioned(
            right: 18,
            bottom: 8,
            child: Material(
              color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.86),
              shape: const CircleBorder(),
              child: IconButton(
                icon: Icon(
                  _autoScroll ? Icons.vertical_align_bottom : Icons.pause_circle_outline,
                  color: _autoScroll ? AppColors.primary : colorScheme.onSurfaceVariant,
                ),
                tooltip: _autoScroll ? "Auto-scroll ON" : "Auto-scroll OFF",
                onPressed: () {
                  setState(() {
                    _autoScroll = !_autoScroll;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
