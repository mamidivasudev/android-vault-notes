import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models.dart';
import '../providers.dart';
import '../widgets/category_chip_bar.dart';
import '../widgets/empty_state.dart';
import '../main_helpers.dart';
import '../utils/formula_evaluator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as excel_pkg;
import 'package:path_provider/path_provider.dart';
import 'dart:io';


class TablesView extends ConsumerStatefulWidget {
  const TablesView({super.key});

  @override
  ConsumerState<TablesView> createState() => _TablesViewState();
}

class _TablesViewState extends ConsumerState<TablesView> {
  late PageController _tableCategoryPageController;
  final Map<String, GlobalKey> _tableChipKeys = {};

  @override
  void initState() {
    super.initState();
    _tableCategoryPageController = PageController();
  }

  @override
  void dispose() {
    _tableCategoryPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(tableCategoriesProvider);
    final selectedCat = ref.watch(selectedTableCategoryProvider);
    final allTables = ref.watch(tablesProvider);
    final query = ref.watch(searchQueryProvider).toLowerCase();
    final sortOrder = ref.watch(sortOrderProvider);
    final baseFontSize = ref.watch(fontSizeProvider);
    final showFavs = ref.watch(showFavoritesOnlyProvider);

    final fullCategories = categories;

    final currentSelectedCat = (fullCategories.isNotEmpty && (selectedCat.isEmpty || !fullCategories.contains(selectedCat))) ? fullCategories.first : selectedCat;

    // Sync PageController
    ref.listen(selectedTableCategoryProvider, (prev, next) {
      final index = fullCategories.indexOf(next);
      if (index != -1 && _tableCategoryPageController.hasClients && _tableCategoryPageController.page?.round() != index) {
        _tableCategoryPageController.jumpToPage(index);
      }
      final key = _tableChipKeys[next];
      if (key != null && key.currentContext != null) {
        Scrollable.ensureVisible(key.currentContext!, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut, alignment: 0.5);
      }
    });

    final editingTable = ref.watch(editingTableProvider);

    if (editingTable != null) {
      return TableEditorDialog(
        table: editingTable,
        isNew: !allTables.any((t) => t.id == editingTable.id),
      );
    }

    return Column(
      children: [
        CategoryChipBar(
          categories: fullCategories,
          selectedCategory: currentSelectedCat,
          onSelected: (cat) => ref.read(selectedTableCategoryProvider.notifier).state = cat,
          onAddPressed: () => addTableCategory(context, ref),
          onManagePressed: () => manageTableCategoriesDialog(context, ref),
          chipKeys: _tableChipKeys,
          showFavoritesOnly: showFavs,
          onFavoriteToggle: () => ref.read(showFavoritesOnlyProvider.notifier).state = !showFavs,
          itemCount: allTables.where((t) {
            final matchCat = t.category == currentSelectedCat;
            final matchFav = !showFavs || t.isFavorite;
            if (query.isEmpty) return matchCat && matchFav;
            return matchCat && matchFav && t.title.toLowerCase().contains(query);
          }).length,
        ),
        Expanded(
          child: PageView.builder(
            controller: _tableCategoryPageController,
            physics: const ClampingScrollPhysics(),
            itemCount: fullCategories.length,
            onPageChanged: (index) {
              ref.read(selectedTableCategoryProvider.notifier).state = fullCategories[index];
            },
            itemBuilder: (context, catIndex) {
              final cat = fullCategories[catIndex];

              final filteredTables = allTables.where((t) {
                final matchCat = t.category == cat;
                final matchFav = !showFavs || t.isFavorite;
                if (query.isEmpty) return matchCat && matchFav;
                return matchCat && matchFav && t.title.toLowerCase().contains(query);
              }).toList();

              // Sorting logic
              filteredTables.sort((a, b) {
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

              if (filteredTables.isEmpty) {
                return EmptyState(
                  icon: Icons.table_chart_outlined,
                  title: 'No Tables Found',
                  subtitle: query.isEmpty ? 'No tables in "$cat". Tap + to add one!' : 'No tables match your search.',
                  actionLabel: 'Create Table',
                  onAction: () => _createNewTable(),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filteredTables.length,
                itemBuilder: (context, index) {
                  final table = filteredTables[index];
                  return _TableCard(table: table, baseFontSize: baseFontSize)
                      .animate()
                      .fadeIn(delay: (50 * index).ms, duration: 300.ms)
                      .slideY(begin: 0.1, end: 0, curve: Curves.easeOut);
                },
              );
            },
          ),
        ),
      ],
    );
  }


  void _createNewTable() {
    final selectedCat = ref.read(selectedTableCategoryProvider);
    final initialCat = selectedCat;
    
    ref.read(editingTableProvider.notifier).state = VaultTable(
      title: '',
      columns: [VaultTableCell(text: 'Column 1'), VaultTableCell(text: 'Column 2')],
      rows: [
        [VaultTableCell(text: ''), VaultTableCell(text: '')]
      ],
      category: initialCat,
    );
  }
}

class _TableCard extends ConsumerWidget {
  final VaultTable table;
  final double baseFontSize;
  const _TableCard({required this.table, required this.baseFontSize});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBorderColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final headerColor = isDark ? const Color(0xFF94A3B8) : Colors.grey.shade700;
    final rowTextColor = isDark ? const Color(0xFF94A3B8) : Colors.grey.shade700;
    final separatorColor = isDark ? const Color(0xFF334155) : Colors.grey.shade400;
    final separatorFaintColor = isDark ? const Color(0xFF1E293B) : Colors.grey.shade200;
    final dateBadgeBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final dateBadgeText = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final moreIconColor = isDark ? Colors.white38 : const Color(0xFF94A3B8);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cardBorderColor),
      ),
      child: InkWell(
        onTap: () {
          if (table.isLocked) {
            verifyPasscode(context, ref, onSuccess: () {
              ref.read(editingTableProvider.notifier).state = table;
            });
          } else {
            ref.read(editingTableProvider.notifier).state = table;
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.table_chart, size: 20, color: Color(0xFF1D63D2)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          table.title.isEmpty ? 'Untitled Table' : table.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: baseFontSize,
                            color: titleColor,
                          ),
                        ),
                        if (table.description.isNotEmpty)
                          Text(
                            table.description,
                            style: TextStyle(
                              fontSize: baseFontSize - 1,
                              color: isDark ? const Color(0xFF64748B) : Colors.grey.shade500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (table.isPinned) const Icon(Icons.push_pin, size: 16, color: Color(0xFF1D63D2)),
                  if (table.isFavorite)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.favorite, size: 16, color: Colors.pink),
                    ),
                  if (table.isLocked)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.lock, size: 16, color: Colors.red),
                    ),
                  IconButton(
                    icon: Icon(Icons.more_vert, size: 18, color: moreIconColor),
                    onPressed: () => _showTableOptions(context, ref, table),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(left: 8),
                  ),
                ],
              ),
              if (!table.isLocked && table.rows.isNotEmpty) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row
                      Row(
                        children: [
                          for (int i = 0; i < table.columns.length; i++) ...[
                            SizedBox(
                              width: 80,
                              child: Text(
                                table.columns[i].text.toUpperCase(),
                                maxLines: 2,
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: baseFontSize - 2,
                                  fontWeight: FontWeight.bold,
                                  color: headerColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            if (i < table.columns.length - 1)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  '|',
                                  style: TextStyle(color: separatorColor, fontSize: baseFontSize - 4),
                                ),
                              ),
                          ],
                        ],
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        height: 1,
                        color: separatorColor,
                      ),
                      // Data rows
                      ...table.rows.take(3).map((row) {
                        final grid = table.rows.map((r) => r.map((c) => c.text).toList()).toList();
                        final bgColors = table.rows.map((r) => r.map((c) => c.backgroundColor).toList()).toList();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              for (int i = 0; i < row.length; i++) ...[
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    FormulaEvaluator.evaluate(row[i].text, grid, bgColors: bgColors),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: baseFontSize - 1, color: rowTextColor),
                                  ),
                                ),
                                if (i < row.length - 1)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(
                                      '|',
                                      style: TextStyle(color: separatorFaintColor, fontSize: baseFontSize - 4),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        );
                      }),
                      if (table.rows.length > 3)
                        Text('...', style: TextStyle(color: separatorColor, fontSize: 10)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: dateBadgeBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  DateFormat('dd MMM yyyy').format(table.createdAt),
                  style: TextStyle(fontSize: 10, color: dateBadgeText, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  void _showTableOptions(BuildContext context, WidgetRef ref, VaultTable table) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            ListTile(
              leading: Icon(table.isLocked ? Icons.lock_open : Icons.lock, color: Colors.red),
              title: Text(table.isLocked ? 'Unlock Table' : 'Lock Table'),
              onTap: () {
                Navigator.pop(context);
                if (table.isLocked) {
                  verifyPasscode(context, ref, onSuccess: () {
                    ref.read(tablesProvider.notifier).toggleLock(table.id);
                  });
                } else {
                  ref.read(tablesProvider.notifier).toggleLock(table.id);
                }
              },
            ),
            if (!table.isLocked) ...[
              ListTile(
                leading: Icon(table.isPinned ? Icons.push_pin : Icons.push_pin_outlined, color: const Color(0xFF1D63D2)),
                title: Text(table.isPinned ? 'Unpin' : 'Pin'),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(tablesProvider.notifier).togglePin(table.id);
                },
              ),
              ListTile(
                leading: Icon(table.isFavorite ? Icons.favorite : Icons.favorite_border, color: Colors.pink),
                title: Text(table.isFavorite ? 'Remove from Favorites' : 'Add to Favorites'),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(tablesProvider.notifier).toggleFavorite(table.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(table.isFavorite ? 'Removed from Favorites' : 'Added to Favorites')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy, color: Color(0xFF1D63D2)),
                title: const Text('Copy Table'),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(copiedTableProvider.notifier).state = table;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Table copied. Open a new table and click Paste.')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_copy, color: Color(0xFF1D63D2)),
                title: const Text('Copy Data'),
                onTap: () {
                  Navigator.pop(context);
                  _showCopyFormatDialog(context, table);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Color(0xFF1D63D2)),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(context);
                  final text = _tableToText(table);
                  Share.share(text);
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF1D63D2)),
                title: const Text('Export to PDF'),
                onTap: () {
                  Navigator.pop(context);
                  exportTableToPDF(context, table);
                },
              ),
              ListTile(
                leading: const Icon(Icons.table_view_outlined, color: Color(0xFF1D63D2)),
                title: const Text('Export to Excel (XLSX)'),
                onTap: () {
                  Navigator.pop(context);
                  exportTableToExcel(context, table);
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_rounded, color: Color(0xFF1D63D2)),
                title: const Text('Export Excel (CSV)'),
                onTap: () {
                  Navigator.pop(context);
                  exportTableToCSV(context, table);
                },
              ),

              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Table', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteTable(context, ref, table);
                },
              ),
            ],      // if (!table.isLocked)
          ],        // Column children
            ),      // Column
          ),        // SingleChildScrollView
        ),          // ConstrainedBox
      ),            // SafeArea
    );
  }

  void _confirmDeleteTable(BuildContext context, WidgetRef ref, VaultTable table) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Table'),
        content: const Text('Are you sure you want to delete this table?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(tablesProvider.notifier).deleteTable(table.id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showCopyFormatDialog(BuildContext context, VaultTable table) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Copy Table Data'),
        content: const Text('Select format to copy to clipboard:'),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.text_fields),
                label: const Text('Plain Text (Tabs)'),
                onPressed: () {
                  final text = _tableToText(table);
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied as Plain Text')),
                  );
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.list_alt_rounded),
                label: const Text('CSV (Comma-separated)'),
                onPressed: () {
                  final text = _tableToCSV(table);
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied as CSV')),
                  );
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.code),
                label: const Text('Markdown Table'),
                onPressed: () {
                  final text = _tableToMarkdown(table);
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied as Markdown')),
                  );
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.html),
                label: const Text('HTML Table'),
                onPressed: () {
                  final text = _tableToHTML(table);
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied as HTML')),
                  );
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _tableToText(VaultTable table) {
    StringBuffer sb = StringBuffer();
    sb.writeln(table.title.isEmpty ? 'Untitled Table' : table.title);
    sb.writeln();
    
    // Headers
    sb.writeln(table.columns.map((c) => c.text).join('\t'));
    
    // Rows
    final grid = table.rows.map((r) => r.map((c) => c.text).toList()).toList();
    final bgColors = table.rows.map((r) => r.map((c) => c.backgroundColor).toList()).toList();
    for (var row in table.rows) {
      sb.writeln(row.map((cell) => FormulaEvaluator.evaluate(cell.text, grid, bgColors: bgColors)).join('\t'));
    }
    
    return sb.toString();
  }

  String _tableToCSV(VaultTable table) {
    StringBuffer sb = StringBuffer();
    String escapeCsv(String field) {
      if (field.contains(',') || field.contains('"') || field.contains('\n') || field.contains('\r')) {
        return '"${field.replaceAll('"', '""')}"';
      }
      return field;
    }
    sb.writeln(table.columns.map((c) => escapeCsv(c.text)).join(','));
    final grid = table.rows.map((r) => r.map((c) => c.text).toList()).toList();
    final bgColors = table.rows.map((r) => r.map((c) => c.backgroundColor).toList()).toList();
    for (var row in table.rows) {
      sb.writeln(row.map((cell) => escapeCsv(FormulaEvaluator.evaluate(cell.text, grid, bgColors: bgColors))).join(','));
    }
    return sb.toString();
  }

  String _tableToMarkdown(VaultTable table) {
    StringBuffer sb = StringBuffer();
    sb.writeln('| ${table.columns.map((c) => c.text).join(' | ')} |');
    sb.writeln('| ${table.columns.map((_) => '---').join(' | ')} |');
    final grid = table.rows.map((r) => r.map((c) => c.text).toList()).toList();
    final bgColors = table.rows.map((r) => r.map((c) => c.backgroundColor).toList()).toList();
    for (var row in table.rows) {
      sb.writeln('| ${row.map((cell) => FormulaEvaluator.evaluate(cell.text, grid, bgColors: bgColors)).join(' | ')} |');
    }
    return sb.toString();
  }

  String _tableToHTML(VaultTable table) {
    StringBuffer sb = StringBuffer();
    sb.writeln('<table>');
    sb.writeln('  <thead>');
    sb.writeln('    <tr>');
    for (var c in table.columns) {
      sb.writeln('      <th>${c.text}</th>');
    }
    sb.writeln('    </tr>');
    sb.writeln('  </thead>');
    sb.writeln('  <tbody>');
    final grid = table.rows.map((r) => r.map((c) => c.text).toList()).toList();
    final bgColors = table.rows.map((r) => r.map((c) => c.backgroundColor).toList()).toList();
    for (var row in table.rows) {
      sb.writeln('    <tr>');
      for (var cell in row) {
        sb.writeln('      <td>${FormulaEvaluator.evaluate(cell.text, grid, bgColors: bgColors)}</td>');
      }
      sb.writeln('    </tr>');
    }
    sb.writeln('  </tbody>');
    sb.writeln('</table>');
    return sb.toString();
  }

  Future<void> exportTableToExcel(BuildContext context, VaultTable table) async {
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['Sheet1'];
      
      for (int colIndex = 0; colIndex < table.columns.length; colIndex++) {
        final cellIndex = excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: 0);
        sheet.cell(cellIndex).value = excel_pkg.TextCellValue(table.columns[colIndex].text);
      }
      
      final grid = table.rows.map((r) => r.map((c) => c.text).toList()).toList();
      final bgColors = table.rows.map((r) => r.map((c) => c.backgroundColor).toList()).toList();
      for (int rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
        final row = table.rows[rowIndex];
        for (int colIndex = 0; colIndex < row.length; colIndex++) {
          final cellValue = FormulaEvaluator.evaluate(row[colIndex].text, grid, bgColors: bgColors);
          final cellIndex = excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: rowIndex + 1);
          sheet.cell(cellIndex).value = excel_pkg.TextCellValue(cellValue);
        }
      }
      
      final fileBytes = excel.save();
      if (fileBytes == null) throw Exception("Failed to generate excel file");
      
      final tempDir = await getTemporaryDirectory();
      final fileName = '${table.title.isEmpty ? "table" : table.title.toLowerCase().replaceAll(' ', '_')}.xlsx';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(fileBytes);
      
      await Share.shareXFiles([XFile(file.path)], subject: 'Excel Export - ${table.title}');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excel export failed: $e')));
    }
  }

  Future<void> exportTableToPDF(BuildContext context, VaultTable table) async {
    try {
      final pdf = pw.Document();
      
      final headers = table.columns.map((col) => col.text).toList();
      
      final grid = table.rows.map((r) => r.map((c) => c.text).toList()).toList();
      final bgColors = table.rows.map((r) => r.map((c) => c.backgroundColor).toList()).toList();
      final List<List<String>> data = table.rows.map((row) {
        return row.map((cell) => FormulaEvaluator.evaluate(cell.text, grid, bgColors: bgColors)).toList();
      }).toList();
      
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Text(
                  table.title.isEmpty ? 'Untitled Table' : table.title,
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
              ),
              if (table.description.isNotEmpty) ...[
                pw.Paragraph(text: table.description),
                pw.SizedBox(height: 10),
              ],
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: data,
                border: pw.TableBorder.all(color: PdfColors.grey, width: 0.5),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellAlignment: pw.Alignment.centerLeft,
              ),
            ];
          },
        ),
      );
      
      final tempDir = await getTemporaryDirectory();
      final fileName = '${table.title.isEmpty ? "table" : table.title.toLowerCase().replaceAll(' ', '_')}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());
      
      await Share.shareXFiles([XFile(file.path)], subject: 'PDF Export - ${table.title}');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
    }
  }
}


