import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';

class ExpenseCard extends ConsumerWidget {
  final Expense expense;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Function(bool?)? onCheckboxChanged;
  final VoidCallback onMorePressed;
  final Widget? trailing;

  const ExpenseCard({
    super.key,
    required this.expense,
    this.isSelected = false,
    this.isSelectionMode = false,
    required this.onTap,
    required this.onLongPress,
    this.onCheckboxChanged,
    required this.onMorePressed,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyFormatter = NumberFormat.decimalPattern('en_IN');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final color = expense.type == 'In'
        ? Colors.green
        : (expense.type == 'Out' ? Colors.red : Colors.blueGrey);
        
    final bgColor = expense.type == 'In'
        ? (isDark ? Colors.green.withOpacity(0.15) : Colors.green[50])
        : (expense.type == 'Out' ? (isDark ? Colors.red.withOpacity(0.15) : Colors.red[50]) : (isDark ? Colors.blueGrey.withOpacity(0.15) : Colors.blueGrey[50]));
        
    final baseFontSize = ref.watch(fontSizeProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isSelected ? 4 : 0,
      color: isSelected
          ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
          : (isDark ? const Color(0xFF0F172A) : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: onCheckboxChanged,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    expense.type == 'In'
                        ? Icons.arrow_upward
                        : (expense.type == 'Out'
                              ? Icons.arrow_downward
                              : Icons.remove),
                    color: color,
                    size: 18,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            expense.isLocked
                                ? (expense.title.length > 4
                                      ? "${expense.title.substring(0, 4)}..."
                                      : expense.title)
                                : expense.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: baseFontSize,
                              color: isDark ? Colors.white : const Color(0xFF1E293B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('d MMM').format(expense.date),
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.grey[500],
                            fontSize: baseFontSize,
                          ),
                        ),

                        if (expense.note != null &&
                            expense.note!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            expense.isLocked ? '**********' : expense.note!,
                            style: TextStyle(
                              color: const Color(0xFF60A5FA),
                              fontSize: baseFontSize - 1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),

                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₹${currencyFormatter.format(expense.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: baseFontSize + 2,
                  color: color,
                  letterSpacing: -0.5,
                ),
              ),
              if (!isSelectionMode)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (expense.isPinned)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.push_pin,
                          size: 16,
                          color: Color(0xFF1D63D2),
                        ),
                      ),
                    if (expense.isFavorite)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.favorite,
                          size: 16,
                          color: Colors.pink,
                        ),
                      ),
                    if (expense.isLocked)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.lock, size: 16, color: Colors.red),
                      ),
                    IconButton(
                      padding: const EdgeInsets.only(left: 8),
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.more_vert,
                        size: 18,
                        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                      ),
                      onPressed: onMorePressed,
                    ),
                  ],
                ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
