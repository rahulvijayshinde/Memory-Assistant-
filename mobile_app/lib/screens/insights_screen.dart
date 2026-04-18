import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  Map<String, dynamic>? _brief;
  List<dynamic> _urgent = [];
  List<dynamic> _patterns = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.generateDailyBrief(),
        ApiService.getUrgentItems(hours: 24),
        ApiService.getMemoryPatterns(minFrequency: 2),
      ]);
      if (!mounted) return;
      setState(() {
        _brief = results[0] as Map<String, dynamic>;
        _urgent = results[1] as List<dynamic>;
        _patterns = results[2] as List<dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Vibe'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Color(0xFF888888),
                ),
              ),
            )
          : _error != null
          ? Center(
              child: Text(
                'Could not load insights: $_error',
                style: const TextStyle(color: Color(0xFF999999)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                // Staggered card 1 — Daily Brief
                _StaggeredCard(
                  delay: 0,
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.today,
                                color: Color(0xFFCCCCCC)),
                            const SizedBox(width: 8),
                            Text(
                              'Daily Brief',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          (_brief?['summary'] ??
                                  _brief?['brief'] ??
                                  'No brief generated yet.')
                              .toString(),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Staggered card 2 — Urgent
                _StaggeredCard(
                  delay: 1,
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.priority_high,
                                color: Color(0xFFFF6B6B)),
                            const SizedBox(width: 8),
                            Text(
                              'Urgent in 24h',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_urgent.isEmpty)
                          const Text('No urgent events. You are clear.',
                              style: TextStyle(color: Color(0xFF888888))),
                        ..._urgent.take(4).map((e) {
                          final map = e is Map ? e : {};
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              '- ${(map['description'] ?? 'Event').toString()}',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Staggered card 3 — Patterns
                _StaggeredCard(
                  delay: 2,
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.stacked_line_chart,
                                color: Color(0xFFFFFFFF)),
                            const SizedBox(width: 8),
                            Text(
                              'Patterns',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_patterns.isEmpty)
                          const Text('No recurring patterns yet.',
                              style: TextStyle(color: Color(0xFF888888))),
                        ..._patterns.take(5).map((p) {
                          final map = p is Map ? p : {};
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '- ${(map['description'] ?? map['pattern'] ?? 'Pattern').toString()}',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Staggered fade-in + slide-up animation for cards
class _StaggeredCard extends StatefulWidget {
  final int delay; // 0, 1, 2, ...
  final Widget child;

  const _StaggeredCard({required this.delay, required this.child});

  @override
  State<_StaggeredCard> createState() => _StaggeredCardState();
}

class _StaggeredCardState extends State<_StaggeredCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: 120 * widget.delay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: widget.child,
      ),
    );
  }
}
