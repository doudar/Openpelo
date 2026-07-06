import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class RecessedPane extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const RecessedPane({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);

    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.recessedPaneBorder,
          borderRadius: radius,
        ),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Material(
            color: AppColors.recessedPane,
            borderRadius: BorderRadius.circular(7),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: padding,
                    child: child,
                  ),
                ),
                _RecessedEdge(
                  alignment: Alignment.topCenter,
                  height: 30,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  opacity: 0.095,
                ),
                _RecessedEdge(
                  alignment: Alignment.bottomCenter,
                  height: 24,
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  opacity: 0.025,
                ),
                _RecessedEdge(
                  alignment: Alignment.centerLeft,
                  width: 30,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  opacity: 0.065,
                ),
                _RecessedEdge(
                  alignment: Alignment.centerRight,
                  width: 22,
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  opacity: 0.018,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(
                          color: AppColors.ink.withValues(alpha: 0.035),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecessedEdge extends StatelessWidget {
  final Alignment alignment;
  final double? width;
  final double? height;
  final Alignment begin;
  final Alignment end;
  final double opacity;

  const _RecessedEdge({
    required this.alignment,
    this.width,
    this.height,
    required this.begin,
    required this.end,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: IgnorePointer(
          child: SizedBox(
            width: width,
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: begin,
                  end: end,
                  colors: [
                    AppColors.ink.withValues(alpha: opacity),
                    AppColors.ink.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