class TableEditorDialog extends ConsumerStatefulWidget {
  final VaultTable table;
  final bool isNew;
  const TableEditorDialog({super.key, required this.table, this.isNew = false});

  @override
  ConsumerState<TableEditorDialog> createState() => _TableEditorDialogState();
}

class _TableEditorDialogState extends ConsumerState<TableEditorDialog> {
  static const String _paidCellLabel = 'PAID';
  static const String _paidCellBgHex = '#FFE4EC';

  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late List<TextEditingController> _columnControllers;
  late List<double> _columnWidths;
  late List<String> _headerAlignments;
  late List<bool> _headerIsBold;
  late List<String?> _headerBgColors;
  late List<String?> _headerTextColors;
  late List<List<TextEditingController>> _cellControllers;
  late List<List<String>> _alignments;
  late List<List<bool>> _isBold;
  late List<List<String?>> _bgColors;
  late List<List<String?>> _textColors;
  late List<List<bool>> _isPaid;
  late String _category;
  int? _focusedRow;
  int? _focusedCol;
  final Set<String> _selectedCells = {};
  _CellFormat? _copiedFormat;
  bool _isFormatPainterActive = false;

  final List<_TableSnapshot> _undoStack = [];
  final List<_TableSnapshot> _redoStack = [];
  static const int _maxHistory = 10;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.table.title);
    _descriptionController = TextEditingController(text: widget.table.description);
    _columnControllers = widget.table.columns.map((c) => TextEditingController(text: c.text)).toList();
    _columnWidths = List<double>.from(widget.table.columnWidths);
    _headerAlignments = widget.table.columns.map((c) => c.alignment).toList();
    _headerIsBold = widget.table.columns.map((c) => c.isBold).toList();
    _headerBgColors = widget.table.columns.map((c) => c.backgroundColor).toList();
    _headerTextColors = widget.table.columns.map((c) => c.textColor).toList();
    
    _cellControllers = widget.table.rows.map((row) {
      return row.map((cell) => TextEditingController(text: cell.text)).toList();
    }).toList();

    _alignments = widget.table.rows.map((row) => row.map((cell) => cell.alignment).toList()).toList();
    _isBold = widget.table.rows.map((row) => row.map((cell) => cell.isBold).toList()).toList();
    _bgColors = widget.table.rows.map((row) => row.map((cell) => cell.backgroundColor).toList()).toList();
    _textColors = widget.table.rows.map((row) => row.map((cell) => cell.textColor).toList()).toList();
    _isPaid = widget.table.rows.map((row) => row.map((cell) => cell.isPaid).toList()).toList();
    _category = widget.table.category;

    if (_columnWidths.length < _columnControllers.length) {
      _columnWidths.addAll(List.generate(_columnControllers.length - _columnWidths.length, (_) => 120.0));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    for (var controller in _columnControllers) { controller.dispose(); }
    for (var row in _cellControllers) { for (var controller in row) { controller.dispose(); } }
    super.dispose();
  }

  String _getColLetter(int index) {
    return String.fromCharCode('A'.codeUnitAt(0) + index);
  }

  String _cellKey(int row, int col) => '$row,$col';

  bool _isCellSelected(int row, int col) => _selectedCells.contains(_cellKey(row, col));

  void _selectOnlyCell(int row, int col) {
    _selectedCells
      ..clear()
      ..add(_cellKey(row, col));
    _focusedRow = row;
    _focusedCol = col;
  }

  void _toggleCellSelection(int row, int col) {
    final key = _cellKey(row, col);
    if (_selectedCells.contains(key)) {
      _selectedCells.remove(key);
      if (_focusedRow == row && _focusedCol == col) {
        if (_selectedCells.isEmpty) {
          _focusedRow = null;
          _focusedCol = null;
        } else {
          final first = _selectedCells.first.split(',');
          _focusedRow = int.parse(first[0]);
          _focusedCol = int.parse(first[1]);
        }
      }
    } else {
      _selectedCells.add(key);
      _focusedRow = row;
      _focusedCol = col;
    }
  }

  bool get _hasDataCellSelection =>
      _selectedCells.isNotEmpty ||
      (_focusedRow != null && _focusedCol != null && _focusedRow! >= 0);

  List<(int row, int col)> _selectedDataCellsList() {
    if (_selectedCells.isNotEmpty) {
      return _selectedCells.map((key) {
        final parts = key.split(',');
        return (int.parse(parts[0]), int.parse(parts[1]));
      }).where((cell) => cell.$1 >= 0).toList();
    }
    if (_focusedRow != null && _focusedCol != null && _focusedRow! >= 0) {
      return [(_focusedRow!, _focusedCol!)];
    }
    return [];
  }

  List<List<String>> _getCurrentGrid() {
    return _cellControllers.map((row) => row.map((c) => c.text).toList()).toList();
  }

  void _saveToHistory() {
    final snapshot = _TableSnapshot(
      columnTitles: _columnControllers.map((c) => c.text).toList(),
      columnWidths: List<double>.from(_columnWidths),
      headerAlignments: List<String>.from(_headerAlignments),
      headerIsBold: List<bool>.from(_headerIsBold),
      headerBgColors: List<String?>.from(_headerBgColors),
      headerTextColors: List<String?>.from(_headerTextColors),
      cellTexts: _cellControllers.map((row) => row.map((c) => c.text).toList()).toList(),
      alignments: _alignments.map((row) => List<String>.from(row)).toList(),
      isBold: _isBold.map((row) => List<bool>.from(row)).toList(),
      bgColors: _bgColors.map((row) => List<String?>.from(row)).toList(),
      textColors: _textColors.map((row) => List<String?>.from(row)).toList(),
      isPaid: _isPaid.map((row) => List<bool>.from(row)).toList(),
    );
    _undoStack.add(snapshot);
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _restoreFromSnapshot(_TableSnapshot snapshot) {
    setState(() {
      while (_columnControllers.length > snapshot.columnTitles.length) {
        _columnControllers.removeLast().dispose();
      }
      for (int i = 0; i < snapshot.columnTitles.length; i++) {
        if (i < _columnControllers.length) {
          _columnControllers[i].text = snapshot.columnTitles[i];
        } else {
          _columnControllers.add(TextEditingController(text: snapshot.columnTitles[i]));
        }
      }
      _columnWidths = List<double>.from(snapshot.columnWidths);
      _headerAlignments = List<String>.from(snapshot.headerAlignments);
      _headerIsBold = List<bool>.from(snapshot.headerIsBold);
      _headerBgColors = List<String?>.from(snapshot.headerBgColors);
      _headerTextColors = List<String?>.from(snapshot.headerTextColors);
      while (_cellControllers.length > snapshot.cellTexts.length) {
        for (var c in _cellControllers.removeLast()) {
          c.dispose();
        }
      }
      for (int i = 0; i < snapshot.cellTexts.length; i++) {
        if (i < _cellControllers.length) {
          while (_cellControllers[i].length > snapshot.cellTexts[i].length) {
            _cellControllers[i].removeLast().dispose();
          }
          for (int j = 0; j < snapshot.cellTexts[i].length; j++) {
            if (j < _cellControllers[i].length) {
              _cellControllers[i][j].text = snapshot.cellTexts[i][j];
            } else {
              _cellControllers[i].add(TextEditingController(text: snapshot.cellTexts[i][j]));
            }
          }
        } else {
          _cellControllers.add(snapshot.cellTexts[i].map((text) => TextEditingController(text: text)).toList());
        }
      }
      _alignments = snapshot.alignments.map((row) => List<String>.from(row)).toList();
      _isBold = snapshot.isBold.map((row) => List<bool>.from(row)).toList();
      _bgColors = snapshot.bgColors.map((row) => List<String?>.from(row)).toList();
      _textColors = snapshot.textColors.map((row) => List<String?>.from(row)).toList();
      _isPaid = snapshot.isPaid.map((row) => List<bool>.from(row)).toList();
      _focusedRow = null;
      _focusedCol = null;
      _selectedCells.clear();
    });
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snapshotCurrent());
    _restoreFromSnapshot(_undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snapshotCurrent());
    _restoreFromSnapshot(_redoStack.removeLast());
  }

  _TableSnapshot _snapshotCurrent() => _TableSnapshot(
    columnTitles: _columnControllers.map((c) => c.text).toList(),
    columnWidths: List<double>.from(_columnWidths),
    headerAlignments: List<String>.from(_headerAlignments),
    headerIsBold: List<bool>.from(_headerIsBold),
    headerBgColors: List<String?>.from(_headerBgColors),
    headerTextColors: List<String?>.from(_headerTextColors),
    cellTexts: _cellControllers.map((row) => row.map((c) => c.text).toList()).toList(),
    alignments: _alignments.map((row) => List<String>.from(row)).toList(),
    isBold: _isBold.map((row) => List<bool>.from(row)).toList(),
    bgColors: _bgColors.map((row) => List<String?>.from(row)).toList(),
    textColors: _textColors.map((row) => List<String?>.from(row)).toList(),
    isPaid: _isPaid.map((row) => List<bool>.from(row)).toList(),
  );

  void _markCellPaid() {
    final targets = _selectedDataCellsList();
    if (targets.isEmpty) return;
    _saveToHistory();
    setState(() {
      for (final (r, c) in targets) {
        _isPaid[r][c] = true;
        _cellControllers[r][c].text = _paidCellLabel;
        _bgColors[r][c] = _paidCellBgHex;
        _textColors[r][c] = null;
        _alignments[r][c] = 'center';
        _isBold[r][c] = true;
      }
    });
  }

  void _addRow() {
    _saveToHistory();
    setState(() {
      _cellControllers.add(List.generate(_columnControllers.length, (_) => TextEditingController()));
      _alignments.add(List.generate(_columnControllers.length, (_) => 'left'));
      _isBold.add(List.generate(_columnControllers.length, (_) => false));
      _bgColors.add(List.generate(_columnControllers.length, (_) => null));
      _textColors.add(List.generate(_columnControllers.length, (_) => null));
      _isPaid.add(List.generate(_columnControllers.length, (_) => false));
    });
  }

  void _addColumn() {
    _saveToHistory();
    setState(() {
      _columnControllers.add(TextEditingController(text: 'New Column'));
      _columnWidths.add(120.0);
      _headerAlignments.add('left');
      _headerIsBold.add(true);
      _headerBgColors.add(null);
      _headerTextColors.add(null);
      for (var row in _cellControllers) {
        row.add(TextEditingController());
      }
      for (var row in _alignments) {
        row.add('left');
      }
      for (var row in _isBold) {
        row.add(false);
      }
      for (var row in _bgColors) {
        row.add(null);
      }
      for (var row in _textColors) {
        row.add(null);
      }
      for (var row in _isPaid) {
        row.add(false);
      }
    });
  }

  void _deleteRow(int index) {
    _saveToHistory();
    setState(() {
      _cellControllers.removeAt(index);
      _alignments.removeAt(index);
      _isBold.removeAt(index);
      _bgColors.removeAt(index);
      _textColors.removeAt(index);
      _isPaid.removeAt(index);
      _focusedRow = null;
    });
  }

  void _deleteColumn(int index) {
    _saveToHistory();
    setState(() {
      _columnControllers.removeAt(index);
      _columnWidths.removeAt(index);
      _headerAlignments.removeAt(index);
      _headerIsBold.removeAt(index);
      _headerBgColors.removeAt(index);
      _headerTextColors.removeAt(index);
      for (var row in _cellControllers) {
        row.removeAt(index);
      }
      for (var row in _alignments) {
        row.removeAt(index);
      }
      for (var row in _isBold) {
        row.removeAt(index);
      }
      for (var row in _bgColors) {
        row.removeAt(index);
      }
      for (var row in _textColors) {
        row.removeAt(index);
      }
      for (var row in _isPaid) {
        row.removeAt(index);
      }
      _focusedCol = null;
    });
  }

  void _clearData() {
    _saveToHistory();
    setState(() {
      for (int r = 0; r < _cellControllers.length; r++) {
        for (int c = 0; c < _cellControllers[r].length; c++) {
          _cellControllers[r][c].clear();
          _isPaid[r][c] = false;
          _bgColors[r][c] = null;
          _textColors[r][c] = null;
        }
      }
    });
  }

  void _pasteTable(VaultTable copied) {
    _saveToHistory();
    setState(() {
      _titleController.text = '${copied.title} (Copy)';
      
      // Dispose old controllers
      for (var c in _columnControllers) {
        c.dispose();
      }
      for (var row in _cellControllers) { for (var c in row) {
        c.dispose();
      } }

      _columnControllers = copied.columns.map((c) => TextEditingController(text: c.text)).toList();
      _columnWidths = List<double>.from(copied.columnWidths);
      _headerAlignments = copied.columns.map((c) => c.alignment).toList();
      _headerIsBold = copied.columns.map((c) => c.isBold).toList();
      _headerBgColors = copied.columns.map((c) => c.backgroundColor).toList();
      _headerTextColors = copied.columns.map((c) => c.textColor).toList();
      
      _cellControllers = copied.rows.map((row) {
        return row.map((cell) => TextEditingController(text: cell.text)).toList();
      }).toList();

      _alignments = copied.rows.map((row) => row.map((cell) => cell.alignment).toList()).toList();
      _isBold = copied.rows.map((row) => row.map((cell) => cell.isBold).toList()).toList();
      _bgColors = copied.rows.map((row) => row.map((cell) => cell.backgroundColor).toList()).toList();
      _textColors = copied.rows.map((row) => row.map((cell) => cell.textColor).toList()).toList();
      _isPaid = copied.rows.map((row) => row.map((cell) => cell.isPaid).toList()).toList();
      _focusedRow = null;
      _focusedCol = null;
    });
  }

  void _handleSave() {
    final List<VaultTableCell> columns = _columnControllers.asMap().entries.map((entry) {
      final idx = entry.key;
      return VaultTableCell(
        text: entry.value.text,
        alignment: _headerAlignments[idx],
        isBold: _headerIsBold[idx],
        backgroundColor: _headerBgColors[idx],
        textColor: _headerTextColors[idx],
      );
    }).toList();

    final List<List<VaultTableCell>> rows = _cellControllers.asMap().entries.map((rowEntry) {
      final rIdx = rowEntry.key;
      return rowEntry.value.asMap().entries.map((cellEntry) {
        final cIdx = cellEntry.key;
        return VaultTableCell(
          text: cellEntry.value.text,
          alignment: _alignments[rIdx][cIdx],
          isBold: _isBold[rIdx][cIdx],
          backgroundColor: _bgColors[rIdx][cIdx],
          textColor: _textColors[rIdx][cIdx],
          isPaid: _isPaid[rIdx][cIdx],
        );
      }).toList();
    }).toList();

    final updatedTable = widget.table.copyWith(
      title: _titleController.text,
      description: _descriptionController.text,
      columns: columns,
      rows: rows,
      columnWidths: _columnWidths,
      category: _category,
    );

    if (widget.isNew) {
      ref.read(tablesProvider.notifier).addTable(updatedTable);
    } else {
      ref.read(tablesProvider.notifier).updateTable(updatedTable);
    }
    ref.read(editingTableProvider.notifier).state = null;
  }


  @override
  Widget build(BuildContext context) {
    final baseFontSize = ref.watch(fontSizeProvider);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        FocusScope.of(context).unfocus();
        setState(() {
          _focusedRow = null;
          _focusedCol = null;
          _selectedCells.clear();
        });
      },
      child: SafeArea(
        child: Column(
          children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(onPressed: () => ref.read(editingTableProvider.notifier).state = null, icon: const Icon(Icons.arrow_back)),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _titleController, decoration: const InputDecoration(hintText: 'Table Title', border: InputBorder.none), style: TextStyle(fontWeight: FontWeight.bold, fontSize: baseFontSize + 4))),
                  IconButton(icon: Icon(Icons.undo, color: _undoStack.isEmpty ? Colors.grey : Colors.black), onPressed: _undoStack.isEmpty ? null : _undo),
                  IconButton(icon: Icon(Icons.redo, color: _redoStack.isEmpty ? Colors.grey : Colors.black), onPressed: _redoStack.isEmpty ? null : _redo),
                  IconButton(icon: const Icon(Icons.save, color: Color(0xFF1D63D2)), onPressed: _handleSave),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 48.0, bottom: 8.0),
                child: TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(hintText: 'Add a description...', border: InputBorder.none, isDense: true),
                  style: TextStyle(fontSize: baseFontSize - 1, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
        if (_focusedRow != null && _focusedCol != null) ...[
          if (_selectedCells.length > 1)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: const Color(0xFFEFF6FF),
              child: Text(
                '${_selectedCells.length} cells selected · long-press to add/remove',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade800),
              ),
            ),
          _buildFormattingToolbar(),
        ],
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                      child: Column(children: [_buildHeaderRow(baseFontSize), ..._cellControllers.asMap().entries.map((entry) => _buildDataRow(entry.key, entry.value, baseFontSize))]),
                    ),
                    const SizedBox(height: 20),
                    Row(children: [
                      OutlinedButton.icon(onPressed: _addRow, icon: const Icon(Icons.add), label: const Text('Add Row')),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(onPressed: _addColumn, icon: const Icon(Icons.view_column), label: const Text('Add Column')),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      TextButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Clear Table Data'),
                              content: const Text('Are you sure you want to clear all data in this table? The structure will remain.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                TextButton(
                                  onPressed: () {
                                    _clearData();
                                    Navigator.pop(context);
                                  },
                                  child: const Text('Clear', style: TextStyle(color: Colors.orange)),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.layers_clear, color: Colors.orange),
                        label: const Text('Clear Data', style: TextStyle(color: Colors.orange)),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: _hasDataCellSelection ? _markCellPaid : null,
                        icon: Icon(
                          Icons.check_circle_outline,
                          color: _hasDataCellSelection ? Colors.pink.shade400 : Colors.grey.shade400,
                        ),
                        label: Text(
                          'Mark Paid',
                          style: TextStyle(
                            color: _hasDataCellSelection ? Colors.pink.shade400 : Colors.grey.shade400,
                          ),
                        ),
                      ),
                      if (widget.isNew) ...[
                        const SizedBox(width: 12),
                        Consumer(builder: (context, ref, _) {
                          final copiedTable = ref.watch(copiedTableProvider);
                          if (copiedTable == null) return const SizedBox.shrink();
                          return TextButton.icon(
                            onPressed: () => _pasteTable(copiedTable),
                            icon: const Icon(Icons.paste, color: Colors.green),
                            label: const Text('Paste Copied Table', style: TextStyle(color: Colors.green)),
                          );
                        }),
                      ],
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    )));
  }

  Widget _buildHeaderRow(double baseFontSize) {
    return Container(
      color: Colors.grey.shade100,
      child: Row(
        children: _columnControllers.asMap().entries.map((entry) {
          final idx = entry.key;
          return Row(
            children: [
              Container(
                width: _columnWidths[idx],
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: _headerBgColors[idx] != null ? Color(int.parse(_headerBgColors[idx]!.replaceFirst('#', '0xFF'))) : null,
                child: TextField(
                  controller: entry.value,
                  textAlign: _headerAlignments[idx] == 'center' ? TextAlign.center : (_headerAlignments[idx] == 'right' ? TextAlign.right : TextAlign.left),
                  onTap: () {
                    if (_isFormatPainterActive && _copiedFormat != null) {
                      _saveToHistory();
                      setState(() {
                        _headerAlignments[idx] = _copiedFormat!.alignment;
                        _headerIsBold[idx] = _copiedFormat!.isBold;
                        _headerBgColors[idx] = _copiedFormat!.backgroundColor;
                        _headerTextColors[idx] = _copiedFormat!.textColor;
                        _isFormatPainterActive = false;
                        _selectOnlyCell(-1, idx);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Header format applied'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    } else {
                      setState(() => _selectOnlyCell(-1, idx));
                    }
                  },
                  style: TextStyle(
                    fontWeight: _headerIsBold[idx] ? FontWeight.bold : FontWeight.normal,
                    fontSize: baseFontSize - 1,
                    color: _headerTextColors[idx] != null ? Color(int.parse(_headerTextColors[idx]!.replaceFirst('#', '0xFF'))) : null,
                  ),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _columnWidths[idx] = (_columnWidths[idx] + details.delta.dx).clamp(50.0, 500.0);
                  });
                },
                child: Container(
                  width: 30,
                  height: 40,
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                      width: 2,
                      height: 24,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDataRow(int rowIndex, List<TextEditingController> controllers, double baseFontSize) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: controllers.asMap().entries.map((entry) {
          final idx = entry.key;
          final controller = entry.value;
          final alignmentStr = _alignments[rowIndex][idx];
          final cellIsBold = _isBold[rowIndex][idx];
          final cellBgColorHex = _bgColors[rowIndex][idx];
          final cellTextColorHex = _textColors[rowIndex][idx];
          final cellIsPaid = _isPaid[rowIndex][idx];

          TextAlign textAlign = TextAlign.left;
          if (alignmentStr == 'center') textAlign = TextAlign.center;
          if (alignmentStr == 'right') textAlign = TextAlign.right;

          Color? cellBgColor;
          if (cellIsPaid) {
            cellBgColor = const Color(0xFFFFE4EC);
          } else if (cellBgColorHex != null) {
            cellBgColor = Color(int.parse(cellBgColorHex.replaceFirst('#', '0xFF')));
          }

          Color? cellTextColor;
          if (cellTextColorHex != null) {
            cellTextColor = Color(int.parse(cellTextColorHex.replaceFirst('#', '0xFF')));
          }

          final isEditingFormula = (_focusedRow != null && _focusedCol != null && _focusedRow! >= 0 && _cellControllers[_focusedRow!][_focusedCol!].text.startsWith('='));
          final isSelected = _isCellSelected(rowIndex, idx);

          return Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: _columnWidths[idx],
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: cellBgColor,
                      border: isSelected
                          ? Border.all(color: const Color(0xFF1D63D2), width: 2)
                          : null,
                    ),
                    child: (_focusedRow == rowIndex && _focusedCol == idx)
                    ? TextField(
                      controller: controller,
                      textAlign: textAlign,
                      autofocus: true,
                      keyboardType: _isNumeric(controller.text.replaceAll(',', '')) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                      onChanged: (value) {
                        if (cellIsPaid && value.trim().toUpperCase() != _paidCellLabel) {
                          _isPaid[rowIndex][idx] = false;
                        }
                        setState(() {});
                      },
                      style: TextStyle(
                        fontSize: baseFontSize,
                        fontWeight: cellIsBold ? FontWeight.bold : FontWeight.normal,
                        color: cellTextColor ?? (cellIsPaid ? Colors.pink.shade700 : null),
                      ),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                    )
                    : InkWell(
                        onTap: () {
                          if (_isFormatPainterActive && _copiedFormat != null) {
                            _saveToHistory();
                            setState(() {
                              _alignments[rowIndex][idx] = _copiedFormat!.alignment;
                              _isBold[rowIndex][idx] = _copiedFormat!.isBold;
                              _bgColors[rowIndex][idx] = _copiedFormat!.backgroundColor;
                              _textColors[rowIndex][idx] = _copiedFormat!.textColor;
                              _isFormatPainterActive = false;
                              _selectOnlyCell(rowIndex, idx);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Cell format applied'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          } else {
                            setState(() => _selectOnlyCell(rowIndex, idx));
                          }
                        },
                        onLongPress: () {
                          setState(() => _toggleCellSelection(rowIndex, idx));
                        },
                        child: Container(
                          height: 40,
                          alignment: alignmentStr == 'center' ? Alignment.center : (alignmentStr == 'right' ? Alignment.centerRight : Alignment.centerLeft),
                          child: Text(
                            cellIsPaid
                                ? _paidCellLabel
                                : FormulaEvaluator.evaluate(controller.text, _getCurrentGrid(), bgColors: _bgColors),
                            style: TextStyle(
                              fontSize: baseFontSize,
                              fontWeight: cellIsBold ? FontWeight.bold : FontWeight.normal,
                              color: cellTextColor ??
                                  (cellIsPaid
                                      ? Colors.pink.shade700
                                      : (controller.text.startsWith('=') ? Colors.blue.shade700 : null)),
                            ),
                          ),
                        ),
                      ),
                  ),
                  if (isEditingFormula)
                    Positioned(
                      top: 0,
                      left: 2,
                      child: Text(
                        '${_getColLetter(idx)}${rowIndex + 1}',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade400,
                          backgroundColor: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ),
                ],
              ),
              // Vertical grid line matching header divider
              Container(
                width: 30,
                height: 40,
                alignment: Alignment.center,
                child: Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey.shade300,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFormattingToolbar() {
    final r = _focusedRow!;
    final c = _focusedCol!;
    final isHeader = r == -1;
    final controller = isHeader ? _columnControllers[c] : _cellControllers[r][c];
    
    final alignment = isHeader ? _headerAlignments[c] : _alignments[r][c];
    final isBold = isHeader ? _headerIsBold[c] : _isBold[r][c];

    return Column(
      children: [
        if (!isHeader && controller.text.startsWith('='))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blue.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('fx', style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        autofocus: false,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          hintText: 'Enter formula (e.g., =SUM(A1:A5))',
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.blue.shade200),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.blue.shade200),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text('Formulas: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 12)),
                      ...['COUNT(A1:A5)', 'COUNTIF(A1:A5, "paid")', 'COUNTIFCOLOR(A1:A5, "paid")', 'SUM(A1:A5)', 'AVG(A1:A5)'].map((f) => 
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () {
                              final base = '${f.split('(')[0]}(';
                              setState(() {
                                controller.text = '=$base';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.blue.shade200),
                                borderRadius: BorderRadius.circular(4),
                                color: Colors.white,
                              ),
                              child: Text(f, style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w500)),
                            ),
                          ),
                        )
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildToolbarButton(
              icon: Icons.format_align_left,
              label: 'Left',
              color: alignment == 'left' ? Colors.blue : null,
              activeColor: alignment == 'left' ? Colors.blue : null,
              onPressed: () {
                _saveToHistory();
                setState(() {
                  if (isHeader) {
                    _headerAlignments[c] = 'left';
                  } else {
                    _alignments[r][c] = 'left';
                  }
                });
              },
            ),
            _buildToolbarButton(
              icon: Icons.format_align_center,
              label: 'Center',
              color: alignment == 'center' ? Colors.blue : null,
              activeColor: alignment == 'center' ? Colors.blue : null,
              onPressed: () {
                _saveToHistory();
                setState(() {
                  if (isHeader) {
                    _headerAlignments[c] = 'center';
                  } else {
                    _alignments[r][c] = 'center';
                  }
                });
              },
            ),
            _buildToolbarButton(
              icon: Icons.format_align_right,
              label: 'Right',
              color: alignment == 'right' ? Colors.blue : null,
              activeColor: alignment == 'right' ? Colors.blue : null,
              onPressed: () {
                _saveToHistory();
                setState(() {
                  if (isHeader) {
                    _headerAlignments[c] = 'right';
                  } else {
                    _alignments[r][c] = 'right';
                  }
                });
              },
            ),
            const VerticalDivider(),
            _buildToolbarButton(
              icon: Icons.format_bold,
              label: 'Bold',
              color: isBold ? Colors.blue : null,
              activeColor: isBold ? Colors.blue : null,
              onPressed: () {
                _saveToHistory();
                setState(() {
                  if (isHeader) {
                    _headerIsBold[c] = !_headerIsBold[c];
                  } else {
                    _isBold[r][c] = !isBold;
                  }
                });
              },
            ),
            _buildToolbarButton(
              icon: Icons.text_fields,
              label: 'Caps',
              onPressed: () {
                _saveToHistory();
                final controller = isHeader ? _columnControllers[c] : _cellControllers[r][c];
                controller.text = controller.text.toUpperCase();
              },
            ),
            _buildToolbarButton(
              icon: Icons.format_paint,
              label: 'Format Copy',
              color: _isFormatPainterActive ? Colors.blue : null,
              activeColor: _isFormatPainterActive ? Colors.blue : null,
              onPressed: () {
                setState(() {
                  if (_isFormatPainterActive) {
                    _isFormatPainterActive = false;
                  } else {
                    _copiedFormat = _CellFormat(
                      alignment: isHeader ? _headerAlignments[c] : _alignments[r][c],
                      isBold: isHeader ? _headerIsBold[c] : _isBold[r][c],
                      backgroundColor: isHeader ? _headerBgColors[c] : _bgColors[r][c],
                      textColor: isHeader ? _headerTextColors[c] : _textColors[r][c],
                    );
                    _isFormatPainterActive = true;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Format Painter active: Tap another cell to apply format'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                });
              },
            ),
            const VerticalDivider(),
            // Background Color Palette
            _buildToolbarButton(
              icon: Icons.format_color_fill,
              label: 'Fill',
              onPressed: () {},
            ),
            const SizedBox(width: 4),
            _buildColorPalette(onColorSelected: (hex) {
              _saveToHistory();
              setState(() {
                if (isHeader) {
                  _headerBgColors[c] = hex;
                } else {
                  _bgColors[r][c] = hex;
                }
              });
            }),
            const SizedBox(width: 12),
            // Text Color Palette
            _buildToolbarButton(
              icon: Icons.format_color_text,
              label: 'Text',
              onPressed: () {},
            ),
            const SizedBox(width: 4),
            _buildColorPalette(onColorSelected: (hex) {
              _saveToHistory();
              setState(() {
                if (isHeader) {
                  _headerTextColors[c] = hex;
                } else {
                  _textColors[r][c] = hex;
                }
              });
            }, isText: true),
            const VerticalDivider(),
            if (!isHeader)
              _buildToolbarButton(
                icon: Icons.check_circle_outline,
                label: 'Mark Paid',
                color: Colors.pink.shade400,
                activeColor: Colors.pink.shade600,
                onPressed: _markCellPaid,
              ),
            const VerticalDivider(),
            // Delete Options
            if (!isHeader)
              _buildToolbarButton(
                icon: Icons.delete_sweep,
                label: 'Del Row',
                color: Colors.redAccent,
                activeColor: Colors.redAccent,
                onPressed: () => _deleteRow(r),
              ),
            _buildToolbarButton(
              icon: Icons.delete_outline,
              label: 'Del Col',
              color: Colors.redAccent,
              activeColor: Colors.redAccent,
              onPressed: () => _deleteColumn(c),
            ),
            const VerticalDivider(),
            _buildToolbarButton(
              icon: Icons.close,
              label: 'Close',
              onPressed: () => setState(() {
                _focusedRow = null;
                _focusedCol = null;
                _selectedCells.clear();
              }),
            ),
          ],
        ),
      ),
      ),
      ],
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
    Color? activeColor,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color ?? const Color(0xFF475569)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: activeColor ?? (color ?? const Color(0xFF475569)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPalette({required Function(String?) onColorSelected, bool isText = false}) {
    final colors = [
      null, // Clear
      '#FFF9C4', // Light Yellow
      '#BBDEFB', // Light Blue
      '#C8E6C9', // Light Green
      '#FFCDD2', // Light Red
      '#F5F5F5', // Light Grey
      '#000000', // Black
      '#FFFFFF', // White
      '#1D63D2', // Primary Blue
    ];

    return Row(
      children: colors.map((hex) {
        if (hex == null) {
          return InkWell(
            onTap: () => onColorSelected(null),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.format_color_reset, size: 12, color: Colors.grey),
            ),
          );
        }
        return InkWell(
          onTap: () => onColorSelected(hex),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Color(int.parse(hex.replaceFirst('#', '0xFF'))),
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }).toList(),
    );
  }

  bool _isNumeric(String s) {
    if (s.isEmpty) return false;
    return double.tryParse(s) != null;
  }
}

class _TableSnapshot {
  final List<String> columnTitles;
  final List<double> columnWidths;
  final List<String> headerAlignments;
  final List<bool> headerIsBold;
  final List<String?> headerBgColors;
  final List<String?> headerTextColors;
  final List<List<String>> cellTexts;
  final List<List<String>> alignments;
  final List<List<bool>> isBold;
  final List<List<String?>> bgColors;
  final List<List<String?>> textColors;
  final List<List<bool>> isPaid;

  _TableSnapshot({
    required this.columnTitles,
    required this.columnWidths,
    required this.headerAlignments,
    required this.headerIsBold,
    required this.headerBgColors,
    required this.headerTextColors,
    required this.cellTexts,
    required this.alignments,
    required this.isBold,
    required this.bgColors,
    required this.textColors,
    required this.isPaid,
  });
}

class _CellFormat {
  final String alignment;
  final bool isBold;
  final String? backgroundColor;
  final String? textColor;

  _CellFormat({
    required this.alignment,
    required this.isBold,
    this.backgroundColor,
    this.textColor,
  });
}

