import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CategoryChipBar extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final Function(String) onSelected;
  final Function(String)? onLongPress;
  final VoidCallback onAddPressed;
  final VoidCallback onManagePressed;
  final Map<String, GlobalKey> chipKeys;

  final bool showFavoritesOnly;
  final VoidCallback onFavoriteToggle;
  final int itemCount;
  final bool showGroupByDateToggle;
  final bool groupByDateEnabled;
  final VoidCallback? onGroupByDateToggle;
  final bool showPreviewsEnabled;
  final VoidCallback? onPreviewsToggle;

  const CategoryChipBar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
    this.onLongPress,
    required this.onAddPressed,
    required this.onManagePressed,
    required this.chipKeys,
    required this.showFavoritesOnly,
    required this.onFavoriteToggle,
    required this.itemCount,
    this.showGroupByDateToggle = false,
    this.groupByDateEnabled = false,
    this.onGroupByDateToggle,
    this.showPreviewsEnabled = false,
    this.onPreviewsToggle,
  });

  void _showAllCategories(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final containerBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: containerBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'All Categories',
                    style: GoogleFonts.lexend(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 2.2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  final isSelected = cat == selectedCategory;
                  return InkWell(
                    onTap: () {
                      onSelected(cat);
                      Navigator.pop(context);
                    },
                    onLongPress: onLongPress != null ? () {
                      Navigator.pop(context); // Close bottom sheet first
                      onLongPress!(cat);
                    } : null,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? Theme.of(context).colorScheme.primary : cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? Theme.of(context).colorScheme.primary : borderColor,
                          width: 1.5,
                        ),
                        boxShadow: isSelected ? [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          )
                        ] : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        cat,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final containerBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final dividerColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: containerBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primaryColor.withOpacity(isDark ? 0.35 : 0.25), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(isDark ? 0.06 : 0.08),
              blurRadius: 16,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () => _showAllCategories(context),
                onLongPress: onLongPress != null ? () => onLongPress!(selectedCategory) : null,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedCategory,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.lexend(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down_rounded, color: isDark ? Colors.white60 : Colors.grey, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            Text(
              '$itemCount',
              style: GoogleFonts.lexend(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.grey[600],
              ),
            ),
            IconButton(
              icon: Icon(
                showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
                color: Colors.redAccent,
                size: 22,
              ),
              onPressed: onFavoriteToggle,
              tooltip: 'Show Favorites Only',
              splashRadius: 24,
            ),
            if (onPreviewsToggle != null)
              IconButton(
                icon: Icon(
                  showPreviewsEnabled ? Icons.image : Icons.image_outlined,
                  color: showPreviewsEnabled ? primaryColor : (isDark ? Colors.white60 : Colors.grey.shade600),
                  size: 22,
                ),
                onPressed: onPreviewsToggle,
                tooltip: showPreviewsEnabled ? 'Hide Previews' : 'Show Previews',
                splashRadius: 24,
              ),
            if (showGroupByDateToggle && onGroupByDateToggle != null)
              IconButton(
                icon: Icon(
                  groupByDateEnabled ? Icons.visibility : Icons.visibility_off_outlined,
                  color: groupByDateEnabled ? primaryColor : (isDark ? Colors.white60 : Colors.grey.shade600),
                  size: 22,
                ),
                onPressed: onGroupByDateToggle,
                tooltip: groupByDateEnabled ? 'Show flat list' : 'Group by date',
                splashRadius: 24,
              ),
            Container(
              width: 1,
              height: 24,
              color: dividerColor,
            ),
            IconButton(
              icon: Icon(Icons.settings_rounded, color: primaryColor, size: 22),
              onPressed: onManagePressed,
              tooltip: 'Manage Categories',
              splashRadius: 24,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
