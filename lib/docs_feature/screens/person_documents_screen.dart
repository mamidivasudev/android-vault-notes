import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/document_provider.dart';
import '../models/document_model.dart';
import '../widgets/glass_container.dart';
import '../widgets/expiry_badge.dart';
import '../utils/app_theme.dart';
import '../utils/app_routes.dart';
import 'document_detail_screen.dart';
import 'document_form_screen.dart';

class PersonDocumentsScreen extends StatefulWidget {
  final String categoryName;
  final String personName;

  const PersonDocumentsScreen({
    super.key,
    required this.categoryName,
    required this.personName,
  });

  @override
  State<PersonDocumentsScreen> createState() => _PersonDocumentsScreenState();
}

class _PersonDocumentsScreenState extends State<PersonDocumentsScreen> {
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isSharing = false;

  void _toggleSelectionMode(List<DocumentModel> docs) {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedIds.clear();
    });
  }

  void _toggleSelectAll(List<DocumentModel> docs) {
    setState(() {
      if (_selectedIds.length == docs.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(docs.map((d) => d.id));
      }
    });
  }

  Future<void> _shareSelected(List<DocumentModel> docs) async {
    if (_selectedIds.isEmpty) return;

    setState(() => _isSharing = true);
    
    final selectedDocs = docs.where((d) => _selectedIds.contains(d.id)).toList();
    final List<XFile> files = [];
    String text = 'Sharing ${selectedDocs.length} document(s) from LifeVault:\n\n';
    
    for (var doc in selectedDocs) {
      text += '• ${doc.title}\n';
      if (doc.issueDate != null) text += '  Issued: ${DateFormat.yMMMd().format(doc.issueDate!)}\n';
      if (doc.expiryDate != null) text += '  Expires: ${DateFormat.yMMMd().format(doc.expiryDate!)}\n';
      for (var path in doc.imagePaths) {
        files.add(XFile(path));
      }
      text += '\n';
    }

    try {
      if (files.isNotEmpty) {
        await Share.shareXFiles(files, text: text);
      } else {
        await Share.share(text);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
          _isSelectionMode = false;
          _selectedIds.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = getCategoryColor(widget.categoryName);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
          ),
          onPressed: () {
            if (_isSelectionMode) {
              setState(() => _isSelectionMode = false);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Column(
          children: [
            Text(
              _isSelectionMode ? '${_selectedIds.length} Selected' : widget.personName,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            if (!_isSelectionMode)
              Text(
                widget.categoryName,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: categoryColor,
                ),
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          Consumer<DocumentProvider>(
            builder: (context, provider, _) {
              final personDocs = provider.documents
                  .where((d) => d.category == widget.categoryName && d.personName == widget.personName)
                  .toList();
              
              if (personDocs.isEmpty) return const SizedBox();

              if (_isSelectionMode) {
                return IconButton(
                  icon: Icon(
                    _selectedIds.length == personDocs.length ? Icons.deselect_rounded : Icons.select_all_rounded,
                    color: categoryColor,
                  ),
                  onPressed: () => _toggleSelectAll(personDocs),
                  tooltip: 'Select All',
                );
              } else {
                return IconButton(
                  icon: const Icon(Icons.share_rounded, color: Colors.white),
                  onPressed: () => _toggleSelectionMode(personDocs),
                  tooltip: 'Share',
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Consumer<DocumentProvider>(
            builder: (context, provider, _) {
              final personDocs = provider.documents
                  .where((d) => d.category == widget.categoryName && d.personName == widget.personName)
                  .toList();

              if (personDocs.isEmpty) {
                return _buildEmptyState(context, categoryColor);
              }

              return RefreshIndicator(
                color: AppColors.cyan,
                backgroundColor: AppColors.surface,
                onRefresh: () async {
                  provider.loadDocuments();
                },
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: personDocs.length,
                  itemBuilder: (context, index) {
                    final doc = personDocs[index];
                    return _buildDocumentCard(context, doc, categoryColor, index);
                  },
                ),
              );
            },
          ),
        ),
      ),
      floatingActionButton: Consumer<DocumentProvider>(
        builder: (context, provider, _) {
          final personDocs = provider.documents
              .where((d) => d.category == widget.categoryName && d.personName == widget.personName)
              .toList();
          return _buildFAB(context, personDocs);
        },
      ),
    );
  }

  Widget _buildDocumentCard(
      BuildContext context, DocumentModel doc, Color color, int index) {
    final expiryColor = getExpiryColor(doc.expiryDate);
    final isExpired = doc.expiryDate != null && doc.expiryDate!.isBefore(DateTime.now());
    final isExpiringSoon = doc.expiryDate != null &&
        doc.expiryDate!.difference(DateTime.now()).inDays <= 30 &&
        !isExpired;
    final hasAlert = isExpired || isExpiringSoon;
    
    final isSelected = _selectedIds.contains(doc.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassContainer(
        padding: EdgeInsets.zero,
        accentColor: _isSelectionMode && isSelected ? AppColors.cyan : (hasAlert ? expiryColor : color),
        showGlow: hasAlert || (_isSelectionMode && isSelected),
        onTap: () {
          if (_isSelectionMode) {
            setState(() {
              if (isSelected) {
                _selectedIds.remove(doc.id);
              } else {
                _selectedIds.add(doc.id);
              }
            });
          } else {
            Navigator.push(
              context,
              SlideRoute(page: DocumentDetailScreen(document: doc)),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              if (_isSelectionMode) ...[
                Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: isSelected ? AppColors.cyan : AppColors.textMuted,
                  size: 24,
                ),
                const SizedBox(width: 16),
              ],
              
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Icon(Icons.description_rounded, color: color, size: 24),
              ),
              const SizedBox(width: 16),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.title,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (doc.issueDate != null) ...[
                          Icon(Icons.calendar_today_rounded,
                              size: 11, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat.yMMMd().format(doc.issueDate!),
                            style: GoogleFonts.inter(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (doc.imagePaths.isNotEmpty) ...[
                          Icon(Icons.attach_file_rounded,
                              size: 11, color: AppColors.textMuted),
                          const SizedBox(width: 3),
                          Text(
                            '${doc.imagePaths.length}',
                            style: GoogleFonts.inter(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    ExpiryBadge(expiryDate: doc.expiryDate),
                  ],
                ),
              ),

              if (!_isSelectionMode)
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: AppColors.textMuted, size: 14),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: (60 * index).ms, duration: 350.ms)
        .slideX(begin: 0.12, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _buildEmptyState(BuildContext context, Color color) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Icon(Icons.description_outlined, size: 56, color: color),
          ).animate().fadeIn().scale(),
          const SizedBox(height: 24),
          Text(
            'No documents for ${widget.personName}',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ).animate().fadeIn(delay: 100.ms),
          const SizedBox(height: 8),
          Text(
            'Add a ${widget.categoryName} document below',
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
          ).animate().fadeIn(delay: 180.ms),
        ],
      ),
    );
  }

  Widget _buildFAB(BuildContext context, List<DocumentModel> docs) {
    if (_isSelectionMode) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: AppColors.cyanPurpleGradient,
          ),
          boxShadow: AppShadows.fab,
        ),
        child: FloatingActionButton.extended(
          backgroundColor: Colors.transparent,
          elevation: 0,
          onPressed: _selectedIds.isEmpty || _isSharing ? null : () => _shareSelected(docs),
          icon: _isSharing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.share_rounded, color: Colors.white),
          label: Text(
            _isSharing ? 'Sharing...' : 'Share ${_selectedIds.length}',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ).animate().fadeIn().slideY(begin: 0.5, end: 0);
    }

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
          FadeScaleRoute(
            page: DocumentFormScreen(
              initialCategory: widget.categoryName,
              initialPerson: widget.personName,
            ),
          ),
        ),
        child: const Icon(Icons.add_rounded, size: 28, color: Colors.white),
      ),
    ).animate().fadeIn(delay: 400.ms).scaleXY(begin: 0.8, end: 1.0, curve: Curves.easeOutBack);
  }
}
