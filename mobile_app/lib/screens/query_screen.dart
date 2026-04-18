import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/rainbow_border_container.dart';

class QueryScreen extends StatefulWidget {
  const QueryScreen({super.key});

  @override
  State<QueryScreen> createState() => _QueryScreenState();
}

class _QueryScreenState extends State<QueryScreen> {
  final TextEditingController _questionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;

  final List<String> _quickPrompts = const [
    'next appointment?',
    'medicine plan?',
    'today recap?',
    'what did doctor say?',
  ];

  Future<void> _askQuestion(String text) async {
    final q = text.trim();
    if (q.isEmpty || _isLoading) return;

    setState(() {
      _messages.add({'role': 'user', 'text': q});
      _isLoading = true;
    });
    _questionController.clear();
    _scrollToBottom();

    try {
      final result = await ApiService.chatWithMemory(q);
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'bot',
          'text': (result['answer'] ?? 'No answer found.').toString(),
        });
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'bot',
          'text': 'Network-free brain lag. Try that again in a sec.',
        });
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            onPressed: _messages.isEmpty
                ? null
                : () => setState(() => _messages.clear()),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 4, 14, 100 + bottomInset),
            child: Column(
              children: [
                if (_messages.isEmpty)
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick asks',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _quickPrompts
                              .map(
                                (p) => ActionChip(
                                  label: Text(p),
                                  onPressed: () => _askQuestion(p),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Typing indicator
                      if (_isLoading && index == _messages.length) {
                        return _ChatBubbleAnimated(
                          key: const ValueKey('typing'),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(
                                bottom: 12, right: 52,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF151515),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFF2A2A2A),
                                  width: 0.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF888888),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'thinking...',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      final msg = _messages[index];
                      final isUser = msg['role'] == 'user';
                      return _ChatBubbleAnimated(
                        key: ValueKey('msg_$index'),
                        child: Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: EdgeInsets.only(
                              bottom: 12,
                              left: isUser ? 52 : 0,
                              right: isUser ? 0 : 52,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? const Color(0xFFFFFFFF)
                                  : const Color(0xFF151515),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft: Radius.circular(isUser ? 18 : 6),
                                bottomRight: Radius.circular(isUser ? 6 : 18),
                              ),
                              border: Border.all(
                                color: isUser
                                    ? const Color(0x00000000)
                                    : const Color(0xFF2A2A2A),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              msg['text'] ?? '',
                              style: TextStyle(
                                fontSize: 15.5,
                                height: 1.45,
                                color: isUser
                                    ? const Color(0xFF000000)
                                    : cs.onSurface,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // ── Input area: rainbow-bordered text field + separate send button ──
          Positioned(
            left: 12,
            right: 12,
            bottom: 10 + bottomInset,
            child: SafeArea(
              top: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Rainbow-bordered text field
                  Expanded(
                    child: RainbowBorderContainer(
                      borderRadius: 22,
                      borderWidth: 1.8,
                      duration: const Duration(seconds: 3),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0A0A),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: TextField(
                          controller: _questionController,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _askQuestion,
                          style: const TextStyle(
                            color: Color(0xFFF5F5F5),
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Type your question...',
                            hintStyle: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 15,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            filled: false,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Separate floating send button
                  _SendButton(
                    isLoading: _isLoading,
                    onPressed: () => _askQuestion(_questionController.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

/// Premium floating send button with gradient glow
class _SendButton extends StatefulWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const _SendButton({required this.isLoading, required this.onPressed});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final glowOpacity = 0.25 + (_glowController.value * 0.35);
        return Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFFFFF),
                Color(0xFFCCCCCC),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFFFFF).withValues(alpha: glowOpacity),
                blurRadius: 16,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: widget.isLoading ? null : widget.onPressed,
              child: Center(
                child: widget.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Color(0xFF000000),
                        ),
                      )
                    : const Icon(
                        Icons.arrow_upward_rounded,
                        color: Color(0xFF000000),
                        size: 24,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Animated chat bubble — fade + scale in from bottom
class _ChatBubbleAnimated extends StatefulWidget {
  final Widget child;

  const _ChatBubbleAnimated({super.key, required this.child});

  @override
  State<_ChatBubbleAnimated> createState() => _ChatBubbleAnimatedState();
}

class _ChatBubbleAnimatedState extends State<_ChatBubbleAnimated>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
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
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
