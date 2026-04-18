import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/nebula_background.dart';
import '../widgets/rainbow_border_container.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..forward();

    Timer(const Duration(milliseconds: 2400), widget.onComplete);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: NebulaBackground(
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: fade,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.88, end: 1).animate(fade),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Rainbow-bordered logo circle
                    RainbowBorderContainer(
                      borderRadius: 60,
                      borderWidth: 2.0,
                      duration: const Duration(seconds: 2),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFFFFFF),
                        ),
                        child: const Icon(
                          Icons.memory_rounded,
                          size: 50,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      'MIRA',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Memory Intelligence & Recall Assistant\nOffline recall. Calm clarity. Zero cloud.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF888888),
                      ),
                    ),
                    const SizedBox(height: 36),
                    const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
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
