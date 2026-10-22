import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/consultation.dart';
import '../../services/api_client.dart';
import '../../services/consultation_chat.dart';
import '../../services/consultation_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';

/// Messages with the specialist of one accepted appointment. Plain text only: links are shown as text, never as buttons.
class ConsultationChatScreen extends StatefulWidget {
  final Appointment appointment;

  /// Replaceable so the screen can be tested without Firebase.
  final Stream<List<ChatMessage>> Function()? messages;
  final Future<void> Function(String text)? onSend;
  final Future<void> Function()? onOpened;
  final DateTime Function()? clock;
  const ConsultationChatScreen({Key? key, required this.appointment, this.messages, this.onSend, this.onOpened, this.clock}) : super(key: key);

  @override
  State<ConsultationChatScreen> createState() => _ConsultationChatScreenState();
}

class _ConsultationChatScreenState extends State<ConsultationChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final Stream<List<ChatMessage>> _stream = (widget.messages ?? () => ConsultationChat.instance.watch(widget.appointment.id))();
  bool _sending = false;
  String? _problem;
  int _shown = 0;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    unawaited((widget.onOpened ?? () => ConsultationChat.instance.markRead(widget.appointment))());
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final problem = ChatRules.problem(_text.text);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    setState(() {
      _sending = true;
      _problem = null;
    });
    try {
      await (widget.onSend ?? (t) => ConsultationChat.instance.send(widget.appointment, t))(_text.text.trim());
      if (mounted) _text.clear();
    } on ApiException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } catch (_) {
      if (mounted) setState(() => _problem = 'Could not send the message. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    });
  }

  Widget _bubble(ChatMessage m) {
    final mine = m.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: mine ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: mine ? AppTheme.primary : AppTheme.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(m.text, style: TextStyle(height: 1.4, color: mine ? Colors.white : AppTheme.textPrimary, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 4),
            Text(ConsultationService.formatDateTime(m.at), style: TextStyle(fontSize: 11, color: mine ? Colors.white : AppTheme.textSecondary)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final closed = ChatRules.closedReason(a, _now);
    return Scaffold(
      appBar: AppBar(title: Text(a.specialistName)),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return const MessageState(message: 'Could not load the messages. Check your internet connection.');
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final list = snap.data!;
                if (list.length != _shown) {
                  _shown = list.length;
                  _scrollToEnd();
                }
                if (list.isEmpty) {
                  return const MessageState(icon: Icons.chat_bubble_outline_rounded, message: 'No messages yet. Say hello, or ask what you want to cover.');
                }
                return ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), children: [for (final m in list) _bubble(m)]);
              },
            ),
          ),
          if (closed != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(closed, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w700, height: 1.4)),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_problem != null)
                  Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(_problem!, style: const TextStyle(color: AppTheme.error, fontWeight: FontWeight.w700, fontSize: 13))),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: ChatRules.maxLength,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'Write a message', counterText: ''),
                      onChanged: (_) {
                        if (_problem != null) setState(() => _problem = null);
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send',
                    onPressed: _sending ? null : _send,
                    icon: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
                    color: AppTheme.primary,
                  ),
                ]),
                const Text('Do not send passwords or payment details. In an emergency contact emergency services.', style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.35)),
              ]),
            ),
        ]),
      ),
    );
  }
}
