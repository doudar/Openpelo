import 'dart:math' as math;
import 'package:flutter/material.dart';

class DraggableDialog extends StatefulWidget {
  final double width;
  final double height;
  final Widget title;
  final Widget? leading;
  final List<Widget> actions;
  final Widget child;
  final Widget? footer;

  const DraggableDialog({
    super.key,
    required this.width,
    required this.height,
    required this.title,
    required this.child,
    this.leading,
    this.actions = const [],
    this.footer,
  });

  @override
  State<DraggableDialog> createState() => _DraggableDialogState();
}

class _DraggableDialogState extends State<DraggableDialog> {
  static const double _edgePadding = 16;
  Offset _offset = Offset.zero;

  Offset _clampOffset(Offset offset, Size viewportSize, Size dialogSize) {
    final maxDx = math.max(0.0, (viewportSize.width - dialogSize.width) / 2);
    final maxDy = math.max(0.0, (viewportSize.height - dialogSize.height) / 2);

    return Offset(
      offset.dx.clamp(-maxDx, maxDx).toDouble(),
      offset.dy.clamp(-maxDy, maxDy).toDouble(),
    );
  }

  void _dragBy(DragUpdateDetails details, Size viewportSize, Size dialogSize) {
    setState(() {
      _offset = _clampOffset(_offset + details.delta, viewportSize, dialogSize);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final maxWidth = math.max(0.0, constraints.maxWidth - (_edgePadding * 2));
        final maxHeight =
            math.max(0.0, constraints.maxHeight - (_edgePadding * 2));
        final dialogSize = Size(
          math.min(widget.width, maxWidth),
          math.min(widget.height, maxHeight),
        );
        _offset = _clampOffset(_offset, viewportSize, dialogSize);

        return Transform.translate(
          offset: _offset,
          child: Dialog(
            insetPadding: const EdgeInsets.all(_edgePadding),
            child: SizedBox(
              width: dialogSize.width,
              height: dialogSize.height,
              child: Column(
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) =>
                          _dragBy(details, viewportSize, dialogSize),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                        child: Row(
                          children: [
                            if (widget.leading != null) ...[
                              widget.leading!,
                              const SizedBox(width: 10),
                            ],
                            Expanded(child: widget.title),
                            ...widget.actions,
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: widget.child),
                  if (widget.footer != null) widget.footer!,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
