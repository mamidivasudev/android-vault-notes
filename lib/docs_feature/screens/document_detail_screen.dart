import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:open_filex/open_filex.dart';
import '../models/document_model.dart';
import '../providers/document_provider.dart';
import '../utils/app_theme.dart';
import '../utils/app_routes.dart';
import 'document_form_screen.dart';

class DocumentDetailScreen extends StatefulWidget {
  final DocumentModel document;

  const DocumentDetailScreen({super.key, required this.document});

  @override
  _DocumentDetailScreenState createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  int _currentImageIndex = 0;
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showFullScreenImage(BuildContext context, String path, int index) {
    HapticFeedback.lightImpact();
    Navigator.push(context, FadeScaleRoute(page: _FullScreenImageViewer(
      paths: widget.document.imagePaths,
      initialIndex: index,
    )));
  }

  Future<void> _confirmDelete(BuildContext context, DocumentProvider provider, DocumentModel doc) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.expired.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_forever_rounded, color: AppColors.expired, size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                'Delete Document?',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '"${doc.title}" will be permanently deleted.',
                style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.borderSubtle),
                        foregroundColor: AppColors.textSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Cancel', style: GoogleFonts.outfit()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.expired,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Delete', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true && mounted) {
      provider.deleteDocument(doc.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DocumentProvider>(context);
    final idx = provider.documents.indexWhere((d) => d.id == widget.document.id);

    if (idx == -1) {
      // Deleted - go back gracefully
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const Scaffold(backgroundColor: AppColors.background);
    }

    final document = provider.documents[idx];
    final hasImages = document.imagePaths.isNotEmpty;
    final categoryColor = getCategoryColor(document.category);
    final expiryColor = getExpiryColor(document.expiryDate);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Sliver App Bar with images or gradient header
          SliverAppBar(
            expandedHeight: hasImages ? 320.0 : 180.0,
            floating: false,
            pinned: true,
            backgroundColor: AppColors.background,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    FadeScaleRoute(page: DocumentFormScreen(existingDocument: document)),
                  ),
                  tooltip: 'Edit',
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.expired.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_rounded, color: AppColors.expired, size: 18),
                  ),
                  onPressed: () => _confirmDelete(context, provider, document),
                  tooltip: 'Delete',
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 60, bottom: 16, right: 60),
              title: Text(
                document.title,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  shadows: [const Shadow(color: Colors.black, blurRadius: 12, offset: Offset(0, 2))],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              background: hasImages
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        PageView.builder(
                          controller: _pageController,
                          itemCount: document.imagePaths.length,
                          onPageChanged: (i) => setState(() => _currentImageIndex = i),
                          itemBuilder: (context, index) {
                            final path = document.imagePaths[index];
                            final isPdf = path.toLowerCase().endsWith('.pdf');
                            return GestureDetector(
                              onTap: () {
                                if (isPdf) {
                                  OpenFilex.open(path);
                                } else {
                                  _showFullScreenImage(context, path, index);
                                }
                              },
                              child: isPdf
                                  ? Container(
                                      color: AppColors.surfaceLight,
                                      child: const Center(
                                        child: Icon(Icons.picture_as_pdf_rounded, size: 80, color: AppColors.expired),
                                      ),
                                    )
                                  : Hero(
                                      tag: 'img_${document.id}_$index',
                                      child: Image.file(File(path), fit: BoxFit.cover),
                                    ),
                            );
                          },
                        ),
                        // Gradient overlay
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.transparent,
                                Color(0x99000000),
                                AppColors.background,
                              ],
                              stops: [0.0, 0.4, 0.75, 1.0],
                            ),
                          ),
                        ),
                        // Page indicator
                        if (document.imagePaths.length > 1)
                          Positioned(
                            bottom: 60,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                document.imagePaths.length,
                                (i) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  width: _currentImageIndex == i ? 18 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: _currentImageIndex == i
                                        ? AppColors.cyan
                                        : Colors.white.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            categoryColor.withValues(alpha: 0.4),
                            AppColors.background,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 40),
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: categoryColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                                border: Border.all(color: categoryColor.withValues(alpha: 0.3)),
                              ),
                              child: Icon(getCategoryIcon(document.category),
                                  size: 48, color: categoryColor),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),

          // Document Details
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category + Person chips
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _buildChip(
                        icon: getCategoryIcon(document.category),
                        label: document.category,
                        color: categoryColor,
                      ),
                      _buildChip(
                        icon: Icons.person_rounded,
                        label: document.personName,
                        color: AppColors.purple,
                      ),
                      _buildChip(
                        icon: Icons.notes_rounded,
                        label: 'Notes',
                        color: AppColors.expiringSoon,
                        onTap: () => _showNotesBottomSheet(context, provider, document),
                      ),
                    ],
                  ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),

                  const SizedBox(height: 24),

                  // Expiry Status Banner (if not valid/no expiry)
                  if (document.expiryDate != null)
                    _buildExpiryBanner(document.expiryDate!, expiryColor),

                  const SizedBox(height: 24),

                  // Date Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildDateCard(
                          icon: Icons.event_available_rounded,
                          title: 'Issue Date',
                          date: document.issueDate,
                          color: AppColors.cyan,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildDateCard(
                          icon: Icons.event_busy_rounded,
                          title: 'Expiry Date',
                          date: document.expiryDate,
                          color: expiryColor,
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.15, end: 0),

                  // Display Saved Notes
                  if (document.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.notes_rounded, color: AppColors.textMuted, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Saved Notes',
                                style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            document.notes,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 14, height: 1.4),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),
                  ],

                  // Attached Images section
                  if (hasImages) ...[
                    const SizedBox(height: 28),
                    _buildImagesSection(document),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip({required IconData icon, required String label, required Color color, VoidCallback? onTap}) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: chip);
    }
    return chip;
  }

  Widget _buildExpiryBanner(DateTime expiryDate, Color color) {
    final label = getExpiryLabel(expiryDate);
    final days = expiryDate.difference(DateTime.now()).inDays;
    final isExpired = days < 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isExpired ? Icons.error_rounded : Icons.warning_amber_rounded,
            color: color,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  'Expires: ${DateFormat.yMMMMd().format(expiryDate)}',
                  style: GoogleFonts.inter(color: color.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildDateCard({
    required IconData icon,
    required String title,
    required DateTime? date,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            date != null ? DateFormat.yMMMd().format(date) : 'Not set',
            style: GoogleFonts.outfit(
              color: date != null ? Colors.white : AppColors.textMuted,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _showNotesBottomSheet(BuildContext context, DocumentProvider provider, DocumentModel document) {
    final notesController = TextEditingController(text: document.notes);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Notes',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      document.notes = notesController.text.trim();
                      provider.updateDocument(document);
                      Navigator.pop(ctx);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.cyan,
                    ),
                    child: Text('Save', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: TextField(
                  controller: notesController,
                  maxLines: 8,
                  minLines: 3,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Enter your notes here...',
                    hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
                    contentPadding: const EdgeInsets.all(16),
                    border: InputBorder.none,
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  autofocus: true,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagesSection(DocumentModel document) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Attachments',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${document.imagePaths.length}',
                style: GoogleFonts.inter(
                    color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: document.imagePaths.length,
            itemBuilder: (context, index) {
              final path = document.imagePaths[index];
              final isPdf = path.toLowerCase().endsWith('.pdf');
              return GestureDetector(
                onTap: () {
                  if (isPdf) {
                    OpenFilex.open(path);
                  } else {
                    _showFullScreenImage(context, path, index);
                  }
                },
                child: Hero(
                  tag: 'img_${document.id}_$index',
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    width: 110,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: isPdf ? AppColors.expired.withValues(alpha: 0.1) : null,
                      image: isPdf
                          ? null
                          : DecorationImage(
                              image: FileImage(File(path)),
                              fit: BoxFit.cover,
                            ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                    child: Align(
                      alignment: isPdf ? Alignment.center : Alignment.topRight,
                      child: isPdf
                          ? const Icon(Icons.picture_as_pdf_rounded, color: AppColors.expired, size: 40)
                          : Container(
                              margin: const EdgeInsets.all(6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 14),
                            ),
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: (60 * index).ms).scaleXY(begin: 0.9, end: 1.0);
            },
          ),
        ),
      ],
    ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.15, end: 0);
  }
}

// Full screen image viewer
class _FullScreenImageViewer extends StatefulWidget {
  final List<String> paths;
  final int initialIndex;

  const _FullScreenImageViewer({required this.paths, required this.initialIndex});

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late int _currentIndex;
  late PageController _controller;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        elevation: 0,
        title: Text(
          '${_currentIndex + 1} / ${widget.paths.length}',
          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.paths.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, index) {
          final path = widget.paths[index];
          final isPdf = path.toLowerCase().endsWith('.pdf');
          return InteractiveViewer(
            child: Center(
              child: isPdf
                  ? const Icon(Icons.picture_as_pdf_rounded, color: AppColors.expired, size: 100)
                  : Image.file(
                      File(path),
                      fit: BoxFit.contain,
                    ),
            ),
          );
        },
      ),
    );
  }
}
