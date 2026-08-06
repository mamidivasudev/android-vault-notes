import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/document_provider.dart';
import '../models/document_model.dart';
import '../widgets/glass_container.dart';
import '../utils/app_theme.dart';
import '../utils/app_routes.dart';
import 'document_form_screen.dart';
import 'category_screen.dart';
import 'settings_screen.dart';

class DocsHomeScreen extends StatefulWidget {
  const DocsHomeScreen({super.key});

  @override
  _DocsHomeScreenState createState() => _DocsHomeScreenState();
}

class _DocsHomeScreenState extends State<DocsHomeScreen> with SingleTickerProviderStateMixin {


  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;
  late AnimationController _fabAnimController;

  @override
  void initState() {
    super.initState();
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fabAnimController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context),
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: Consumer<DocumentProvider>(
          builder: (context, provider, _) {
            final allDocs = provider.documents;

            // Build category set
            final Set<String> allCategories = {...provider.categories};
            for (var doc in allDocs) {
              allCategories.add(doc.category);
            }

            // Filter by search
            List<String> filteredCategories = allCategories.toList()..sort();
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              filteredCategories = filteredCategories
                  .where((c) => c.toLowerCase().contains(q))
                  .toList();
            }

            // Stats
            final expiredCount = allDocs.where((d) {
              if (d.expiryDate == null) return false;
              return d.expiryDate!.isBefore(DateTime.now());
            }).length;
            final expiringSoonCount = allDocs.where((d) {
              if (d.expiryDate == null) return false;
              final days = d.expiryDate!.difference(DateTime.now()).inDays;
              return days >= 0 && days <= 30;
            }).length;

            return SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  _buildHeader(context, allDocs.length, expiredCount, expiringSoonCount),

                  // Search Bar
                  if (_isSearching)
                    _buildSearchBar()
                        .animate()
                        .fadeIn(duration: 200.ms)
                        .slideY(begin: -0.3, end: 0, curve: Curves.easeOut),

                  // Section Title
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _searchQuery.isNotEmpty
                              ? '${filteredCategories.length} Categories Found'
                              : 'Your Vault',
                          style: GoogleFonts.outfit(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '${allDocs.length} docs',
                          style: GoogleFonts.outfit(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Category Grid
                  Expanded(
                    child: filteredCategories.isEmpty
                        ? _buildEmptyState()
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.75,
                            ),
                            itemCount: filteredCategories.length,
                            itemBuilder: (context, index) {
                              final category = filteredCategories[index];
                              final docs = allDocs
                                  .where((d) => d.category == category)
                                  .toList();
                              return _buildCategoryCard(context, category, docs, index);
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: _buildFAB(context),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Colors.white),
        onPressed: () {
          Scaffold.of(context).openDrawer();
        },
        tooltip: 'Menu',
      ),
      title: Text(
        'Docs Vault',
        style: GoogleFonts.outfit(
          fontWeight: FontWeight.bold,
          fontSize: 26,
          letterSpacing: 0.8,
          foreground: Paint()
            ..shader = const LinearGradient(
              colors: [AppColors.cyan, AppColors.purple],
            ).createShader(const Rect.fromLTWH(0, 0, 150, 30)),
        ),
      ),
      actions: [
        IconButton(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _isSearching ? Icons.search_off_rounded : Icons.search_rounded,
              key: ValueKey(_isSearching),
              color: _isSearching ? AppColors.cyan : Colors.white,
            ),
          ),
          onPressed: _toggleSearch,
          tooltip: 'Search',
        ),
        IconButton(
          icon: const Icon(Icons.settings_rounded, color: Colors.white),
          onPressed: () => Navigator.push(
            context,
            SlideRoute(page: SettingsScreen()),
          ),
          tooltip: 'Settings',
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, int total, int expired, int expiringSoon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My Documents',
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1, end: 0),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.folder_rounded,
                  label: 'Total',
                  value: total.toString(),
                  color: AppColors.cyan,
                ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.2, end: 0),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.warning_amber_rounded,
                  label: 'Expiring Soon',
                  value: expiringSoon.toString(),
                  color: AppColors.expiringSoon,
                ).animate().fadeIn(delay: 180.ms).slideY(begin: 0.2, end: 0),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.error_rounded,
                  label: 'Expired',
                  value: expired.toString(),
                  color: AppColors.expired,
                ).animate().fadeIn(delay: 260.ms).slideY(begin: 0.2, end: 0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
        ),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search categories or documents...',
            hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
            prefixIcon: const Icon(Icons.search, color: AppColors.cyan, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: AppColors.textMuted, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(BuildContext context, String category, List<DocumentModel> docs, int index) {
    final color = getCategoryColor(category);
    final icon = getCategoryIcon(category);
    final count = docs.length;

    // Check if any doc in this category is expiring/expired
    final hasExpired = docs.any((d) => d.expiryDate != null && d.expiryDate!.isBefore(DateTime.now()));
    final hasExpiringSoon = docs.any((d) {
      if (d.expiryDate == null) return false;
      final days = d.expiryDate!.difference(DateTime.now()).inDays;
      return days >= 0 && days <= 30;
    });

    Color? alertColor;
    if (hasExpired) { alertColor = AppColors.expired; }
    else if (hasExpiringSoon) { alertColor = AppColors.expiringSoon; }

    return GlassContainer(
      padding: EdgeInsets.zero,
      accentColor: alertColor ?? color,
      showGlow: alertColor != null,
      onTap: () => Navigator.push(
        context,
        SlideRoute(page: CategoryScreen(categoryName: category)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
                  ),
                  child: Icon(icon, size: 26, color: color),
                ),
                if (alertColor != null)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: alertColor,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: alertColor.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 1)],
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              category,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.white,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count ${count == 1 ? 'doc' : 'docs'}',
                    style: GoogleFonts.inter(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: (40 * index).ms, duration: 400.ms)
        .scaleXY(begin: 0.92, end: 1.0, curve: Curves.easeOutBack);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.cyan.withValues(alpha: 0.2)),
            ),
            child: const Icon(Icons.search_off_rounded, size: 52, color: AppColors.cyan),
          ).animate().fadeIn().scale(),
          const SizedBox(height: 20),
          Text(
            'No categories found',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildFAB(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: AppColors.cyanPurpleGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: AppShadows.fab,
      ),
      child: FloatingActionButton(
        backgroundColor: Colors.transparent,
        elevation: 0,
        tooltip: 'Add Document',
        onPressed: () => Navigator.push(
          context,
          FadeScaleRoute(page: DocumentFormScreen()),
        ),
        child: const Icon(Icons.add_rounded, size: 30, color: Colors.white),
      ),
    ).animate().fadeIn(delay: 500.ms).scaleXY(begin: 0.8, end: 1.0, curve: Curves.easeOutBack);
  }
}
