import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/chat_message.dart';
import '../ai_providers.dart';

class AiChatPanel extends ConsumerStatefulWidget {
  const AiChatPanel({super.key});

  @override
  ConsumerState<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends ConsumerState<AiChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty || _sending) return;
    _controller.clear();
    setState(() => _sending = true);
    try {
      await ref.read(aiChatProvider.notifier).send(text);
      _scrollToEnd();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(aiChatProvider);
    final notifier = ref.read(aiChatProvider.notifier);
    final aiOn = ref.watch(aiConfiguredProvider);

    ref.listen(aiChatProvider, (_, __) => _scrollToEnd());

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E8E4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Color(0xFF2E7D32),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Порадник з походів',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        aiOn ? 'ШІ-чат увімкнено' : 'Локальні поради + підбір маршрутів',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Очистити чат',
                  onPressed: () => notifier.clear(),
                  icon: Icon(Icons.refresh, color: Colors.grey[600], size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 260,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                return _ChatBubble(message: messages[index]);
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _sending ? null : (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Запитайте про похід…',
                      filled: true,
                      fillColor: const Color(0xFFF5F7F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: const Color(0xFF2E7D32),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _sending ? null : _send,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF2E7D32) : const Color(0xFFF0F4F2),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: isUser ? Colors.white : Colors.black87,
            fontSize: 14,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
