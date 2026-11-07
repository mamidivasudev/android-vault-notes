import 'package:flutter/material.dart';

const kToastGreen = Color(0xFF16A34A);
const kToastBlue = Color(0xFF3B6FD8);
const kToastRed = Color(0xFFD9534F);

OverlayEntry? _currentToast;

/// Small coloured pill that drops in at the top of the screen and fades away
/// by itself. With [actionLabel] it gets a button (e.g. UNDO) and stays a bit
/// longer so there is time to tap it.
void showTopToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle,
  Color color = kToastGreen,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _currentToast?.remove();
  _currentToast = null;
  final hasAction = actionLabel != null && onAction != null;

  late final OverlayEntry entry;
  void close() {
    if (_currentToast == entry) _currentToast = null;
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      top: MediaQuery.viewPaddingOf(ctx).top + 12,
      left: 24,
      right: 24,
      child: IgnorePointer(
        ignoring: !hasAction,
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(offset: Offset(0, -16 * (1 - t)), child: child),
            ),
            child: Material(
              color: color,
              elevation: 6,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, hasAction ? 2 : 9, hasAction ? 4 : 16, hasAction ? 2 : 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    if (hasAction) ...[
                      const SizedBox(width: 4),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
                        onPressed: () {
                          close();
                          onAction();
                        },
                        child: Text(actionLabel),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  _currentToast = entry;
  overlay.insert(entry);
  Future.delayed(Duration(milliseconds: hasAction ? 4000 : 1600), close);
}

/// Standard "Are you sure?" dialog with No / Yes. Returns true for Yes.
Future<bool> confirmYesNo(BuildContext context, String title, String message) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kToastRed),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );
  return ok == true;
}
