import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'voice_enrollment_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic> _stats = {};
  Map<String, dynamic> _resourceStats = {};
  List<dynamic> _speakers = [];
  Map<String, dynamic> _sherpaStatus = {};
  Map<String, dynamic> _llmStatus = {};
  Timer? _sherpaTimer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _startStatusTimer();
  }

  @override
  void dispose() {
    _sherpaTimer?.cancel();
    super.dispose();
  }

  void _startStatusTimer() {
    _sherpaTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final status = await ApiService.getSherpaStatus();
        final llm = await ApiService.checkLlmStatus();
        if (!mounted) return;
        setState(() {
          _sherpaStatus = status;
          _llmStatus = llm;
        });

        if (status['ready'] == true) {
          timer.cancel();
          _startSlowTimer();
        }
      } catch (_) {}
    });
  }

  void _startSlowTimer() {
    _sherpaTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        final status = await ApiService.getSherpaStatus();
        final llm = await ApiService.checkLlmStatus();
        if (!mounted) return;
        setState(() {
          _sherpaStatus = status;
          _llmStatus = llm;
        });
      } catch (_) {}
    });
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    try {
      final results = await Future.wait([
        ApiService.getStats(),
        ApiService.getResourceStats(),
        ApiService.getSpeakers(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0];
        _resourceStats = results[1];
        final speakersResult = results[2];
        _speakers = (speakersResult['speakers'] as List<dynamic>?) ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }

    try {
      final sherpa = await ApiService.getSherpaStatus();
      final llm = await ApiService.checkLlmStatus();
      if (!mounted) return;
      setState(() {
        _sherpaStatus = sherpa;
        _llmStatus = llm;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Me',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
              children: [
                _buildSectionHeader('Intelligence Engines', 0),
                _AnimatedCell(
                  delayIndex: 1,
                  child: _buildEngineCell(
                    title: 'Transcription Engine',
                    icon: Icons.graphic_eq_rounded,
                    status: _sherpaStatus['asr'] ?? {},
                    defaultSize: 130,
                    onStart: ApiService.startAsrDownload,
                    onPause: ApiService.pauseAsrDownload,
                    onResume: ApiService.resumeAsrDownload,
                    onRetry: ApiService.retryAsrDownload,
                  ),
                ),
                _AnimatedCell(
                  delayIndex: 2,
                  child: _buildEngineCell(
                    title: 'Speaker Identity',
                    icon: Icons.fingerprint_rounded,
                    status: _sherpaStatus['spk'] ?? {},
                    defaultSize: 12,
                    onStart: ApiService.startSpkDownload,
                    onPause: ApiService.pauseSpkDownload,
                    onResume: ApiService.resumeSpkDownload,
                    onRetry: ApiService.retrySpkDownload,
                  ),
                ),
                _AnimatedCell(
                  delayIndex: 3,
                  child: _buildEngineCell(
                    title: 'Answer Brain',
                    icon: Icons.auto_awesome_rounded,
                    status: _llmStatus,
                    defaultSize: 1900,
                    onStart: ApiService.startLlmDownload,
                    onPause: ApiService.pauseLlmDownload,
                    onResume: ApiService.resumeLlmDownload,
                    onRetry: ApiService.retryLlmDownload,
                  ),
                ),

                const SizedBox(height: 30),
                _buildSectionHeader('Voice Profiles', 4),
                _AnimatedCell(
                  delayIndex: 5,
                  child: GestureDetector(
                    onTap: () async {
                      final enrolled = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VoiceEnrollmentScreen(),
                        ),
                      );
                      if (enrolled == true) _loadAll();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161616),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF333333),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.black,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Text(
                              'Enroll New Voice',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF666666),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (_speakers.isEmpty)
                  _AnimatedCell(
                    delayIndex: 6,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'No voices enrolled yet.',
                          style: TextStyle(
                            color: Color(0xFF666666),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),

                ..._speakers.asMap().entries.map((entry) {
                  final i = entry.key;
                  final s = entry.value;
                  final sp = s is Map ? s : {};
                  final name =
                      sp['name']?.toString() ??
                      sp['display_name']?.toString() ??
                      'Unknown';
                  final samples = sp['sample_count'] ?? 1;
                  final id = sp['id']?.toString() ?? '';

                  return _AnimatedCell(
                    delayIndex: 6 + i,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0A0A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF222222),
                          width: 0.5,
                        ),
                      ),
                      child: Dismissible(
                        key: Key(id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A0000),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFFF4444),
                          ),
                        ),
                        onDismissed: (_) {
                          ApiService.deleteSpeakerProfile(id);
                          setState(() => _speakers.remove(s));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1E1E1E),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  name.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$samples sample${samples > 1 ? 's' : ''}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF888888),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 30),
                _buildSectionHeader('Diagnostics', 10),
                _AnimatedCell(
                  delayIndex: 11,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF080808),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF1A1A1A),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildStatRow(
                          'Events Stored',
                          '${_stats['total_events'] ?? 0}',
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(color: Color(0xFF1A1A1A), height: 1),
                        ),
                        _buildStatRow(
                          'Conversations',
                          '${_stats['total_conversations'] ?? 0}',
                        ),
                        if (_resourceStats.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(color: Color(0xFF1A1A1A), height: 1),
                          ),
                          _buildStatRow(
                            'Est. Memory',
                            '${_resourceStats['memory_mb'] ?? _resourceStats['estimated_memory_mb'] ?? '?'} MB',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title, int delayIndex) {
    return _AnimatedCell(
      delayIndex: delayIndex,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF888888),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildEngineCell({
    required String title,
    required IconData icon,
    required Map status,
    required int defaultSize,
    required VoidCallback onStart,
    required VoidCallback onPause,
    required VoidCallback onResume,
    required VoidCallback onRetry,
  }) {
    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    final isReady = status['ready'] == true;
    final isInit = status['initializing'] == true;
    final isPaused = status['paused'] == true;
    final stage = (status['stage'] ?? '').toString().trim().toLowerCase();
    final error = (status['error'] ?? '').toString();
    final downloaded = toInt(status['downloaded_mb']);
    final progress = toInt(status['progress']);
    final isExtractingStage = stage == 'extracting';
    final isLoadingStage = stage == 'loading';

    String statusText = 'Not Downloaded';
    Color statusColor = const Color(0xFF666666);
    Widget actionWidget;

    if (isReady) {
      statusText = 'Active & Ready';
      statusColor = const Color(0xFF22C55E); // Green
      actionWidget = Icon(
        Icons.check_circle_rounded,
        color: statusColor,
        size: 20,
      );
    } else if (error.isNotEmpty) {
      statusText = 'Failed';
      statusColor = const Color(0xFFFF4444); // Red
      actionWidget = _buildMiniButton('Retry', onRetry, color: statusColor);
    } else if (isPaused) {
      statusText = 'Paused ($downloaded MB)';
      statusColor = const Color(0xFFEAB308); // Yellow
      actionWidget = _buildMiniButton('Resume', onResume);
    } else if (isExtractingStage || isLoadingStage) {
      statusText = 'Setting up...';
      statusColor = const Color(0xFF3B82F6); // Blue
      actionWidget = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          color: Color(0xFF3B82F6),
          strokeWidth: 2,
        ),
      );
    } else if (isInit) {
      statusText = 'Downloading... $progress%';
      statusColor = const Color(0xFF3B82F6);
      actionWidget = _buildMiniButton('Pause', onPause);
    } else {
      statusText = '~${defaultSize}MB';
      actionWidget = _buildMiniButton(
        'Download',
        onStart,
        color: Colors.white,
        textColor: Colors.black,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 13,
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          actionWidget,
        ],
      ),
    );
  }

  Widget _buildMiniButton(
    String text,
    VoidCallback onTap, {
    Color color = const Color(0xFF222222),
    Color textColor = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 15, color: Color(0xFF888888)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

/// Staggered animated cell that slides up and fades in
class _AnimatedCell extends StatefulWidget {
  final int delayIndex;
  final Widget child;

  const _AnimatedCell({required this.delayIndex, required this.child});

  @override
  State<_AnimatedCell> createState() => _AnimatedCellState();
}

class _AnimatedCellState extends State<_AnimatedCell>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: 50 * widget.delayIndex), () {
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
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
