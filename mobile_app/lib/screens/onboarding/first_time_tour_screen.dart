import 'package:flutter/material.dart';

class FirstTimeTourScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const FirstTimeTourScreen({super.key, required this.onFinished});

  @override
  State<FirstTimeTourScreen> createState() => _FirstTimeTourScreenState();
}

class _FirstTimeTourScreenState extends State<FirstTimeTourScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _pages = [
    (
      icon: Icons.auto_awesome,
      title: 'Your Memory Wingman',
      body:
          'Drop voice or text, and the app turns chat chaos into clean memory cards you can search later.',
      colorA: Color(0xFF06B6D4),
      colorB: Color(0xFF0EA5E9),
    ),
    (
      icon: Icons.hearing,
      title: 'Capture in One Tap',
      body:
          'Hit record, talk naturally, and we handle diarization, summary, events, and reminders in the background.',
      colorA: Color(0xFF22C55E),
      colorB: Color(0xFF14B8A6),
    ),
    (
      icon: Icons.psychology_alt,
      title: 'Ask Like You Text',
      body:
          'Say things like "what did the doctor say" and get instant answers from your private local memory.',
      colorA: Color(0xFFF59E0B),
      colorB: Color(0xFFFB7185),
    ),
  ];

  void _next() {
    if (_index == _pages.length - 1) {
      widget.onFinished();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Column(
            children: [
              Row(
                children: [
                  TextButton(
                    onPressed: widget.onFinished,
                    child: const Text('Skip'),
                  ),
                  const Spacer(),
                  Text(
                    '${_index + 1}/${_pages.length}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  onPageChanged: (v) => setState(() => _index = v),
                  itemCount: _pages.length,
                  itemBuilder: (context, i) {
                    final p = _pages[i];
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxHeight < 620;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.fromLTRB(6, 12, 6, 12),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [p.colorA, p.colorB],
                            ),
                          ),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight - 48,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: compact ? 76 : 92,
                                    height: compact ? 76 : 92,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      p.icon,
                                      size: compact ? 40 : 50,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: compact ? 18 : 30),
                                  Text(
                                    p.title,
                                    style: TextStyle(
                                      fontSize: compact ? 26 : 32,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      height: 1.1,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: compact ? 12 : 18),
                                  Text(
                                    p.body,
                                    style: TextStyle(
                                      fontSize: compact ? 15 : 17,
                                      color: const Color(0xFFEFF9FF),
                                      height: 1.45,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _index == i ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: _index == i ? cs.primary : cs.outline,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _next,
                  icon: Icon(
                    _index == _pages.length - 1
                        ? Icons.rocket_launch
                        : Icons.east,
                  ),
                  label: Text(
                    _index == _pages.length - 1 ? 'Launch App' : 'Next Move',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
