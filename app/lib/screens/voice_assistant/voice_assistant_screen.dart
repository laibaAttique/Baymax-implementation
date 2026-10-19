import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/app_permissions.dart';
import '../../services/voice/voice_assistant_controller.dart';
import '../../theme/app_theme.dart';

/// S-16: the AI micro-coaching voice assistant (Module 6).
///
/// The screen only renders [VoiceAssistantController]'s state: the waveform
/// moves with the microphone level while listening and while a reply is being
/// spoken, and is flat otherwise.
class VoiceAssistantScreen extends StatefulWidget {
  /// Override in tests. The screen closes whichever controller it uses.
  final VoiceAssistantController? controller;

  /// Start listening as soon as the screen opens (opening it is the user's
  /// request to talk).
  final bool autoListen;

  const VoiceAssistantScreen({super.key, this.controller, this.autoListen = true});

  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> with SingleTickerProviderStateMixin {
  static const _navy = Color(0xFF0F0F1A);

  late final VoiceAssistantController _assistant = widget.controller ?? VoiceAssistantController();
  late final AnimationController _wave;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _assistant.addListener(_onAssistantChanged);
    if (widget.autoListen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _assistant.startListening());
    }
  }

  @override
  void dispose() {
    _assistant.removeListener(_onAssistantChanged);
    _wave.dispose();
    // Releases the microphone and discards any pending command (FR19.4).
    _assistant.dispose();
    super.dispose();
  }

  bool get _animated => _assistant.state == VoiceState.listening || _assistant.state == VoiceState.speaking;

  void _onAssistantChanged() {
    if (!mounted) return;
    if (_animated && !_wave.isAnimating) {
      _wave.repeat();
    } else if (!_animated && _wave.isAnimating) {
      _wave.stop();
    }
    setState(() {});
  }

  String get _stateLabel {
    switch (_assistant.state) {
      case VoiceState.idle:
        return 'Tap the mic to speak';
      case VoiceState.listening:
        return 'Listening...';
      case VoiceState.processing:
        return 'Thinking...';
      case VoiceState.speaking:
        return 'Baymax is speaking';
      case VoiceState.error:
        return 'Something went wrong';
      case VoiceState.unavailable:
        return 'Voice input unavailable';
    }
  }

  Widget _buildWaveform() {
    const offsets = [0.0, 1.0, 2.0, 3.0, 4.0, 3.0, 2.0];
    return SizedBox(
      height: 80,
      child: AnimatedBuilder(
        animation: Listenable.merge([_wave, _assistant.soundLevel]),
        builder: (context, _) {
          // Listening: amplitude follows the microphone. Speaking: steady.
          final double amplitude;
          switch (_assistant.state) {
            case VoiceState.listening:
              amplitude = 0.2 + 0.8 * _assistant.soundLevel.value;
            case VoiceState.speaking:
              amplitude = 0.6;
            default:
              amplitude = 0;
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final offset in offsets)
                Builder(builder: (_) {
                  final swing = (1 + math.sin(_wave.value * 2 * math.pi + offset)) / 2;
                  return Container(
                    width: 6,
                    height: 10 + 60 * amplitude * swing,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: amplitude == 0 ? 0.35 : 0.5 + 0.5 * swing),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMicButton() {
    final state = _assistant.state;
    final listening = state == VoiceState.listening;
    return Semantics(
      button: true,
      label: listening ? 'Stop listening' : 'Start listening',
      child: GestureDetector(
        key: const Key('micButton'),
        onTap: _assistant.toggleMic,
        child: AnimatedBuilder(
          animation: _wave,
          builder: (context, child) {
            final pulse = listening ? (1 + math.sin(_wave.value * 2 * math.pi)) / 2 : 0.0;
            return Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: state == VoiceState.unavailable ? AppTheme.textSecondary : AppTheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  if (listening)
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.4 * (1 - pulse)),
                      spreadRadius: 20 * pulse,
                      blurRadius: 10 * pulse,
                    ),
                ],
              ),
              alignment: Alignment.center,
              child: child,
            );
          },
          child: state == VoiceState.processing
              ? const SizedBox(
                  width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
              : Icon(listening ? Icons.stop : Icons.mic, color: Colors.white, size: 34),
        ),
      ),
    );
  }

  Widget _buildSuggestChip(String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(text, style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w500)),
        backgroundColor: Colors.transparent,
        side: const BorderSide(color: AppTheme.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onPressed: () => _assistant.submitText(text),
      ),
    );
  }

  Widget _buildResponseCard() {
    final response = _assistant.response;
    final speaking = _assistant.state == VoiceState.speaking;
    final failed = _assistant.state == VoiceState.error || _assistant.state == VoiceState.unavailable;
    final chips = response?.chips ?? const ['How many reps?', 'Check my form', "What's my workout today?"];

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: const BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(speaking ? Icons.volume_up : Icons.chat_bubble_outline, color: AppTheme.primary, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(speaking ? 'Baymax is responding' : 'Baymax',
                      style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w500)),
                ),
                if (speaking)
                  IconButton(
                    tooltip: 'Stop speaking',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.stop_circle_outlined, color: AppTheme.primary),
                    onPressed: _assistant.stopSpeaking,
                  )
                else if (response != null && _assistant.state == VoiceState.idle)
                  IconButton(
                    tooltip: 'Replay',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.replay, color: AppTheme.primary),
                    onPressed: _assistant.replay,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (failed) ...[
              Text(_assistant.errorMessage ?? 'Please try again.',
                  style: const TextStyle(color: AppTheme.error, fontSize: 15, height: 1.5)),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_assistant.settingsNeeded)
                    TextButton(
                        onPressed: AppPermissions.instance.openSettings, child: const Text('Open Settings')),
                  TextButton(onPressed: _assistant.startListening, child: const Text('Try again')),
                ],
              ),
            ] else
              Text(
                response?.text ?? 'Ask me about your reps, your form, or how to do an exercise.',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, height: 1.5),
              ),
            if (_assistant.speechOutputFailed)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Voice output is not available on this device, so the reply is shown as text only.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final chip in chips.take(3)) _buildSuggestChip(chip)]),
            ),
            const SizedBox(height: 8),
            Text('Intent engine: ${_assistant.engineName}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listening = _assistant.state == VoiceState.listening;
    final transcript = _assistant.transcript;

    return Scaffold(
      backgroundColor: _navy,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Semantics(
                  button: true,
                  label: 'Close voice assistant',
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_stateLabel,
                          style: const TextStyle(
                              color: AppTheme.primaryLight, fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 1)),
                      const SizedBox(height: 20),
                      _buildWaveform(),
                      const SizedBox(height: 20),
                      _buildMicButton(),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: listening
                            ? TextButton(
                                onPressed: _assistant.cancelListening,
                                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                              )
                            : null,
                      ),
                      if (transcript.isNotEmpty)
                        Text('“$transcript”',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
                    ],
                  ),
                ),
              ),
            ),
            _buildResponseCard(),
          ],
        ),
      ),
    );
  }
}
