import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Big mic that listens once (Indian English) and hands back what was said.
/// Shows the words live while speaking, and a clear message if the mic is
/// not allowed or nothing was heard.
class VoiceMic extends StatefulWidget {
  final ValueChanged<String> onResult;
  final String hint;
  final bool autoStart;

  const VoiceMic({super.key, required this.onResult, required this.hint, this.autoStart = true});

  @override
  State<VoiceMic> createState() => _VoiceMicState();
}

class _VoiceMicState extends State<VoiceMic> {
  final _speech = SpeechToText();
  String _heard = '';
  bool _listening = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _problem = null;
      _heard = '';
    });
    final ready = await _speech.initialize(
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _problem = e.errorMsg.contains('no_match') || e.errorMsg.contains('speech_timeout')
              ? "Didn't catch that. Tap the mic and try again."
              : 'Could not listen (${e.errorMsg}). Check the internet or try again.';
        });
      },
      onStatus: (s) {
        if (mounted && (s == 'done' || s == 'notListening')) setState(() => _listening = false);
      },
    );
    if (!mounted) return;
    if (!ready) {
      setState(() => _problem = 'Voice input is not available. Allow the microphone for this app in phone Settings.');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() => _heard = r.recognizedWords);
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) widget.onResult(r.recognizedWords.trim());
      },
      listenOptions: SpeechListenOptions(
        localeId: 'en_IN',
        partialResults: true,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 3),
        cancelOnError: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.hint, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _listening ? () => _speech.stop() : _start,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: _listening ? 96 : 80,
            height: _listening ? 96 : 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _listening ? Colors.red : scheme.primary,
              boxShadow: _listening ? [BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4)] : null,
            ),
            child: Icon(_listening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 40),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _problem ?? (_listening ? (_heard.isEmpty ? 'Listening…' : _heard) : 'Tap the mic to speak'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: _problem != null ? Colors.red : null, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Green mic button used above the + button.
class VoiceFab extends StatelessWidget {
  final VoidCallback onPressed;
  final Object? heroTag;
  const VoiceFab({super.key, required this.onPressed, required this.heroTag});

  @override
  Widget build(BuildContext context) => FloatingActionButton.small(
        heroTag: heroTag,
        tooltip: 'Add by voice',
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        onPressed: onPressed,
        child: const Icon(Icons.mic),
      );
}

/// Opens a sheet with the mic and returns what was said (null if closed).
Future<String?> listenOnce(BuildContext context, {required String title, required String hint}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            VoiceMic(hint: hint, onResult: (words) => Navigator.pop(sheetContext, words)),
          ],
        ),
      ),
    ),
  );
}
