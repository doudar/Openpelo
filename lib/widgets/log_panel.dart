import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class LogPanel extends StatefulWidget {
  const LogPanel({super.key});

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          Consumer<AppProvider>(
            builder: (context, provider, child) {
              // Trigger scroll on new logs
              WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
              
              return Scrollbar(
                thumbVisibility: true,
                trackVisibility: true,
                controller: _scrollController,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(top: 8, left: 8, right: 8, bottom: 40), // Space for button
                  itemCount: provider.logs.length,
                  itemBuilder: (context, index) {
                    final entry = provider.logs[index];
                    Color color = Colors.black;
                    if (entry.tag == 'error' || entry.tag == 'stderr') color = Colors.red;
                    if (entry.tag == 'command') color = Colors.blue;
                    if (entry.tag == 'status') color = Colors.teal;
                    
                    return SelectableText.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: "${entry.timestamp} ", style: const TextStyle(color: Colors.grey)),
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
              color: Colors.white.withOpacity(0.7),
              shape: const CircleBorder(),
              child: IconButton(
                icon: Icon(
                  _autoScroll ? Icons.vertical_align_bottom : Icons.pause_circle_outline,
                  color: _autoScroll ? Colors.blue : Colors.grey,
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
