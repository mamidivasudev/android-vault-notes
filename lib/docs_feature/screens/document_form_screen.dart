import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../providers/document_provider.dart';
import '../models/document_model.dart';
import '../services/ocr_service.dart';
import '../services/notification_service.dart';
import '../utils/app_theme.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:file_picker/file_picker.dart';

class DocumentFormScreen extends StatefulWidget {
  final DocumentModel? existingDocument;
  final String? initialCategory;
  final String? initialPerson;

  const DocumentFormScreen({
    Key? key,
    this.existingDocument,
    this.initialCategory,
    this.initialPerson,
  }) : super(key: key);

  @override
  _DocumentFormScreenState createState() => _DocumentFormScreenState();
}

class _DocumentFormScreenState extends State<DocumentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _personController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _issueDate;
  DateTime? _expiryDate;
  List<String> _imagePaths = [];
  bool _isScanning = false;
  bool _isSaving = false;

  bool _isCustomCategory = false;
  bool _isCustomPerson = false;

  String? _selectedCategory;
  String? _selectedPerson;

  List<String> _categories = [];
  final List<String> _persons = ['Me', 'Add Custom...'];

  @override
  void initState() {
    super.initState();

    // Load unique persons and categories from provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = Provider.of<DocumentProvider>(context, listen: false);
      final docs = provider.documents;
      final uniquePersons = docs.map((d) => d.personName).toSet().toList();
      
      setState(() {
        _categories = List.from(provider.categories);
        if (!_categories.contains('Add Custom...')) {
          _categories.add('Add Custom...');
        }

        for (var person in uniquePersons) {
          if (!_persons.contains(person)) {
            _persons.insert(_persons.length - 1, person);
          }
        }
        // Re-apply selected values now that list is populated
        _applyInitialValues();
      });
    });
  }

  void _applyInitialValues() {
    if (widget.existingDocument != null) {
      final doc = widget.existingDocument!;
      _titleController.text = doc.title;
      _issueDate = doc.issueDate;
      _expiryDate = doc.expiryDate;
      _imagePaths = List.from(doc.imagePaths);
      _notesController.text = doc.notes;

      // Category
      if (_categories.contains(doc.category)) {
        _selectedCategory = doc.category;
        _categoryController.text = doc.category;
        _isCustomCategory = false;
      } else {
        _selectedCategory = 'Add Custom...';
        _categoryController.text = doc.category;
        _isCustomCategory = true;
      }

      // Person
      if (_persons.contains(doc.personName)) {
        _selectedPerson = doc.personName;
        _personController.text = doc.personName;
        _isCustomPerson = false;
      } else {
        _selectedPerson = 'Add Custom...';
        _personController.text = doc.personName;
        _isCustomPerson = true;
      }
    } else {
      // New document
      if (widget.initialCategory != null) {
        if (_categories.contains(widget.initialCategory)) {
          _selectedCategory = widget.initialCategory;
          _isCustomCategory = false;
        } else {
          _selectedCategory = 'Add Custom...';
          _isCustomCategory = true;
        }
        _categoryController.text = widget.initialCategory!;
      }

      if (widget.initialPerson != null) {
        if (_persons.contains(widget.initialPerson)) {
          _selectedPerson = widget.initialPerson;
          _isCustomPerson = false;
        } else {
          _selectedPerson = 'Add Custom...';
          _isCustomPerson = true;
        }
        _personController.text = widget.initialPerson!;
      } else {
        _selectedPerson = 'Me';
        _personController.text = 'Me';
        _isCustomPerson = false;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _personController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _scanText(ImageSource source) async {
    setState(() => _isScanning = true);
    final text = await OcrService.pickAndRecognize(source);
    setState(() => _isScanning = false);

    if (text != null && text.isNotEmpty) {
      setState(() {
        _titleController.text = text.split('\n').first.trim();
      });
      if (mounted) {
        _showSnack('Scanned: "${_titleController.text}"', AppColors.valid);
      }
    } else if (mounted) {
      _showSnack('Could not extract text', AppColors.expiringSoon);
    }
  }

  Future<String> _persistImage(String tempPath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${appDir.path}/images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    final fileName = '${const Uuid().v4()}${p.extension(tempPath)}';
    final savedImage = await File(tempPath).copy('${imagesDir.path}/$fileName');
    return savedImage.path;
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();

    if (source == ImageSource.gallery) {
      final pickedFiles = await picker.pickMultiImage();
      if (pickedFiles.isNotEmpty) {
        final List<String> persistentPaths = [];
        for (var f in pickedFiles) {
          persistentPaths.add(await _persistImage(f.path));
        }
        setState(() => _imagePaths.addAll(persistentPaths));
      }
    } else {
      // Using Cunning Document Scanner instead of default camera!
      try {
        final List<String>? pictures = await CunningDocumentScanner.getPictures();
        if (pictures != null && pictures.isNotEmpty) {
          final List<String> persistentPaths = [];
          for (var path in pictures) {
            persistentPaths.add(await _persistImage(path));
          }
          setState(() => _imagePaths.addAll(persistentPaths));
        }
      } catch (e) {
        if (mounted) _showSnack('Scanner failed: $e', AppColors.expired);
      }
    }
  }

  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final persistentPath = await _persistImage(path); // _persistImage handles any file extension
        setState(() => _imagePaths.add(persistentPath));
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to pick file: $e', AppColors.expired);
    }
  }

  void _showImageSourceBottomSheet({required bool forOcr}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              forOcr ? 'Scan for OCR' : 'Add Photo',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _sourceButton(
                    icon: Icons.document_scanner_rounded,
                    label: 'Scan',
                    color: AppColors.cyan,
                    onTap: () {
                      Navigator.pop(ctx);
                      forOcr ? _scanText(ImageSource.camera) : _pickImage(ImageSource.camera);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _sourceButton(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    color: AppColors.purple,
                    onTap: () {
                      Navigator.pop(ctx);
                      forOcr ? _scanText(ImageSource.gallery) : _pickImage(ImageSource.gallery);
                    },
                  ),
                ),
                if (!forOcr) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _sourceButton(
                      icon: Icons.picture_as_pdf_rounded,
                      label: 'PDF',
                      color: AppColors.expiringSoon,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickPdf();
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 10),
            Text(
              label,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label, {IconData? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: AppColors.textMuted, size: 20) : null,
      filled: true,
      fillColor: AppColors.surfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.borderSubtle, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.cyan, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.expired, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.expired, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: color.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _getTitleHint() {
    final cat = _categoryController.text;
    if (cat.contains('Insurance')) return 'e.g. LIC Policy, Health Insurance';
    if (cat.contains('Medical')) return 'e.g. Apollo Hospital Report';
    if (cat.contains('Education')) return 'e.g. Degree Certificate';
    if (cat.contains('Financial')) return 'e.g. Bank Statement';
    if (cat.contains('ID') || cat.contains('Passport')) return 'e.g. Aadhar Card, PAN Card';
    if (cat.contains('Vehicle')) return 'e.g. RC Book, Driving Licence';
    return 'e.g. Document Name';
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingDocument != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? 'Edit Document' : 'New Document',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: _buildSaveButton(isEditing),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            // ── Section: Basic Info ──────────────────────────────
            _sectionHeader('Basic Info', Icons.info_outline_rounded),
            const SizedBox(height: 12),

            // Title + OCR scanner
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _titleController,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
                    decoration: _inputDeco(_getTitleHint(), prefixIcon: Icons.title_rounded),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: 'Scan text via OCR',
                  child: GestureDetector(
                    onTap: _isScanning ? null : () => _showImageSourceBottomSheet(forOcr: true),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.purple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.purple.withValues(alpha: 0.4)),
                      ),
                      child: _isScanning
                          ? const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: AppColors.purple,
                                  strokeWidth: 2.5,
                                ),
                              ),
                            )
                          : const Icon(Icons.document_scanner_rounded, color: AppColors.purple, size: 26),
                    ),
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.1, end: 0),

            const SizedBox(height: 16),

            // Person dropdown
            DropdownButtonFormField<String>(
              value: _selectedPerson,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
              dropdownColor: AppColors.surface,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
              decoration: _inputDeco('Belongs To', prefixIcon: Icons.person_rounded),
              items: _persons
                  .map((person) => DropdownMenuItem(
                        value: person,
                        child: Text(person),
                      ))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  _selectedPerson = val;
                  if (val == 'Add Custom...') {
                    _isCustomPerson = true;
                    _personController.clear();
                  } else {
                    _isCustomPerson = false;
                    _personController.text = val ?? '';
                  }
                });
              },
              validator: (v) =>
                  (v == null || v == 'Add Custom...') && _personController.text.trim().isEmpty
                      ? 'Select who this belongs to'
                      : null,
            ).animate().fadeIn(delay: 80.ms).slideY(begin: -0.1, end: 0),

            if (_isCustomPerson) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _personController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
                decoration: _inputDeco('Person Name (e.g. Ravi, Mom)', prefixIcon: Icons.person_add_rounded),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.2, end: 0),
            ],

            const SizedBox(height: 16),

            // Category dropdown
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
              dropdownColor: AppColors.surface,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
              decoration: _inputDeco('Category', prefixIcon: Icons.folder_rounded),
              items: _categories
                  .map((cat) => DropdownMenuItem(
                        value: cat,
                        child: Text(cat),
                      ))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  _selectedCategory = val;
                  if (val == 'Add Custom...') {
                    _isCustomCategory = true;
                    _categoryController.clear();
                  } else {
                    _isCustomCategory = false;
                    _categoryController.text = val ?? '';
                  }
                });
              },
              validator: (v) =>
                  (v == null || v == 'Add Custom...') && _categoryController.text.trim().isEmpty
                      ? 'Select a category'
                      : null,
            ).animate().fadeIn(delay: 120.ms).slideY(begin: -0.1, end: 0),

              if (_isCustomCategory) ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _categoryController,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
                  decoration: _inputDeco('Custom Category Name', prefixIcon: Icons.create_new_folder_rounded),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a category name' : null,
                ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.2, end: 0),
              ],

              const SizedBox(height: 16),

              TextFormField(
                controller: _notesController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
                decoration: _inputDeco('Notes (Optional)', prefixIcon: Icons.notes_rounded),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ).animate().fadeIn(delay: 150.ms).slideY(begin: -0.1, end: 0),

            // ── Section: Dates ───────────────────────────────────
            const SizedBox(height: 28),
            _sectionHeader('Dates', Icons.date_range_rounded),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _dateTile(
                    title: 'Issue Date',
                    date: _issueDate,
                    icon: Icons.event_available_rounded,
                    color: AppColors.cyan,
                    onSelect: (d) => setState(() => _issueDate = d),
                    onClear: () => setState(() => _issueDate = null),
                  ).animate().fadeIn(delay: 180.ms),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dateTile(
                    title: 'Expiry Date',
                    date: _expiryDate,
                    icon: Icons.event_busy_rounded,
                    color: getExpiryColor(_expiryDate),
                    onSelect: (d) => setState(() => _expiryDate = d),
                    onClear: () => setState(() => _expiryDate = null),
                  ).animate().fadeIn(delay: 220.ms),
                ),
              ],
            ),

            // ── Section: Attachments ─────────────────────────────
            const SizedBox(height: 28),
            _sectionHeader('Attachments', Icons.attach_file_rounded),
            const SizedBox(height: 12),

            _buildAttachmentsSection().animate().fadeIn(delay: 260.ms),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.cyan, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.outfit(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Divider(color: AppColors.borderSubtle, thickness: 1),
        ),
      ],
    );
  }

  Widget _dateTile({
    required String title,
    required DateTime? date,
    required IconData icon,
    required Color color,
    required Function(DateTime) onSelect,
    required VoidCallback onClear,
  }) {
    return GestureDetector(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
          builder: (context, child) => Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: AppColors.cyan,
                onPrimary: Colors.black,
                surface: AppColors.surface,
                onSurface: Colors.white,
              ),
              dialogTheme: const DialogThemeData(
                backgroundColor: AppColors.surface,
              ),
            ),
            child: child!,
          ),
        );
        if (d != null) onSelect(d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: date != null ? color.withValues(alpha: 0.4) : AppColors.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(
                    date != null ? DateFormat('dd MMM yy').format(date) : 'Set',
                    style: GoogleFonts.inter(
                      color: date != null ? Colors.white : AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: date != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (date != null)
              GestureDetector(
                onTap: onClear,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.expired.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: AppColors.expired, size: 14),
                ),
              )
            else
              const Icon(Icons.calendar_today_rounded, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Photos',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_imagePaths.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_imagePaths.length}',
                        style: GoogleFonts.inter(color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
              GestureDetector(
                onTap: () => _showImageSourceBottomSheet(forOcr: false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_a_photo_rounded, color: AppColors.cyan, size: 16),
                      const SizedBox(width: 6),
                      Text('Add', style: GoogleFonts.inter(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_imagePaths.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.image_outlined, color: AppColors.textMuted, size: 36),
                    const SizedBox(height: 8),
                    Text('No photos attached', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
                  ],
                ),
              ),
            )
          else ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _imagePaths.length,
                itemBuilder: (context, index) {
                  return Stack(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(right: 10, top: 10),
                        width: 88,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: _imagePaths[index].toLowerCase().endsWith('.pdf') ? AppColors.expired.withValues(alpha: 0.1) : null,
                          image: _imagePaths[index].toLowerCase().endsWith('.pdf')
                              ? null
                              : DecorationImage(
                                  image: FileImage(File(_imagePaths[index])),
                                  fit: BoxFit.cover,
                                ),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: _imagePaths[index].toLowerCase().endsWith('.pdf')
                            ? const Center(child: Icon(Icons.picture_as_pdf_rounded, color: AppColors.expired, size: 36))
                            : null,
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: GestureDetector(
                          onTap: () => setState(() => _imagePaths.removeAt(index)),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: AppColors.expired,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4)],
                            ),
                            child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSaveButton(bool isEditing) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.cyanPurpleGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.35),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: _isSaving ? null : _saveDocument,
        child: _isSaving
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isEditing ? Icons.check_rounded : Icons.save_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    isEditing ? 'Save Changes' : 'Save Document',
                    style: GoogleFonts.outfit(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _saveDocument() async {
    // Validate custom field if custom is selected
    if (_isCustomCategory && _categoryController.text.trim().isEmpty) {
      _showSnack('Please enter a custom category name', AppColors.expiringSoon);
      return;
    }
    if (_isCustomPerson && _personController.text.trim().isEmpty) {
      _showSnack('Please enter a person name', AppColors.expiringSoon);
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final isEditing = widget.existingDocument != null;
      final docId = isEditing ? widget.existingDocument!.id : const Uuid().v4();

      final doc = DocumentModel(
        id: docId,
        title: _titleController.text.trim(),
        category: _categoryController.text.trim(),
        personName: _personController.text.trim(),
        issueDate: _issueDate,
        expiryDate: _expiryDate,
        imagePaths: _imagePaths,
        notes: _notesController.text.trim(),
      );

      final docProvider = Provider.of<DocumentProvider>(context, listen: false);
      if (isEditing) {
        await docProvider.updateDocument(doc);
      } else {
        await docProvider.addDocument(doc);
      }

      if (_expiryDate != null) {
        await NotificationService().scheduleExpiryReminder(docId, doc.title, _expiryDate!);
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error saving document: $e', AppColors.expired);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
