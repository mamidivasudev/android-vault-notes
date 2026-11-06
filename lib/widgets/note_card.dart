import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../providers.dart';

/// Colour labels a note can have. Index 0 means "no colour".
class NoteColors {
  static const names = ['Default', 'Red', 'Orange', 'Yellow', 'Green', 'Teal', 'Blue', 'Purple', 'Pink'];
  static const _light = [
    null,
    Color(0xFFFDE2E1),
    Color(0xFFFFE8CC),
    Color(0xFFFFF5C2),
    Color(0xFFDDF4DC),
    Color(0xFFD5F2EF),
    Color(0xFFDCE8FD),
    Color(0xFFEADFFB),
    Color(0xFFFBE0EE),
  ];
  static const _dark = [
    null,
    Color(0xFF4A1F22),
    Color(0xFF4A3018),
    Color(0xFF45401A),
    Color(0xFF1F3D24),
    Color(0xFF173B39),
    Color(0xFF1C2D4F),
    Color(0xFF33264D),
    Color(0xFF4A1F38),
  ];
  /// Solid swatch used in the colour picker.
  static const swatches = [
    Colors.transparent,
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFEAB308),
    Color(0xFF22C55E),
    Color(0xFF14B8A6),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
  ];

  static Color? background(int index, bool isDark) {
    if (index <= 0 || index >= _light.length) return null;
    return isDark ? _dark[index] : _light[index];
  }
}

/// "Edited 5m ago", "Edited yesterday", or a date for older edits.
String noteTimeLabel(Note note) {
  final updated = note.updatedAt;
  if (updated == null || !updated.isAfter(note.createdAt)) {
    return DateFormat('MMM dd, yyyy').format(note.createdAt);
  }
  final diff = DateTime.now().difference(updated);
  if (diff.inMinutes < 1) return 'Edited just now';
  if (diff.inMinutes < 60) return 'Edited ${diff.inMinutes}m ago';
  if (diff.inHours < 24) return 'Edited ${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Edited yesterday';
  if (diff.inDays < 7) return 'Edited ${diff.inDays}d ago';
  return 'Edited ${DateFormat('MMM dd, yyyy').format(updated)}';
}

class NoteCard extends ConsumerWidget {
  final Note note;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Function(bool?)? onCheckboxChanged;
  final VoidCallback onMorePressed;
  final Widget? trailing;
  final VoidCallback? onCameraTap;

  /// Grid layout: shows a multi-line preview instead of a single line.
  final bool isGrid;

  /// Search text to highlight in the title and preview.
  final String highlight;

  /// Shows a bell icon when the note has an active reminder.
  final bool hasReminder;

  /// Widget shown at the far left (e.g. a drag handle).
  final Widget? leading;

  const NoteCard({
    super.key,
    required this.note,
    this.isSelected = false,
    this.isSelectionMode = false,
    required this.onTap,
    required this.onLongPress,
    this.onCheckboxChanged,
    required this.onMorePressed,
    this.trailing,
    this.onCameraTap,
    this.isGrid = false,
    this.highlight = '',
    this.hasReminder = false,
    this.leading,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseFontSize = ref.watch(fontSizeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final tint = NoteColors.background(note.colorIndex, isDark);

    final titleStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: baseFontSize + 1,
      color: isDark ? Colors.white : const Color(0xFF0F172A),
    );
    final bodyStyle = TextStyle(
      color: isDark ? Colors.white60 : const Color(0xFF475569),
      fontSize: baseFontSize - 1,
    );

    return Card(
      margin: isGrid ? const EdgeInsets.all(4) : const EdgeInsets.only(bottom: 10, left: 2, right: 2),
      elevation: isSelected ? 2 : 0,
      color: isSelected
          ? Color.alphaBlend(primary.withValues(alpha: 0.08), tint ?? (isDark ? const Color(0xFF0F172A) : Colors.white))
          : (tint ?? (isDark ? const Color(0xFF0F172A) : Colors.white)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? primary : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null && !isSelectionMode) leading!,
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 10),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: onCheckboxChanged,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _highlighted(
                            note.isLocked && note.title.isEmpty
                                ? 'Locked note'
                                : (note.title.isEmpty ? 'Untitled Note' : note.title),
                            titleStyle,
                            primary,
                            maxLines: isGrid ? 2 : 1,
                          ),
                        ),
                        if (isGrid && !isSelectionMode) _statusIcons(),
                      ],
                    ),
                    _preview(bodyStyle, primary),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            noteTimeLabel(note),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white70 : const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (note.category != 'All')
                          Text(
                            '#${note.category}',
                            style: TextStyle(
                              fontSize: 9,
                              color: primary.withValues(alpha: 0.8),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isSelectionMode && !isGrid)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _statusIcons(),
                    if (onCameraTap != null && !note.isLocked)
                      IconButton(
                        padding: const EdgeInsets.only(left: 8),
                        constraints: const BoxConstraints(),
                        tooltip: 'Scan text into this note',
                        icon: Icon(Icons.document_scanner_outlined, size: 18, color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                        onPressed: onCameraTap,
                      ),
                    trailing ??
                        IconButton(
                          padding: const EdgeInsets.only(left: 8),
                          constraints: const BoxConstraints(),
                          icon: Icon(Icons.more_vert, size: 18, color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                          onPressed: onMorePressed,
                        ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusIcons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (note.isPinned) const Icon(Icons.push_pin, size: 16, color: Color(0xFF1D63D2)),
        if (hasReminder)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.notifications_active, size: 16, color: Color(0xFFF59E0B)),
          ),
        if (note.isFavorite)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.favorite, size: 16, color: Colors.pink),
          ),
        if (note.isLocked)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.lock, size: 16, color: Colors.red),
          ),
      ],
    );
  }

  Widget _preview(TextStyle style, Color primary) {
    if (note.content.isEmpty) return const SizedBox.shrink();
    if (note.isLocked) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text('**********', style: style),
      );
    }

    if (note.isChecklist) {
      final items = ChecklistItem.parse(note.content).where((i) => i.text.trim().isNotEmpty).toList();
      if (items.isEmpty) return const SizedBox.shrink();
      final done = items.where((i) => i.checked).length;
      final shown = items.take(isGrid ? 5 : 2).toList();
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in shown)
              Row(
                children: [
                  Icon(item.checked ? Icons.check_box : Icons.check_box_outline_blank, size: 14, color: style.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(
                        decoration: item.checked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ],
              ),
            if (items.length > shown.length || done > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('$done/${items.length} done', style: style.copyWith(fontSize: 10)),
              ),
          ],
        ),
      );
    }

    var text = note.content.replaceAll('\n', ' ');
    // When searching, start the preview near the first match so it's visible.
    final q = highlight.trim().toLowerCase();
    if (q.isNotEmpty && !isGrid) {
      final idx = text.toLowerCase().indexOf(q);
      if (idx > 30) text = '…${text.substring(idx - 20)}';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: _highlighted(isGrid ? note.content : text, style, primary, maxLines: isGrid ? 6 : 1),
    );
  }

  Widget _highlighted(String text, TextStyle style, Color primary, {required int maxLines}) {
    final q = highlight.trim().toLowerCase();
    if (q.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final idx = lower.indexOf(q, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: TextStyle(backgroundColor: const Color(0xFFFDE047).withValues(alpha: 0.7), color: Colors.black),
      ));
      start = idx + q.length;
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
