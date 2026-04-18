import 'package:flutter/material.dart';

/// Clean black background with subtle ambient glow — dialed.gg inspired.
class NebulaBackground extends StatelessWidget {
  final Widget child;

  const NebulaBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // True black base
        const Positioned.fill(
          child: ColoredBox(color: Color(0xFF000000)),
        ),
        // Very subtle top-right warm glow
        Positioned(
          top: -120,
          right: -80,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0x0CFFFFFF),
                  const Color(0x00000000),
                ],
              ),
            ),
          ),
        ),
        // Very subtle bottom-left cool glow
        Positioned(
          bottom: -100,
          left: -90,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0x08FFFFFF),
                  const Color(0x00000000),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}
