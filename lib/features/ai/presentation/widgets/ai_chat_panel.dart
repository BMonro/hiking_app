import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/validation/form_validators.dart';
import '../../domain/chat_message.dart';
import '../ai_providers.dart';

/// Картка ШІ-чату: повідомлення + поле вводу внизу.
class AiChatPanel extends ConsumerStatefulWidget {
  const AiChatPanel({
    super.key,
    this.scrollController,
    this.onMessagesChanged,
  });

  final ScrollController? scrollController;
  final VoidCallback? onMessagesChanged;

  @override
  ConsumerState<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends ConsumerState<AiChatPanel> {
  ScrollController? _ownedScroll;

  ScrollController get _scroll =>
      widget.scrollController ?? (_ownedScroll ??= ScrollController());

  @override
  void dispose() {
    _ownedScroll?.dispose();
    super.dispose();
  }

  void scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) return;
      _scroll.jumpTo(max);
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(aiChatProvider);
    final sending = ref.watch(aiChatSendingProvider);
    final configuredAsync = ref.watch(aiConfiguredProvider);

    ref.listen(aiChatProvider, (prev, next) {
      if (prev?.length != next.length) {
        scrollToEnd();
        widget.onMessagesChanged?.call();
      }
    });

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
        mainAxisSize: MainAxisSize.min,
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
                      configuredAsync.when(
                        loading: () => Text(
                          'Перевірка підключення…',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        error: (_, __) => Text(
                          'Статус ШІ невідомий',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        data: (ready) => Text(
                          ready
                              ? 'Запитайте пораду — відповідь з сервера'
                              : 'Потрібен OPENAI_API_KEY у Supabase Secrets',
                          style: TextStyle(
                            fontSize: 12,
                            color: ready
                                ? Colors.grey[600]
                                : const Color(0xFFE65100),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Очистити чат',
                  onPressed: () => ref.read(aiChatProvider.notifier).clear(),
                  icon: Icon(Icons.refresh, color: Colors.grey[600], size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 260,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: messages.length + (sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (sending && index == messages.length) {
                  return const _TypingBubble();
                }
                return _ChatBubble(message: messages[index]);
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE0E8E4)),
          _ChatInputBar(scrollController: _scroll),
        ],
      ),
    ),
    );
  }
}

class _ChatInputBar extends ConsumerStatefulWidget {
  const _ChatInputBar({required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<_ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<_ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollChatToEnd() {
    final scroll = widget.scrollController;
    if (!scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      scroll.jumpTo(scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _controller.text;
    final sending = ref.read(aiChatSendingProvider);
    final promptError = FormValidators.aiPrompt(text);
    if (promptError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(promptError)),
        );
      }
      return;
    }
    if (sending) return;
    _controller.clear();
    await ref.read(aiChatProvider.notifier).send(text);
    _scrollChatToEnd();
  }

  @override
  Widget build(BuildContext context) {
    final sending = ref.watch(aiChatSendingProvider);
    final configuredAsync = ref.watch(aiConfiguredProvider);
    final aiReady = configuredAsync.maybeWhen(
      data: (v) => v,
      orElse: () => true,
    );

    return Container(
      color: const Color(0xFFFAFCFA),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 3,
              maxLength: 4000,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                  null,
              textInputAction: TextInputAction.send,
              onSubmitted: (sending || !aiReady) ? null : (_) => _send(),
              decoration: InputDecoration(
                hintText: aiReady
                    ? 'Запитайте про похід…'
                    : 'ШІ не налаштовано на сервері',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Color(0xFFE0E8E4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Color(0xFFE0E8E4)),
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
              onTap: (sending || !aiReady) ? null : _send,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: sending
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
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4F2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Думаю…',
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
            ),
          ],
        ),
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
