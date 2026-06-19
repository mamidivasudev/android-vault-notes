import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../providers.dart';
import '../widgets/category_chip_bar.dart';
import '../widgets/expense_card.dart';
import '../widgets/empty_state.dart';
import '../dialogs/expense_dialog.dart';
import '../main_helpers.dart';

class ExpensesView extends ConsumerStatefulWidget {
  const ExpensesView({super.key});

  @override
  ConsumerState<ExpensesView> createState() => _ExpensesViewState();
}

class _ExpensesViewState extends ConsumerState<ExpensesView> {
  late PageController _expenseCategoryPageController;
  final Map<String, GlobalKey> _expenseChipKeys = {};
  final Set<String> _expandedDates = {};
  bool _showBreakdown = false;

  static const List<Color> _chartColors = [
    Color(0xFF6366F1), // Indigo
    Color(0xFF3B82F6), // Blue
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFFEC4899), // Pink
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEF4444), // Red
    Color(0xFF14B8A6), // Teal
    Color(0xFFF97316), // Orange
    Color(0xFF06B6D4), // Cyan
  ];


  @override
  void initState() {
    super.initState();
    _expenseCategoryPageController = PageController();
  }

  @override
  void dispose() {
    _expenseCategoryPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(expenseCategoriesProvider);
    final selectedCat = ref.watch(selectedExpenseCategoryProvider);
    final allExpenses = ref.watch(expensesProvider);
    final selectedExpenses = ref.watch(selectedExpensesProvider);
    final isSelectionMode = selectedExpenses.isNotEmpty;

    final fullCategories = categories;

    // Fallback if selected category is invalid (but not empty, which means it is still loading)
    if (categories.isNotEmpty && selectedCat.isNotEmpty && !categories.contains(selectedCat)) {
      Future.microtask(() {
        if (mounted) ref.read(selectedExpenseCategoryProvider.notifier).state = categories.first;
      });
    }
    
    final currentSelectedCat = (categories.isNotEmpty && (selectedCat.isEmpty || !categories.contains(selectedCat))) 
        ? categories.first 
        : selectedCat;

    // Sync PageController and ensure the chip is visible after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cat = ref.read(selectedExpenseCategoryProvider);
      if (cat.isEmpty) return;

      final index = fullCategories.indexOf(cat);
      if (index != -1 && _expenseCategoryPageController.hasClients && _expenseCategoryPageController.page?.round() != index) {
        _expenseCategoryPageController.jumpToPage(index);
      }
      
      final key = _expenseChipKeys[cat];
      if (key != null && key.currentContext != null) {
        Scrollable.ensureVisible(key.currentContext!, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut, alignment: 0.5);
      }
    });

    final categoryExpenses = allExpenses
        .where((e) => currentSelectedCat == 'All' || e.category == currentSelectedCat)
        .toList();

    return Column(
      children: [
        CategoryChipBar(
          categories: fullCategories,
          selectedCategory: currentSelectedCat,
          onSelected: (cat) => ref.read(selectedExpenseCategoryProvider.notifier).state = cat,
          onLongPress: (cat) => showExpenseCategoryOptions(context, ref, cat),
          onAddPressed: () => addExpenseCategory(context, ref),
          onManagePressed: () => manageExpenseCategoriesDialog(context, ref),
          chipKeys: _expenseChipKeys,
          showFavoritesOnly: ref.watch(showFavoritesOnlyProvider),
          onFavoriteToggle: () {
            ref.read(showFavoritesOnlyProvider.notifier).state = !ref.read(showFavoritesOnlyProvider);
          },
          showGroupByDateToggle: true,
          groupByDateEnabled: ref.watch(showGroupedExpensesProvider),
          onGroupByDateToggle: () {
            ref.read(showGroupedExpensesProvider.notifier).state =
                !ref.read(showGroupedExpensesProvider);
          },
          itemCount: allExpenses.where((e) {
            final matchCat = currentSelectedCat == 'All' || e.category == currentSelectedCat;
            final matchFav = !ref.watch(showFavoritesOnlyProvider) || e.isFavorite;
            final query = ref.watch(searchQueryProvider).toLowerCase();
            if (query.isEmpty) return matchCat && matchFav;
            return matchCat && matchFav && (e.title.toLowerCase().contains(query) || e.amount.toString().contains(query));
          }).length,
        ),
        _buildSummaryBar(categoryExpenses, currentSelectedCat),
        if (_showBreakdown)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.42,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _buildSpendingBreakdown(ref.watch(expensesProvider)),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: PageView.builder(
            controller: _expenseCategoryPageController,
            physics: const ClampingScrollPhysics(),
            itemCount: fullCategories.length,
            onPageChanged: (index) {
              ref.read(selectedExpenseCategoryProvider.notifier).state = fullCategories[index];
            },
            itemBuilder: (context, catIndex) {
              return _buildExpensesPage(fullCategories[catIndex], allExpenses, selectedExpenses, isSelectionMode);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBar(List<Expense> expenses, String selectedCat) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sortOrder = ref.watch(expenseSortOrderProvider);
    double income = 0;
    double expense = 0;
    for (var e in expenses) {
      if (e.type == 'In') {
        income += e.amount;
      } else if (e.type == 'Out') expense += e.amount;
    }
    final balance = income - expense;

    final budgets = ref.watch(expenseBudgetProvider);
    final budgetLimit = budgets[selectedCat];
    final hasBudget = budgetLimit != null && budgetLimit > 0;
    final budgetRatio = hasBudget ? (expense / budgetLimit).clamp(0.0, 1.0) : 0.0;
    final budgetColor = hasBudget
        ? (expense > budgetLimit
            ? const Color(0xFFEF4444)
            : expense >= budgetLimit * 0.8
                ? const Color(0xFFF97316)
                : const Color(0xFF10B981))
        : Colors.transparent;

    final formatter = NumberFormat.decimalPattern('en_IN');
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final dividerColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final budgetTrackColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryColumn(context, 'In', income, const Color(0xFF10B981)),
              _buildSummaryColumn(context, 'Out', expense, const Color(0xFFEF4444)),
              _buildSummaryColumn(
                context,
                'Balance',
                balance,
                balance >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              ),
            ],
          ),
          if (hasBudget) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: dividerColor),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '₹${formatter.format(expense)} of ₹${formatter.format(budgetLimit)} limit',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: budgetColor),
                ),
                Text(
                  expense > budgetLimit
                      ? 'Over budget by ₹${formatter.format(expense - budgetLimit)}'
                      : '₹${formatter.format(budgetLimit - expense)} remaining',
                  style: TextStyle(fontSize: 11, color: budgetColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: budgetRatio,
                backgroundColor: budgetTrackColor,
                valueColor: AlwaysStoppedAnimation<Color>(budgetColor),
                minHeight: 8,
              ),
            ),
          ],
          if (expense > 0) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: dividerColor),
            const SizedBox(height: 8),
            Center(
              child: SizedBox(
                width: 280,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              final filtered = selectedCat == 'All'
                                  ? ref.read(expensesProvider)
                                  : ref.read(expensesProvider)
                                      .where((e) => e.category == selectedCat)
                                      .toList();
                              exportExpensesToCSV(context, filtered, selectedCat);
                            },
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.upload_rounded, size: 16, color: Color(0xFF1D63D2)),
                                SizedBox(width: 4),
                                Text(
                                  'Export CSV',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1D63D2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              final filtered = selectedCat == 'All'
                                  ? ref.read(expensesProvider)
                                  : ref.read(expensesProvider)
                                      .where((e) => e.category == selectedCat)
                                      .toList();
                              exportExpensesToTXT(context, filtered, selectedCat);
                            },
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.description_outlined, size: 16, color: Color(0xFF10B981)),
                                SizedBox(width: 4),
                                Text(
                                  'Export TXT',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _showBreakdown = !_showBreakdown),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showBreakdown ? Icons.keyboard_arrow_up : Icons.bar_chart,
                                  size: 16,
                                  color: const Color(0xFF6366F1),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _showBreakdown ? 'Hide Breakdown' : 'Show Breakdown',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6366F1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showSortOptions(context, ref),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: 20), // Placeholder to match icon (16) + spacing (4) of Export TXT
                                Text(
                                  'Sort',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF8B5CF6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpendingBreakdown(List<Expense> allExpenses) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    double totalExpense = 0;
    for (var e in allExpenses) {
      if (e.type == 'Out') totalExpense += e.amount;
    }
    if (totalExpense <= 0) return const SizedBox.shrink();

    final categoryTotals = <String, double>{};
    for (var e in allExpenses) {
      if (e.type == 'Out') {
        categoryTotals[e.category] = (categoryTotals[e.category] ?? 0) + e.amount;
      }
    }
    if (categoryTotals.isEmpty) return const SizedBox.shrink();

    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final formatter = NumberFormat.decimalPattern('en_IN');
    final titleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF334155);
    final labelColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    final amountColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final trackColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spending Breakdown',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 12),
          ...sortedCategories.map((entry) {
            final category = entry.key;
            final amount = entry.value;
            final percentage = (amount / totalExpense) * 100;
            final index = sortedCategories.indexOf(entry);
            final color = _chartColors[index % _chartColors.length];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          category,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: labelColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '₹${formatter.format(amount)} (${percentage.toStringAsFixed(1)}%)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: amountColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: amount / totalExpense,
                      backgroundColor: trackColor,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showSortOptions(BuildContext context, WidgetRef ref) {
    final currentSort = ref.read(expenseSortOrderProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Sort Expenses',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              _buildSortOption(context, ref, 'Newest First', ExpenseSortOrder.dateNewest, currentSort, Icons.arrow_downward),
              _buildSortOption(context, ref, 'Oldest First', ExpenseSortOrder.dateOldest, currentSort, Icons.arrow_upward),
              _buildSortOption(context, ref, 'Highest Amount', ExpenseSortOrder.amountHighest, currentSort, Icons.attach_money),
              _buildSortOption(context, ref, 'Lowest Amount', ExpenseSortOrder.amountLowest, currentSort, Icons.money_off),
              _buildSortOption(context, ref, 'A to Z', ExpenseSortOrder.atoz, currentSort, Icons.sort_by_alpha),
              _buildSortOption(context, ref, 'Z to A', ExpenseSortOrder.ztoa, currentSort, Icons.sort_by_alpha),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSortOption(BuildContext context, WidgetRef ref, String title, ExpenseSortOrder order, ExpenseSortOrder currentSort, IconData icon) {
    final isSelected = order == currentSort;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return ListTile(
      leading: Icon(icon, color: isSelected ? const Color(0xFF6366F1) : (isDark ? Colors.grey[400] : Colors.grey[600])),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? const Color(0xFF6366F1) : (isDark ? Colors.white : Colors.black),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF6366F1)) : null,
      onTap: () {
        ref.read(expenseSortOrderProvider.notifier).state = order;
        Navigator.pop(context);
      },
    );
  }


  Widget _buildSummaryColumn(BuildContext context, String label, double amount, Color valueColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formatter = NumberFormat.decimalPattern('en_IN');
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '₹ ${formatter.format(amount)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildExpensesPage(String category, List<Expense> allExpenses, Set<String> selectedExpenses, bool isSelectionMode) {

    final sortOrder = ref.watch(expenseSortOrderProvider);
    final showGrouped = ref.watch(showGroupedExpensesProvider) && 
        (sortOrder == ExpenseSortOrder.dateNewest || sortOrder == ExpenseSortOrder.dateOldest);
    final query = ref.watch(searchQueryProvider).toLowerCase();
    final showFavs = ref.watch(showFavoritesOnlyProvider);
    
    final filteredExpenses = allExpenses.where((e) {
      final matchCat = category == 'All' || e.category == category;
      final matchFav = !showFavs || e.isFavorite;
      if (query.isEmpty) return matchCat && matchFav;
      return matchCat && matchFav && (e.title.toLowerCase().contains(query) || e.amount.toString().contains(query));
    }).toList();

    // Sort: Pinned first, then by preference
    filteredExpenses.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      
      switch (sortOrder) {
        case ExpenseSortOrder.dateNewest: return b.date.compareTo(a.date);
        case ExpenseSortOrder.dateOldest: return a.date.compareTo(b.date);
        case ExpenseSortOrder.amountHighest: return b.amount.compareTo(a.amount);
        case ExpenseSortOrder.amountLowest: return a.amount.compareTo(b.amount);
        case ExpenseSortOrder.atoz: return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case ExpenseSortOrder.ztoa: return b.title.toLowerCase().compareTo(a.title.toLowerCase());
      }
    });

    if (filteredExpenses.isEmpty) {
      return EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Empty Category',
        subtitle: 'No transactions in "$category". Tap + to add one!',
        actionLabel: 'Add Expense',
        onAction: () => createNewExpense(context, ref),
      );
    }



    if (!showGrouped || query.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: filteredExpenses.length,
        itemBuilder: (context, index) {
          final exp = filteredExpenses[index];
          final isSelected = selectedExpenses.contains(exp.id);
          return ExpenseCard(
            key: ValueKey(exp.id),
            expense: exp,
            isSelected: isSelected,
            isSelectionMode: isSelectionMode,
            onTap: () {
              if (isSelectionMode) {
                ref.read(selectedExpensesProvider.notifier).toggle(exp.id);
              } else if (exp.isLocked) {
                verifyPasscode(context, ref, onSuccess: () {
                  showDialog(context: context, useRootNavigator: true, builder: (context) => ExpenseDialog(expense: exp));
                });
              } else {
                showDialog(context: context, useRootNavigator: true, builder: (context) => ExpenseDialog(expense: exp));
              }
            },
            onLongPress: () {
              if (!isSelectionMode) {
                ref.read(selectedExpensesProvider.notifier).toggle(exp.id);
              }
            },
            onCheckboxChanged: (val) => ref.read(selectedExpensesProvider.notifier).toggle(exp.id),
            onMorePressed: () => showExpenseOptions(context, ref, exp),
          );
        },
      );
    }

    // Normal view: Grouped by Date
    final groupedItems = <dynamic>[];
    final daySummaries = <DateTime, Map<String, double>>{};
    
    for (var exp in filteredExpenses) {
      final d = DateTime(exp.date.year, exp.date.month, exp.date.day);
      if (!daySummaries.containsKey(d)) {
        daySummaries[d] = {'in': 0, 'out': 0};
      }
      if (exp.type == 'In') {
        daySummaries[d]!['in'] = daySummaries[d]!['in']! + exp.amount;
      } else if (exp.type == 'Out') {
        daySummaries[d]!['out'] = daySummaries[d]!['out']! + exp.amount;
      }
    }

    DateTime? lastDate;
    for (var exp in filteredExpenses) {
      final d = DateTime(exp.date.year, exp.date.month, exp.date.day);
      if (lastDate == null || d != lastDate) {
        groupedItems.add(d);
        lastDate = d;
      }
      
      final dateKey = DateFormat('yyyy-MM-dd').format(d);
      if (_expandedDates.contains(dateKey)) {
        groupedItems.add(exp);
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: groupedItems.length,
      itemBuilder: (context, index) {
        final item = groupedItems[index];
        
        if (item is DateTime) {
          final summary = daySummaries[item]!;
          final balance = summary['in']! - summary['out']!;
          final isToday = DateTime.now().year == item.year && DateTime.now().month == item.month && DateTime.now().day == item.day;
          final isYesterday = DateTime.now().subtract(const Duration(days: 1)).year == item.year && DateTime.now().subtract(const Duration(days: 1)).month == item.month && DateTime.now().subtract(const Duration(days: 1)).day == item.day;
          
          String dateStr = DateFormat('dd MMM yyyy').format(item);
          if (isToday) {
            dateStr = "Today, $dateStr";
          } else if (isYesterday) dateStr = "Yesterday, $dateStr";
          else dateStr = "${DateFormat('EEEE').format(item)}, $dateStr";

          final dateKey = DateFormat('yyyy-MM-dd').format(item);
          final isExpanded = _expandedDates.contains(dateKey);

          final isDarkCtx = Theme.of(context).brightness == Brightness.dark;
          return Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8, left: 4, right: 4),
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedDates.remove(dateKey);
                  } else {
                    _expandedDates.add(dateKey);
                  }
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: isDarkCtx
                      ? const Color(0xFF0F172A)
                      : Colors.grey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDarkCtx
                        ? const Color(0xFF1E293B)
                        : Colors.grey.withOpacity(0.12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                      size: 18,
                      color: isDarkCtx ? const Color(0xFF64748B) : Colors.blueGrey.shade400,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isDarkCtx ? const Color(0xFFCBD5E1) : Colors.blueGrey.shade800,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (summary['in']! > 0 || summary['out']! > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (balance >= 0 ? Colors.green : Colors.red)
                              .withOpacity(isDarkCtx ? 0.15 : 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '₹${NumberFormat.decimalPattern('en_IN').format(balance % 1 == 0 ? balance.toInt() : balance)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: balance >= 0
                                ? (isDarkCtx ? Colors.green.shade400 : Colors.green.shade700)
                                : (isDarkCtx ? Colors.red.shade400 : Colors.red.shade700),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        final exp = item as Expense;
        final isSelected = selectedExpenses.contains(exp.id);
        return ExpenseCard(
          key: ValueKey(exp.id),
          expense: exp,
          isSelected: isSelected,
          isSelectionMode: isSelectionMode,
          onTap: () {
            if (isSelectionMode) {
              ref.read(selectedExpensesProvider.notifier).toggle(exp.id);
            } else if (exp.isLocked) {
              verifyPasscode(context, ref, onSuccess: () {
                showDialog(context: context, useRootNavigator: true, builder: (context) => ExpenseDialog(expense: exp));
              });
            } else {
              showDialog(context: context, useRootNavigator: true, builder: (context) => ExpenseDialog(expense: exp));
            }
          },
          onLongPress: () {
            if (!isSelectionMode) {
              ref.read(selectedExpensesProvider.notifier).toggle(exp.id);
            }
          },
          onCheckboxChanged: (val) => ref.read(selectedExpensesProvider.notifier).toggle(exp.id),
          onMorePressed: () => showExpenseOptions(context, ref, exp),
        );
      },
    );
  }
}
