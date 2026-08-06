import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/document_provider.dart';
import '../models/document_model.dart';
import '../widgets/glass_container.dart';
import '../utils/app_theme.dart';
import '../utils/app_routes.dart';
import 'document_form_screen.dart';
import 'person_documents_screen.dart';

class CategoryScreen extends StatelessWidget {
  final String categoryName;

  const CategoryScreen({super.key, required this.categoryName});

  @override
  Widget build(BuildContext context) {
    final categoryColor = getCategoryColor(categoryName);
    final categoryIcon = getCategoryIcon(categoryName);

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
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: categoryColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(categoryIcon, color: categoryColor, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              categoryName,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Consumer<DocumentProvider>(
            builder: (context, provider, _) {
              final categoryDocs = provider.documents
                  .where((d) => d.category == categoryName)
                  .toList();

              if (categoryDocs.isEmpty) {
                return _buildEmptyState(context, categoryColor, categoryIcon);
              }

              // Group by personName
              final Map<String, List<DocumentModel>> groupedByPerson = {};
              for (var doc in categoryDocs) {
                groupedByPerson.putIfAbsent(doc.personName, () => []).add(doc);
              }

              final persons = groupedByPerson.keys.toList()..sort();

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: persons.length,
                itemBuilder: (context, index) {
                  final person = persons[index];
                  final personDocs = groupedByPerson[person]!;

                  // Check expiry status for this person's docs
                  final hasExpired = personDocs.any(
                      (d) => d.expiryDate != null && d.expiryDate!.isBefore(DateTime.now()));
                  final hasExpiringSoon = personDocs.any((d) {
                    if (d.expiryDate == null) return false;
                    final days = d.expiryDate!.difference(DateTime.now()).inDays;
                    return days >= 0 && days <= 30;
                  });

                  Color? alertColor;
                  if (hasExpired) { alertColor = AppColors.expired; }
                  else if (hasExpiringSoon) { alertColor = AppColors.expiringSoon; }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: GlassContainer(
                      padding: EdgeInsets.zero,
                      accentColor: alertColor ?? categoryColor,
                      showGlow: alertColor != null,
                      onTap: () => Navigator.push(
                        context,
                        SlideRoute(
                          page: PersonDocumentsScreen(
                            categoryName: categoryName,
                            personName: person,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            // Avatar
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    categoryColor.withValues(alpha: 0.3),
                                    AppColors.purple.withValues(alpha: 0.3),
                                  ],
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: alertColor ?? categoryColor.withValues(alpha: 0.4),
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  person.isNotEmpty ? person[0].toUpperCase() : '?',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    person,
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.description_rounded,
                                          size: 13, color: AppColors.textMuted),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${personDocs.length} ${personDocs.length == 1 ? 'document' : 'documents'}',
                                        style: GoogleFonts.inter(
                                          color: AppColors.textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (alertColor != null) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: alertColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          hasExpired ? 'Expired' : 'Expiring soon',
                                          style: GoogleFonts.inter(
                                            color: alertColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Arrow
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: AppColors.textMuted,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: (60 * index).ms, duration: 350.ms)
                      .slideX(begin: 0.15, end: 0, curve: Curves.easeOutCubic);
                },
              );
            },
          ),
        ),
      ),
      floatingActionButton: _buildFAB(context),
    );
  }

  Widget _buildEmptyState(BuildContext context, Color color, IconData icon) {
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
            child: Icon(icon, size: 56, color: color),
          ).animate().fadeIn().scale(),
          const SizedBox(height: 24),
          Text(
            'No documents yet',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.2, end: 0),
          const SizedBox(height: 8),
          Text(
            'Tap + to add your first $categoryName document',
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: color.withValues(alpha: 0.15),
              foregroundColor: color,
              side: BorderSide(color: color.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text('Add Document', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            onPressed: () => Navigator.push(
              context,
              FadeScaleRoute(page: DocumentFormScreen(initialCategory: categoryName)),
            ),
          ).animate().fadeIn(delay: 300.ms).scaleXY(begin: 0.9, end: 1.0),
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
          FadeScaleRoute(
            page: DocumentFormScreen(initialCategory: categoryName),
          ),
        ),
        child: const Icon(Icons.add_rounded, size: 28, color: Colors.white),
      ),
    ).animate().fadeIn(delay: 400.ms).scaleXY(begin: 0.8, end: 1.0, curve: Curves.easeOutBack);
  }
}
