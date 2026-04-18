import 'dart:math';
import 'package:flutter/material.dart';

/// A container that wraps its child with a thin, continuously rotating
/// rainbow (sweep gradient) border — inspired by dialed.gg.
class RainbowBorderContainer extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final double borderWidth;
  final Duration duration;

  const RainbowBorderContainer({
    super.key,
    required this.child,
    this.borderRadius = 18,
    this.borderWidth = 2.0,
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<RainbowBorderContainer> createState() =>
      _RainbowBorderContainerState();
}

class _RainbowBorderContainerState extends State<RainbowBorderContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _RainbowBorderPainter(
            progress: _controller.value,
            borderRadius: widget.borderRadius,
            strokeWidth: widget.borderWidth,
          ),
          child: child,
        );
      },
      child: Padding(
        padding: EdgeInsets.all(widget.borderWidth),
        child: widget.child,
      ),
    );
  }
}

class _RainbowBorderPainter extends CustomPainter {
  final double progress;
  final double borderRadius;
  final double strokeWidth;

  _RainbowBorderPainter({
    required this.progress,
    required this.borderRadius,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(borderRadius),
    );

    // Sweep gradient rotates based on animation progress
    final sweepGradient = SweepGradient(
      startAngle: 0,
      endAngle: 2 * pi,
      transform: GradientRotation(2 * pi * progress),
      colors: const [
        Color(0xFFFF6B6B), // red
        Color(0xFFFFE66D), // yellow
        Color(0xFF4ECDC4), // teal
        Color(0xFF45B7D1), // sky
        Color(0xFF96E6FF), // light blue
        Color(0xFFC084FC), // purple
        Color(0xFFFB7185), // pink
        Color(0xFFFF6B6B), // back to red (seamless)
      ],
      stops: const [0.0, 0.14, 0.28, 0.42, 0.57, 0.71, 0.85, 1.0],
    );

    final paint = Paint()
      ..shader = sweepGradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_RainbowBorderPainter old) => old.progress != progress;
}
