import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/document_provider.dart';
import '../utils/app_theme.dart';
import '../widgets/glass_container.dart';

class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({super.key});

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen> {
  final TextEditingController _categoryController = TextEditingController();

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  void _showAddCategoryDialog(BuildContext context) {
    _categoryController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: Text('Add Category', style: GoogleFonts.outfit(color: Colors.white)),
        content: TextField(
          controller: _categoryController,
          style: GoogleFonts.inter(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Category Name',
            hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.cyan.withValues(alpha: 0.3))),
            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.cyan)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              final name = _categoryController.text.trim();
              if (name.isNotEmpty) {
                Provider.of<DocumentProvider>(context, listen: false).addCategory(name);
              }
              Navigator.pop(context);
            },
            child: Text('Add', style: GoogleFonts.inter(color: AppColors.cyan)),
          ),
        ],
      ),
    );
  }

  void _showEditCategoryDialog(BuildContext context, String oldName) {
    _categoryController.text = oldName;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: Text('Edit Category', style: GoogleFonts.outfit(color: Colors.white)),
        content: TextField(
          controller: _categoryController,
          style: GoogleFonts.inter(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Category Name',
            hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.cyan.withValues(alpha: 0.3))),
            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.cyan)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              final newName = _categoryController.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                Provider.of<DocumentProvider>(context, listen: false).editCategory(oldName, newName);
              }
              Navigator.pop(context);
            },
            child: Text('Save', style: GoogleFonts.inter(color: AppColors.cyan)),
          ),
        ],
      ),
    );
  }

  void _showResetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: Text('Reset Categories?', style: GoogleFonts.outfit(color: Colors.white)),
        content: Text(
          'This will restore the default categories. Custom categories will be removed.',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Provider.of<DocumentProvider>(context, listen: false).resetCategories();
              Navigator.pop(context);
            },
            child: Text('Reset', style: GoogleFonts.inter(color: AppColors.expired)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Manage Categories',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.restore_rounded, color: AppColors.expired),
            tooltip: 'Reset Categories',
            onPressed: () => _showResetDialog(context),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: Consumer<DocumentProvider>(
          builder: (context, provider, _) {
            final categories = provider.categories;
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: getCategoryColor(category).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(getCategoryIcon(category), color: getCategoryColor(category), size: 20),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            category,
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_rounded, color: AppColors.cyan, size: 20),
                          onPressed: () => _showEditCategoryDialog(context, category),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.expired, size: 20),
                          onPressed: () => provider.deleteCategory(category),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: (40 * index).ms).slideY(begin: 0.1, end: 0),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: AppColors.cyanPurpleGradient),
          boxShadow: AppShadows.fab,
        ),
        child: FloatingActionButton(
          backgroundColor: Colors.transparent,
          elevation: 0,
          onPressed: () => _showAddCategoryDialog(context),
          child: const Icon(Icons.add_rounded, size: 30, color: Colors.white),
        ),
      ).animate().fadeIn(delay: 200.ms).scaleXY(begin: 0.8, end: 1.0),
    );
  }
}
