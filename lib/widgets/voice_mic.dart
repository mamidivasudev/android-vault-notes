import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Big mic that listens once (Indian English or Telugu) and hands back what was said.
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

/// Language last picked on any mic screen (kept while the app is open).
String voiceLocale = 'en_IN';

class _VoiceMicState extends State<VoiceMic> {
  final _speech = SpeechToText();
  bool _ready = false;
  String _said = ''; // finished parts
  String _partial = ''; // words still being recognised
  bool _active = false; // keep listening until OK is tapped
  bool _listening = false;
  bool _finishing = false;
  String? _problem;

  String get _text => [_said, _partial].where((p) => p.trim().isNotEmpty).join(' ').trim();

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  @override
  void dispose() {
    _active = false;
    _speech.cancel();
    super.dispose();
  }

  Future<bool> _init() async {
    if (_ready) return true;
    _ready = await _speech.initialize(
      onError: (e) {
        if (!mounted) return;
        final quiet = e.errorMsg.contains('no_match') || e.errorMsg.contains('speech_timeout');
        // A pause just ends one round; listening carries on.
        if (quiet && _active) return;
        setState(() {
          _active = false;
          _listening = false;
          _problem = quiet ? "Didn't catch that. Tap the mic and try again." : 'Could not listen (${e.errorMsg}). Check the internet or try again.';
        });
      },
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _listening = false);
          // Android stops after a short silence: start again until OK is tapped.
          if (_active && !_finishing) {
            Future.delayed(const Duration(milliseconds: 250), _listenRound);
          }
        }
      },
    );
    return _ready;
  }

  Future<void> _begin() async {
    setState(() {
      _problem = null;
      _active = true;
    });
    if (!await _init()) {
      if (mounted) {
        setState(() {
          _active = false;
          _problem = 'Voice input is not available. Allow the microphone for this app in phone Settings.';
        });
      }
      return;
    }
    HapticFeedback.selectionClick();
    await _listenRound();
  }

  Future<void> _listenRound() async {
    if (!mounted || !_active || _finishing || _speech.isListening) return;
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() {
          if (r.finalResult) {
            if (r.recognizedWords.trim().isNotEmpty) _said = '$_said ${r.recognizedWords.trim()}'.trim();
            _partial = '';
          } else {
            _partial = r.recognizedWords;
          }
        });
      },
      listenOptions: SpeechListenOptions(
        localeId: voiceLocale,
        partialResults: true,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 10),
        cancelOnError: false,
      ),
    );
  }

  /// Mic button: pause / carry on listening.
  Future<void> _toggle() async {
    if (_active) {
      setState(() => _active = false);
      await _speech.stop();
    } else {
      _begin();
    }
  }

  /// OK: stop and hand over everything that was said.
  Future<void> _ok() async {
    setState(() {
      _finishing = true;
      _active = false;
    });
    await _speech.stop();
    await Future.delayed(const Duration(milliseconds: 400)); // last words arrive
    if (!mounted) return;
    final text = _text;
    if (text.isEmpty) {
      setState(() {
        _finishing = false;
        _problem = 'Nothing heard yet. Tap the mic and speak.';
      });
      return;
    }
    widget.onResult(text);
  }

  void _clear() => setState(() {
        _said = '';
        _partial = '';
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = _text;
    final live = _active && !_finishing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // English or Telugu (Telugu is written in Telugu letters, which match
        // the product list's Telugu names).
        SegmentedButton<String>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: 'en_IN', label: Text('English')),
            ButtonSegment(value: 'te_IN', label: Text('తెలుగు')),
          ],
          selected: {voiceLocale},
          onSelectionChanged: (v) async {
            setState(() => voiceLocale = v.first);
            await _speech.cancel();
            _begin(); // carry on in the new language
          },
        ),
        const SizedBox(height: 12),
        Text(widget.hint, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _finishing ? null : _toggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: live ? 96 : 80,
            height: live ? 96 : 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: live ? Colors.red : scheme.primary,
              boxShadow: live ? [BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4)] : null,
            ),
            child: Icon(live ? Icons.mic : Icons.mic_none, color: Colors.white, size: 40),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _problem ?? (text.isNotEmpty ? text : (live ? 'Listening… speak, then tap OK' : 'Tap the mic to speak')),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: _problem != null ? Colors.red : null, fontWeight: FontWeight.w600),
        ),
        if (live)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _listening ? 'Listening…' : 'Still listening — keep talking',
              style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.5)),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            if (text.isNotEmpty) TextButton(onPressed: _finishing ? null : _clear, child: const Text('Clear')),
            const Spacer(),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('OK'),
              onPressed: _finishing || text.isEmpty ? null : _ok,
            ),
          ],
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
