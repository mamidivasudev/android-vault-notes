import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/voice_mic.dart';

/// Page frame for the optional tabs, with the same blue + button as the others.
class ExtrasScaffold extends StatelessWidget {
  final Widget child;
  final VoidCallback onAdd;
  final VoidCallback? onVoice; // shows a green mic above +
  const ExtrasScaffold({super.key, required this.child, required this.onAdd, this.onVoice});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: child,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (onVoice != null) ...[
            VoiceFab(heroTag: null, onPressed: onVoice!),
            const SizedBox(height: 12),
          ],
          FloatingActionButton(
            heroTag: null,
            onPressed: onAdd,
            elevation: 4,
            backgroundColor: const Color(0xFF1D63D2),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.add, size: 30),
          ),
        ],
      ),
    );
  }
}

class ExtrasEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  final String hint;
  const ExtrasEmpty({super.key, required this.icon, required this.text, required this.hint});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: muted.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(hint, textAlign: TextAlign.center, style: TextStyle(color: muted)),
          ],
        ),
      ),
    );
  }
}

class ExtrasHeading extends StatelessWidget {
  final String text;
  final String? trailing;
  const ExtrasHeading(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Row(
        children: [
          Text(text.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: color)),
          const Spacer(),
          if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// Bottom-sheet form: title, fields, then Delete (when editing) and Save.
class ExtrasSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final VoidCallback? onDelete;
  final String saveLabel;
  const ExtrasSheet({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.onDelete,
    this.saveLabel = 'Save',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        // Keep Save above the phone's nav buttons.
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 16),
            Row(
              children: [
                if (onDelete != null)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                    onPressed: onDelete,
                  ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(onPressed: onSave, child: Text(saveLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable date field ("16 Nov 2026"), with an optional clear button.
class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool clearable;
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.clearable = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime(2200),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: clearable && value != null
              ? IconButton(icon: const Icon(Icons.close), tooltip: 'Clear', onPressed: () => onChanged(null))
              : const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(value == null ? 'Not set' : DateFormat('d MMM yyyy').format(value!)),
      ),
    );
  }
}

/// "₹1,250" / "₹49.5".
String rupees(double v) => '₹${NumberFormat('#,##0.##').format(v)}';
