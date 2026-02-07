import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class ScreenMirrorDialog extends StatefulWidget {
  const ScreenMirrorDialog({super.key});

  @override
  State<ScreenMirrorDialog> createState() => _ScreenMirrorDialogState();
}

class _ScreenMirrorDialogState extends State<ScreenMirrorDialog> {
  Uint8List? _currentImage;
  bool _isLoading = true;
  Timer? _timer;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _startLoop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startLoop() {
    // Poll every 500ms on desktop, maybe 2s on mobile?
    // Let's just loop immediately after previous finishes with a small delay
    _fetchFrame();
  }

  Future<void> _fetchFrame() async {
    if (!mounted) return;
    if (_isProcessing) return; // Prevent overlapping

    setState(() {
       _isProcessing = true;
    });

    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      if (provider.selectedDevice == null) {
         if (mounted) Navigator.pop(context);
         return;
      }
      
      final bytes = await provider.getScreenShotBytes();
      
      if (mounted) {
         setState(() {
            if (bytes != null && bytes.isNotEmpty) {
               _currentImage = bytes;
            }
            _isLoading = false;
         });
      }
    } catch (e) {
       // ignore
    } finally {
      if (mounted) {
         setState(() {
            _isProcessing = false;
         });
         // Schedule next frame
         // Adaptive delay? 
         // If it took 100ms, wait 100ms.
         // If it took 2s (mobile), wait 500ms.
         _timer = Timer(const Duration(milliseconds: 100), _fetchFrame);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 800, // Large dialg
        height: 600,
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Remote Screen View", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))
              ],
            ),
            const Divider(),
            Expanded(
              child: Center(
                child: _currentImage != null 
                   ? Image.memory(
                       _currentImage!,
                       gaplessPlayback: true,
                       fit: BoxFit.contain,
                     )
                   : (_isLoading ? const CircularProgressIndicator() : const Text("No Signal")),
              ),
            ),
            const SizedBox(height: 5),
            const Text("This is a low-framerate preview.", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
