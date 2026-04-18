import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/reminder_notification_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/rainbow_border_container.dart';

/// App states for the record screen
enum AppState { idle, listening, processing, ready }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  AppState _state = AppState.idle;
  String _statusMessage = 'Ready when you are';
  Map<String, dynamic>? _lastResult;
  final TextEditingController _textController = TextEditingController();
  bool _showTextMode = false;
  String _currentSource = 'microphone';
  bool _sourceChanging = false;
  bool _sourcePickerExpanded = false;

  // Shake animation for Bluetooth button
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  void _dismissResult() {
    setState(() {
      _state = AppState.idle;
      _statusMessage = 'Ready when you are';
      _lastResult = null;
    });
  }

  // Pulse animation for listening state
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('audio_source') ?? 'microphone';
      final info = await ApiService.getAudioSourceInfo();
      final resolved = (info['type'] ?? saved).toString();
      if (!mounted) return;
      setState(() {
        _currentSource = resolved;
      });
      // Ensure engine uses the same source as the app preference.
      await ApiService.setAudioSource(resolved);
    } catch (_) {}
  }

  Future<void> _setAudioSource(String source) async {
    if (_sourceChanging || source == _currentSource) return;

    setState(() => _sourceChanging = true);
    try {
      final result = await ApiService.setAudioSource(source);
      final prefs = await SharedPreferences.getInstance();
      final status = (result['status'] ?? '').toString();
      final actualType = (result['type'] ?? source).toString();

      if (!mounted) return;

      if (status == 'fallback') {
        await prefs.setString('audio_source', 'microphone');
        if (!mounted) return;
        setState(() {
          _currentSource = 'microphone';
          _sourceChanging = false;
        });
        _shakeBluetoothButton();
        return;
      }

      await prefs.setString('audio_source', actualType);
      if (!mounted) return;
      setState(() {
        _currentSource = actualType;
        _sourcePickerExpanded = false;
        _sourceChanging = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Input switched to ${_sourceTitle(actualType)}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sourceChanging = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not switch source: $e')));
    }
  }

  Future<void> _startListening() async {
    setState(() {
      _state = AppState.listening;
      _statusMessage = 'Listening...';
      _lastResult = null;
    });
    _pulseController.repeat(reverse: true);

    try {
      await ApiService.startBackgroundListening();
    } catch (e) {
      // Fallback to session recording if background listening unavailable
      try {
        await ApiService.startRecording();
      } catch (_) {}
    }
  }

  Future<void> _stopListening() async {
    _pulseController.stop();
    _pulseController.reset();

    setState(() {
      _state = AppState.processing;
      _statusMessage = 'Processing your conversation...';
    });

    try {
      // Stop and auto-process
      final result = await ApiService.stopRecording();
      if (!mounted) return;
      setState(() {
        _state = AppState.ready;
        _lastResult = result;
        _statusMessage = 'Done! Memory saved.';
      });
      await ReminderNotificationService.instance.markInteraction(
        reason: 'recording_saved',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = AppState.idle;
        _statusMessage = 'Could not process. Try again.';
      });
    }
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _state = AppState.processing;
      _statusMessage = 'Understanding your words...';
    });

    try {
      final result = await ApiService.processText(text);
      if (!mounted) return;
      _textController.clear();
      setState(() {
        _state = AppState.ready;
        _lastResult = result;
        _statusMessage = 'Got it! Memory saved.';
      });
      await ReminderNotificationService.instance.markInteraction(
        reason: 'text_saved',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = AppState.idle;
        _statusMessage = 'Could not understand. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isListening = _state == AppState.listening;
    final isProcessing = _state == AppState.processing;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: _showTextMode ? 'Switch to voice' : 'Switch to text',
            onPressed: isProcessing
                ? null
                : () => setState(() => _showTextMode = !_showTextMode),
            icon: Icon(
              _showTextMode ? Icons.mic_rounded : Icons.keyboard_rounded,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
          children: [
            Text(
              'Drop it fast. Find it later.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Rec is your command center for instant capture.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 18),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _statusMessage,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _state == AppState.ready
                          ? cs.primary
                          : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildInputMethodExpander(cs),
                  const SizedBox(height: 12),
                  _buildRecordArea(cs, isListening, isProcessing),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_showTextMode)
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick text capture',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _textController,
                      enabled: !isProcessing,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText:
                            'Type conversation snippets, notes, or reminders...',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: isProcessing ? null : _sendText,
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('Analyze and Save'),
                      ),
                    ),
                  ],
                ),
              ),
            if (_lastResult != null && _state == AppState.ready) ...[
              const SizedBox(height: 14),
              _buildResultPreview(cs),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecordArea(ColorScheme cs, bool isListening, bool isProcessing) {
    final inner = AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      width: double.infinity,
      padding: isProcessing ? const EdgeInsets.all(16) : EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF111111),
        border: isProcessing
            ? Border.all(color: const Color(0xFF2A2A2A))
            : null,
      ),
      child: isProcessing
          ? Row(
              children: [
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Processing audio, extracting events, and updating memory.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isListening ? _stopListening : _startListening,
                    icon: ScaleTransition(
                      scale: isListening
                          ? _pulseAnimation
                          : const AlwaysStoppedAnimation(1),
                      child: Icon(
                        isListening
                            ? Icons.stop_circle_outlined
                            : Icons.graphic_eq,
                      ),
                    ),
                    label: Text(
                      isListening ? 'Stop and Process' : 'Tap to Record',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: isListening
                          ? const Color(0xFF1A1A1A)
                          : cs.primary,
                      foregroundColor: isListening
                          ? Colors.white
                          : Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );

    // Show rainbow border when idle or listening
    if (!isProcessing) {
      return RainbowBorderContainer(
        borderRadius: 18,
        borderWidth: 2.0,
        duration: const Duration(seconds: 3),
        child: inner,
      );
    }

    return inner;
  }

  Widget _buildInputMethodExpander(ColorScheme cs) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF111111),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () =>
                setState(() => _sourcePickerExpanded = !_sourcePickerExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                children: [
                  Icon(
                    _currentSource == 'bluetooth'
                        ? Icons.bluetooth_audio_rounded
                        : Icons.mic_rounded,
                    size: 20,
                    color: cs.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentSource == 'bluetooth'
                          ? 'Input Method: Bluetooth (tap to change)'
                          : 'Input Method: Microphone (tap to change)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _sourcePickerExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(Icons.expand_more_rounded, color: cs.onSurface),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
            child: _sourcePickerExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _buildSourcePicker(cs),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildSourcePicker(ColorScheme cs) {
    final options = [
      (value: 'microphone', title: 'Microphone', icon: Icons.mic_rounded),
      (
        value: 'bluetooth',
        title: 'Bluetooth',
        icon: Icons.bluetooth_audio_rounded,
      ),
    ];

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: _sourceChanging ? 0.72 : 1,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: options.asMap().entries.map((entry) {
          final idx = entry.key;
          final option = entry.value;
          final selected = _currentSource == option.value;
          final isBluetooth = option.value == 'bluetooth';

          Widget chip = TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 260 + (idx * 90)),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) {
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 10),
                  child: child,
                ),
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: selected
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFF1A1A1A),
                border: Border.all(
                  color: selected
                      ? const Color(0x00000000)
                      : const Color(0xFF333333),
                  width: 0.5,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _sourceChanging
                    ? null
                    : () => _setAudioSource(option.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        option.icon,
                        size: 18,
                        color: selected ? Colors.black : cs.onSurface,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        option.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.black : cs.onSurface,
                        ),
                      ),
                      if (_sourceChanging && selected) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: selected ? Colors.black : cs.onSurface,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );

          // Wrap the Bluetooth chip with shake animation
          if (isBluetooth) {
            chip = AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                final dx =
                    _shakeAnimation.value *
                    8 *
                    _sineShake(_shakeController.value);
                return Transform.translate(offset: Offset(dx, 0), child: child);
              },
              child: chip,
            );
          }

          return chip;
        }).toList(),
      ),
    );
  }

  Widget _buildResultPreview(ColorScheme cs) {
    final summary = _lastResult?['summary'] ?? '';
    final eventCount = (_lastResult?['events_saved'] ?? 0);
    final diarizedText = _lastResult?['diarized_text'] ?? '';
    final fullTranscript = _lastResult?['full_transcript'] ?? '';

    if (summary.toString().isEmpty) return const SizedBox.shrink();

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: cs.primary, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Memory Updated',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
                const Spacer(),
                if (eventCount > 0)
                  Text(
                    '$eventCount event${eventCount > 1 ? 's' : ''} detected',
                    style: TextStyle(fontSize: 14, color: cs.outline),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  child: diarizedText.toString().isNotEmpty
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ..._buildDiarizedLines(diarizedText.toString(), cs),
                            if (fullTranscript.toString().trim().isNotEmpty &&
                                fullTranscript.toString().trim().length >
                                    diarizedText.toString().trim().length +
                                        20) ...[
                              const SizedBox(height: 6),
                              Text(
                                fullTranscript.toString(),
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: cs.onSurface.withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ],
                        )
                      : Text(
                          summary.toString(),
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            color: cs.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _dismissResult,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Clear'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Parse diarized text lines ("Speaker 1: text\nSpeaker 2: text")
  /// and render with color-coded speaker badges.
  List<Widget> _buildDiarizedLines(String diarizedText, ColorScheme cs) {
    final lines = diarizedText
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final speakerColors = [
      Colors.blue,
      Colors.deepOrange,
      Colors.teal,
      Colors.purple,
      Colors.brown,
    ];
    final Map<String, int> speakerColorMap = {};
    int nextColor = 0;

    return lines.map((line) {
      final colonIdx = line.indexOf(':');
      if (colonIdx > 0 && colonIdx < 30) {
        final speaker = line.substring(0, colonIdx).trim();
        final text = line.substring(colonIdx + 1).trim();

        // Assign consistent color per speaker
        if (!speakerColorMap.containsKey(speaker)) {
          speakerColorMap[speaker] = nextColor++;
        }
        final color =
            speakerColors[speakerColorMap[speaker]! % speakerColors.length];

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  speaker,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: cs.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            line,
            style: TextStyle(
              fontSize: 15,
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
        );
      }
    }).toList();
  }

  String _sourceTitle(String source) {
    if (source == 'bluetooth') return 'Bluetooth';
    return 'Microphone';
  }

  /// Returns a sine-based oscillation value for the shake effect.
  /// Produces ~3 rapid left-right shakes.
  double _sineShake(double t) => sin(t * 3 * pi);

  void _shakeBluetoothButton() {
    _shakeController.forward(from: 0).then((_) {
      if (mounted) _shakeController.reset();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shakeController.dispose();
    _textController.dispose();
    super.dispose();
  }
}
