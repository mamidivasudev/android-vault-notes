import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:any_link_preview/any_link_preview.dart';
import '../providers.dart';
import '../models.dart';
import '../dialogs/link_dialog.dart';
import '../widgets/category_chip_bar.dart';
import '../widgets/empty_state.dart';
import '../main_helpers.dart';

class LinksView extends ConsumerStatefulWidget {
  const LinksView({super.key});

  @override
  ConsumerState<LinksView> createState() => _LinksViewState();
}

class _LinksViewState extends ConsumerState<LinksView> {
  late PageController _categoryPageController;
  final Map<String, GlobalKey> _chipKeys = {};

  @override
  void initState() {
    super.initState();
    _categoryPageController = PageController();
  }

  @override
  void dispose() {
    _categoryPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(linkCategoriesProvider);
    final selectedCat = ref.watch(selectedLinkCategoryProvider);
    final allLinks = ref.watch(linkItemsProvider);
    final selectedLinks = ref.watch(selectedLinksProvider);
    final isSelectionMode = selectedLinks.isNotEmpty;
    final showFavs = ref.watch(showFavoritesOnlyProvider);
    
    final fullCategories = ['All', ...categories.where((c) => c != 'General')];

    // Fallback if selected category is invalid or empty
    if (fullCategories.isNotEmpty && (selectedCat.isEmpty || !fullCategories.contains(selectedCat))) {
      Future.microtask(() {
        if (mounted) ref.read(selectedLinkCategoryProvider.notifier).state = fullCategories.first;
      });
    }
    final currentSelectedCat = (fullCategories.isNotEmpty && (selectedCat.isEmpty || !fullCategories.contains(selectedCat))) ? fullCategories.first : selectedCat;

    // Sync PageController if category changes externally
    ref.listen(selectedLinkCategoryProvider, (prev, next) {
      final index = fullCategories.indexOf(next);
      if (index != -1 && _categoryPageController.hasClients && _categoryPageController.page?.round() != index) {
        _categoryPageController.jumpToPage(index);
      }
    });

    return Column(
      children: [
        CategoryChipBar(
          categories: fullCategories,
          selectedCategory: currentSelectedCat,
          onSelected: (cat) => ref.read(selectedLinkCategoryProvider.notifier).state = cat,
          onLongPress: (cat) => cat == 'All' ? null : showLinkCategoryOptions(context, ref, cat),
          onAddPressed: () => addLinkCategory(context, ref),
          onManagePressed: () => manageLinkCategoriesDialog(context, ref),
          chipKeys: _chipKeys,
          showFavoritesOnly: showFavs,
          onFavoriteToggle: () => ref.read(showFavoritesOnlyProvider.notifier).state = !showFavs,
          showPreviewsEnabled: ref.watch(showLinkPreviewsProvider),
          onPreviewsToggle: () => ref.read(showLinkPreviewsProvider.notifier).state = !ref.read(showLinkPreviewsProvider),
          itemCount: allLinks.where((l) {
            final matchCat = currentSelectedCat == 'All' || l.category == currentSelectedCat;
            final matchFav = !showFavs || l.isFavorite;
            final query = ref.watch(searchQueryProvider).toLowerCase();
            if (query.isEmpty) return matchCat && matchFav;
            return matchCat && matchFav && (l.title.toLowerCase().contains(query) || l.url.toLowerCase().contains(query));
          }).length,
        ),
        const Divider(height: 1),

        // Links List
        Expanded(
          child: PageView.builder(
            controller: _categoryPageController,
            physics: const ClampingScrollPhysics(),
            itemCount: fullCategories.length,
            onPageChanged: (index) {
              ref.read(selectedLinkCategoryProvider.notifier).state = fullCategories[index];
            },
            itemBuilder: (context, catIndex) {

              final cat = fullCategories[catIndex];
              final query = ref.watch(searchQueryProvider).toLowerCase();
              final sortOrder = ref.watch(sortOrderProvider);
              
              final filteredLinks = allLinks.where((l) {
                final matchCat = cat == 'All' || l.category == cat;
                final matchFav = !showFavs || l.isFavorite;
                if (query.isEmpty) return matchCat && matchFav;
                return matchCat && matchFav && (l.title.toLowerCase().contains(query) || l.url.toLowerCase().contains(query));
              }).toList();

              // Sort: Pinned first, then by preference
              filteredLinks.sort((a, b) {
                if (a.isPinned && !b.isPinned) return -1;
                if (!a.isPinned && b.isPinned) return 1;
                

                
                switch (sortOrder) {
                  case NoteSortOrder.dateNewest: return b.createdAt.compareTo(a.createdAt);
                  case NoteSortOrder.dateOldest: return a.createdAt.compareTo(b.createdAt);
                  case NoteSortOrder.atoz: return a.title.toLowerCase().compareTo(b.title.toLowerCase());
                  case NoteSortOrder.ztoa: return b.title.toLowerCase().compareTo(a.title.toLowerCase());
                  default: return b.createdAt.compareTo(a.createdAt);
                }
              });
              
              if (filteredLinks.isEmpty) {
                return _buildEmptyState(cat);
              }



              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: filteredLinks.length,
                itemBuilder: (context, index) {
                  final link = filteredLinks[index];
                  final isSelected = selectedLinks.contains(link.id);
                  return _LinkCard(
                    key: ValueKey(link.id),
                    link: link,
                    isSelected: isSelected,
                    isSelectionMode: isSelectionMode,
                    onTap: () {
                      if (isSelectionMode) {
                        ref.read(selectedLinksProvider.notifier).toggle(link.id);
                      } else if (link.isLocked) {
                        verifyPasscode(context, ref, onSuccess: () {
                          _launchURL(link.url);
                        });
                      } else {
                        _launchURL(link.url);
                      }
                    },
                    onLongPress: () {
                      if (!isSelectionMode) {
                        ref.read(selectedLinksProvider.notifier).toggle(link.id);
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String category) {
    return EmptyState(
      icon: Icons.link_off,
      title: 'Empty Category',
      subtitle: 'No links in "$category". Tap + to save your first link!',
      actionLabel: 'Save Link',
      onAction: () => createNewLink(context, ref),
    );
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'Could not launch $url';
      }
    } catch (e) {}
  }
}

class _LinkCard extends ConsumerWidget {
  final LinkItem link;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Widget? trailing;

  const _LinkCard({
    super.key,
    required this.link,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = _getPlatformData(link.url);
    final baseFontSize = ref.watch(fontSizeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBorder = isSelected
        ? const Color(0xFF1D63D2)
        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0));
    final titleColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final urlColor = isDark ? Colors.white38 : Colors.grey[500];
    final showPreviews = ref.watch(showLinkPreviewsProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(
          color: cardBorder,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (val) => onTap(),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: platform.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: platform.iconWidget != null
                        ? SizedBox(width: 24, height: 24, child: platform.iconWidget)
                        : Icon(platform.icon, color: platform.color, size: 20),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.isLocked
                          ? (link.title.length > 4 ? '${link.title.substring(0, 4)}...' : link.title)
                          : link.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: baseFontSize,
                        color: titleColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      link.isLocked ? '**********' : link.url,
                      style: TextStyle(
                        color: urlColor,
                        fontSize: baseFontSize - 1,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!isSelectionMode)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (link.isPinned)
                      const Icon(Icons.push_pin, size: 16, color: Color(0xFF1D63D2)),
                    if (link.isFavorite)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.favorite, size: 16, color: Colors.pink),
                      ),
                    if (link.isLocked)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.lock, size: 16, color: Colors.red),
                      ),
                    IconButton(
                      icon: Icon(
                        Icons.more_vert,
                        size: 18,
                        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                      ),
                      onPressed: () => _showContextMenu(context, ref),
                      padding: const EdgeInsets.only(left: 8),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              if (trailing != null) trailing!,
                ],
              ),
              if (showPreviews && !link.isLocked)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: IgnorePointer(
                        child: AnyLinkPreview(
                          link: link.url,
                          displayDirection: UIDirection.uiDirectionVertical,
                          showMultimedia: true,
                          bodyMaxLines: 3,
                          bodyTextOverflow: TextOverflow.ellipsis,
                          titleStyle: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          bodyStyle: TextStyle(
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            fontSize: 12,
                          ),
                          errorWidget: Container(
                            color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.link, size: 40, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Preview not available',
                                    style: TextStyle(
                                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final handleColor = isDark ? const Color(0xFF334155) : Colors.grey[200];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: handleColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  ListTile(
                    leading: Icon(link.isLocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded, color: const Color(0xFF1D63D2)),
                    title: Text(link.isLocked ? 'Unlock' : 'Lock'),
                    onTap: () {
                      if (link.isLocked) {
                        verifyPasscode(context, ref, onSuccess: () {
                          ref.read(linkItemsProvider.notifier).toggleLock(link.id);
                          Navigator.pop(context);
                        });
                      } else {
                        ref.read(linkItemsProvider.notifier).toggleLock(link.id);
                        Navigator.pop(context);
                      }
                    },
                  ),
                  if (!link.isLocked) ...[
                    ListTile(
                      leading: Icon(link.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, color: const Color(0xFF1D63D2)),
                      title: Text(link.isPinned ? 'Unpin' : 'Pin'),
                      onTap: () {
                        ref.read(linkItemsProvider.notifier).togglePin(link.id);
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      leading: Icon(link.isFavorite ? Icons.favorite : Icons.favorite_border, color: Colors.pink),
                      title: Text(link.isFavorite ? 'Remove from Favorites' : 'Add to Favorites'),
                      onTap: () {
                        ref.read(linkItemsProvider.notifier).toggleFavorite(link.id);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(link.isFavorite ? 'Removed from Favorites' : 'Added to Favorites')),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.edit_rounded, color: Color(0xFF1D63D2)),
                      title: const Text('Edit'),
                      onTap: () {
                        Navigator.pop(context);
                        showDialog(context: context, useRootNavigator: true, builder: (context) => LinkDialog(link: link));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.share_rounded, color: Color(0xFF1D63D2)),
                      title: const Text('Share Link'),
                      onTap: () {
                        Share.share('${link.title}\n${link.url}');
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.move_to_inbox_rounded, color: Color(0xFF1D63D2)),
                      title: const Text('Move to Category'),
                      onTap: () {
                        Navigator.pop(context);
                        _showMoveLinkDialog(context, ref);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.copy_rounded, color: Color(0xFF1D63D2)),
                      title: const Text('Copy URL'),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: link.url));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('URL copied to clipboard')),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                      title: const Text('Delete', style: TextStyle(color: Colors.red)),
                      onTap: () {
                        Navigator.pop(context);
                        _confirmDelete(context, ref);
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContextItem({required IconData icon, required Color color, required String title, required VoidCallback onTap}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
    );
  }

  void _showMoveLinkDialog(BuildContext context, WidgetRef ref) {
    final categories = [
      'All',
      ...ref.read(linkCategoriesProvider).where((c) => c != 'All' && c != 'General'),
    ];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: categories.map((cat) => ListTile(
            title: Text(cat),
            onTap: () {
              ref.read(linkItemsProvider.notifier).moveLinks([link.id], cat);
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete Link?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Move this link to the Recycle Bin?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(linkItemsProvider.notifier).deleteLinks([link.id]);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  _PlatformData _getPlatformData(String url) {
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('youtube.com') || lowerUrl.contains('youtu.be')) {
      return _PlatformData(
        icon: Icons.play_arrow_rounded,
        color: const Color(0xFFFF0000),
        iconWidget: Image.asset('assets/icon/youtube.png', width: 40, height: 40),
      );
    } else if (lowerUrl.contains('instagram.com')) {
      return _PlatformData(
        icon: Icons.camera_alt_rounded,
        color: const Color(0xFFE1306C),
        iconWidget: Image.asset('assets/icon/instagram.png', width: 36, height: 36),
      );
    } else if (lowerUrl.contains('facebook.com') || lowerUrl.contains('fb.com')) {
      return _PlatformData(icon: Icons.facebook_rounded, color: const Color(0xFF1877F2));
    } else if (lowerUrl.contains('twitter.com') || lowerUrl.contains('x.com')) {
      return _PlatformData(icon: Icons.close_rounded, color: Colors.black);
    } else if (lowerUrl.contains('maps.app.goo.gl') || lowerUrl.contains('google.com/maps') || lowerUrl.contains('location')) {
      return _PlatformData(
        icon: Icons.location_on_rounded,
        color: const Color(0xFF4285F4),
        iconWidget: Image.asset('assets/icon/map.png', width: 38, height: 38),
      );
    }
    return _PlatformData(icon: Icons.link_rounded, color: const Color(0xFF1D63D2));
  }
}

class _PlatformData {
  final IconData icon;
  final Color color;
  final Widget? iconWidget;
  _PlatformData({required this.icon, required this.color, this.iconWidget});
}
