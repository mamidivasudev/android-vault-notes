import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../providers.dart';

class NoteCard extends ConsumerWidget {
  final Note note;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Function(bool?)? onCheckboxChanged;
  final VoidCallback onMorePressed;

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
  });

  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseFontSize = ref.watch(fontSizeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 10, left: 2, right: 2),
      elevation: isSelected ? 2 : 0,
      color: isSelected 
          ? Theme.of(context).colorScheme.primary.withOpacity(0.08) 
          : (isDark ? const Color(0xFF0F172A) : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected 
              ? Theme.of(context).colorScheme.primary 
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
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
                      children: [
                        Expanded(
                          child: Text(
                            note.isLocked 
                              ? (note.title.length > 4 ? "${note.title.substring(0, 4)}..." : note.title)
                              : (note.title.isEmpty ? 'Untitled Note' : note.title),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: baseFontSize + 1,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (note.content.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        note.isLocked ? '**********' : note.content.replaceAll('\n', ' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white60 : const Color(0xFF475569),
                          fontSize: baseFontSize - 1,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getFormattedDate(note.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white70 : const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (note.category != 'All')
                          Text(
                            '#${note.category}',
                            style: TextStyle(
                              fontSize: 9,
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isSelectionMode)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (note.isPinned)
                      const Icon(Icons.push_pin, size: 16, color: Color(0xFF1D63D2)),
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
                    trailing ?? IconButton(
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

  String _getFormattedDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }
}
