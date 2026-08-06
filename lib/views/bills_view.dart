import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../providers.dart';
import '../dialogs/bill_dialog.dart';
import '../profiles/providers/theme_provider.dart';
import '../notification_service.dart';

class BillsView extends ConsumerStatefulWidget {
  const BillsView({super.key});

  @override
  ConsumerState<BillsView> createState() => _BillsViewState();
}

class _BillsViewState extends ConsumerState<BillsView> {
  int _viewTab = 0; // 0 for list view, 1 for calendar view
  bool _creditBillsExpanded = false;
  bool _loanBillsExpanded = false;
  bool _otherBillsExpanded = false;

  Future<void> _showMonthlyReport(List<Bill> allBills) async {
    final currentCreditBills = allBills.where((b) => (b.type ?? 'Credit Card') == 'Credit Card').toList();
    final currentLoanBills = allBills.where((b) => b.type == 'Loan').toList();
    final currentCredit = currentCreditBills.fold<double>(0.0, (s, b) => s + b.amount);
    final currentLoan = currentLoanBills.fold<double>(0.0, (s, b) => s + b.amount);
    
    final creditDetails = currentCreditBills.map((b) => <String, dynamic>{'title': b.title, 'amount': b.amount}).toList();
    final loanDetails = currentLoanBills.map((b) => <String, dynamic>{'title': b.title, 'amount': b.amount}).toList();

    final now = DateTime.now();
    await ref.read(vaultServiceProvider).addOrUpdateMonthlySnapshot(
      now.year, 
      now.month, 
      currentCredit, 
      currentLoan,
      creditDetails: creditDetails,
      loanDetails: loanDetails,
    );
    var reports = await ref.read(vaultServiceProvider).loadMonthlyReports();
    try {
      final prefs = await SharedPreferences.getInstance();
      const seenKey = 'monthly_report_seen';
      final seen = prefs.getBool(seenKey) ?? false;
      if (!seen) {
        await showDialog(
          context: context,
          builder: (dctx) => AlertDialog(
            title: const Text('Monthly Report — Notes'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('• The current month is automatically updated when you open this report.'),
                SizedBox(height: 6),
                Text('• Tap the three-dot menu on a month to edit its saved values.'),
                SizedBox(height: 6),
                Text('• Snapshots are saved to monthly_reports.json and included in Drive export.'),
                SizedBox(height: 6),
                Text('• Range shown is May 2026 — May 2028; you can edit any month.'),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Got it'))],
          ),
        );
        await prefs.setBool(seenKey, true);
      }
    } catch (e) {
      // ignore prefs errors
    }

    final Set<int> expandedIndices = {};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
        DateTime start;
        final paidBills = allBills.where((b) => b.lastPaidDate != null).toList();
        if (paidBills.isEmpty) {
          start = DateTime(DateTime.now().year, 1, 1);
        } else {
          final sorted = List<Bill>.from(paidBills)..sort((a, b) => a.lastPaidDate!.compareTo(b.lastPaidDate!));
          start = DateTime(sorted.first.lastPaidDate!.year, sorted.first.lastPaidDate!.month, 1);
        }
        // End date is current month + 1 year
        final end = DateTime(DateTime.now().year, DateTime.now().month, 1).add(const Duration(days: 365));
        final monthsCount =
            (end.year - start.year) * 12 + (end.month - start.month) + 1;
        final months = List.generate(monthsCount, (i) {
          final dt = DateTime(start.year, start.month + i, 1);
          final label = '${DateFormat.MMM().format(dt)} ${dt.year}';
          final found = reports.firstWhere(
                  (r) => r['year'] == dt.year && r['month'] == dt.month,
              orElse: () => <String, dynamic>{});
          final recorded = (found as Map).isNotEmpty;
          final credit =
          recorded ? (found['credit'] as num?)?.toDouble() ?? 0.0 : 0.0;
          final loan =
          recorded ? (found['loan'] as num?)?.toDouble() ?? 0.0 : 0.0;
          return {
            'label': label,
            'credit': credit,
            'loan': loan,
            'creditDetails': found['creditDetails'] ?? [],
            'loanDetails': found['loanDetails'] ?? [],
            'recorded': recorded,
            'dt': dt,
          };
        });

        String fmt(double v) =>
            '₹${NumberFormat.decimalPattern('en_IN').format(v)}';

        final isDark =
            ref.watch(themeModeProvider) == ThemeMode.dark;

        return Container(
          height: MediaQuery.of(context).size.height * 0.82,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                height: 4,
                width: 40,
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              // Header
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1D63D2).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.bar_chart_rounded,
                          color: Color(0xFF1D63D2), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Monthly Report',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            'May 2026 – May 2028',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.ios_share_rounded, color: isDark ? Colors.white70 : Colors.black87),
                      tooltip: 'Export as CSV',
                      onPressed: () async {
                        try {
                          final buffer = StringBuffer();
                          buffer.writeln('Month,Credit Cards (Total),Loans (Total),Overall Total,Credit Details,Loan Details');
                          for (final m in months) {
                            final recorded = m['recorded'] as bool? ?? false;
                            if (!recorded) continue;
                            final label = m['label'];
                            final credit = m['credit'];
                            final loan = m['loan'];
                            final total = (credit as num) + (loan as num);
                            final creditDetails = (m['creditDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                            final loanDetails = (m['loanDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                            
                            String formatDetails(List<Map<String, dynamic>> details) {
                              if (details.isEmpty) return '';
                              return details.map((d) => '${d['title']}: ${d['amount']}').join(' | ').replaceAll('"', '""');
                            }
                            final cDetailsStr = formatDetails(creditDetails);
                            final lDetailsStr = formatDetails(loanDetails);
                            
                            buffer.writeln('"$label",$credit,$loan,$total,"$cDetailsStr","$lDetailsStr"');
                          }
                          final dir = await getTemporaryDirectory();
                          final file = File('${dir.path}/Vault_Monthly_Report.csv');
                          await file.writeAsString(buffer.toString());
                          await Share.shareXFiles([XFile(file.path)], text: 'Vault Notes - Monthly Report');
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error exporting: $e')));
                          }
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.description_outlined, color: isDark ? Colors.green.shade400 : Colors.green.shade700),
                      tooltip: 'Export as TXT',
                      onPressed: () async {
                        try {
                          final buffer = StringBuffer();
                          buffer.writeln('--- Vault Notes: Monthly Report ---');
                          for (final m in months) {
                            final recorded = m['recorded'] as bool? ?? false;
                            if (!recorded) continue;
                            final label = m['label'];
                            final credit = m['credit'];
                            final loan = m['loan'];
                            final total = (credit as num) + (loan as num);
                            final creditDetails = (m['creditDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                            final loanDetails = (m['loanDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                            
                            buffer.writeln('\n[$label]');
                            buffer.writeln('Credit Cards: ₹$credit');
                            if (creditDetails.isNotEmpty) {
                              buffer.writeln('  Details: ${creditDetails.map((d) => '${d['title']}: ₹${d['amount']}').join(' | ')}');
                            }
                            buffer.writeln('Loans: ₹$loan');
                            if (loanDetails.isNotEmpty) {
                              buffer.writeln('  Details: ${loanDetails.map((d) => '${d['title']}: ₹${d['amount']}').join(' | ')}');
                            }
                            buffer.writeln('Total: ₹$total');
                            buffer.writeln('-' * 40);
                          }
                          final dir = await getTemporaryDirectory();
                          final file = File('${dir.path}/Vault_Monthly_Report.txt');
                          await file.writeAsString(buffer.toString());
                          await Share.shareXFiles([XFile(file.path)], text: 'Vault Notes - Monthly Report (TXT)');
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error exporting: $e')));
                          }
                        }
                      },
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              // Column headers
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text('Month',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.black38,
                              letterSpacing: 0.5)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('Credit Cards',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade700,
                              letterSpacing: 0.5)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('Loans',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1D63D2),
                              letterSpacing: 0.5)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('Total',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700,
                              letterSpacing: 0.5)),
                    ),
                  ],
                ),
              ),
              Divider(
                  height: 1,
                  thickness: 0.5,
                  color: isDark
                      ? Colors.white12
                      : Colors.black12),
              // List
              Expanded(
                child: ListView.builder(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: months.length,
                  itemBuilder: (c, idx) {
                    final m = months[idx];
                    final recorded = m['recorded'] as bool? ?? false;
                    final label = m['label'] as String;
                    final creditVal = (m['credit'] as double?) ?? 0.0;
                    final loanVal = (m['loan'] as double?) ?? 0.0;
                    final total = creditVal + loanVal;
                    final dt = m['dt'] as DateTime;
                    final creditDetails = (m['creditDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                    final loanDetails = (m['loanDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                    final hasDetails = creditDetails.isNotEmpty || loanDetails.isNotEmpty;
                    final isExpanded = expandedIndices.contains(idx);
                    final isCurrentMonth = dt.year == DateTime.now().year &&
                        dt.month == DateTime.now().month;

                    return GestureDetector(
                      onTap: () {
                        if (hasDetails) {
                          setModalState(() {
                            if (isExpanded) {
                              expandedIndices.remove(idx);
                            } else {
                              expandedIndices.add(idx);
                            }
                          });
                        }
                      },
                      onLongPress: () async {
                        final creditController = TextEditingController(
                            text: creditVal > 0
                                ? creditVal.toStringAsFixed(0)
                                : '');
                        final loanController = TextEditingController(
                            text: loanVal > 0
                                ? loanVal.toStringAsFixed(0)
                                : '');
                        final res = await showDialog<bool>(
                          context: context,
                          builder: (dctx) => AlertDialog(
                            title: Text('Edit $label'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: creditController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Credit amount'),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: loanController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Loan amount'),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dctx, false),
                                  child: const Text('Cancel')),
                              TextButton(
                                onPressed: () async {
                                  final creditStr = creditController.text
                                      .replaceAll(RegExp(r'[^0-9.]'), '');
                                  final loanStr = loanController.text
                                      .replaceAll(RegExp(r'[^0-9.]'), '');
                                  final credit =
                                      double.tryParse(creditStr) ?? 0.0;
                                  final loan =
                                      double.tryParse(loanStr) ?? 0.0;
                                  final dtParts = label.split(' ');
                                  final mon = DateFormat.MMM()
                                      .parse(dtParts[0])
                                      .month;
                                  final yr = int.tryParse(dtParts[1]) ??
                                      DateTime.now().year;
                                  await ref
                                      .read(vaultServiceProvider)
                                      .addOrUpdateMonthlySnapshot(
                                      yr, mon, credit, loan);
                                  Navigator.pop(dctx, true);
                                },
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        );
                        if (res == true) {
                          final newReports = await ref
                              .read(vaultServiceProvider)
                              .loadMonthlyReports();
                          setModalState(() {
                            reports = newReports;
                          });
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Saved')));
                          }
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isCurrentMonth
                              ? const Color(0xFF1D63D2).withOpacity(0.06)
                              : (recorded
                              ? (isDark
                              ? const Color(0xFF1E293B)
                              : Colors.grey.shade50)
                              : Colors.transparent),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrentMonth
                                ? const Color(0xFF1D63D2).withOpacity(0.3)
                                : (recorded
                                ? (isDark
                                ? Colors.white12
                                : Colors.black12)
                                : Colors.transparent),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                  if (isCurrentMonth)
                                    Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xFF1D63D2),
                                      ),
                                    ),
                                  Flexible(
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: recorded
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                recorded ? fmt(creditVal) : '—',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: recorded
                                      ? Colors.orange.shade700
                                      : Colors.grey.shade400,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                recorded ? fmt(loanVal) : '—',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: recorded
                                      ? const Color(0xFF1D63D2)
                                      : Colors.grey.shade400,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                recorded ? fmt(total) : '—',
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: recorded
                                      ? Colors.green.shade700
                                      : Colors.grey.shade400,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isExpanded && hasDetails)
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Expanded(
                                  flex: 3,
                                  child: SizedBox(),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: creditDetails.map((d) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: GestureDetector(
                                        onTap: () async {
                                          final amtController = TextEditingController(text: (d['amount'] as num).toDouble().toStringAsFixed(0));
                                          final res = await showDialog<bool>(
                                            context: context,
                                            builder: (dctx) => AlertDialog(
                                              title: Text('Edit ${d['title']}'),
                                              content: TextField(
                                                controller: amtController,
                                                keyboardType: TextInputType.number,
                                                decoration: const InputDecoration(labelText: 'Amount'),
                                              ),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
                                                TextButton(onPressed: () async {
                                                  final valStr = amtController.text.replaceAll(RegExp(r'[^0-9.]'), '');
                                                  final val = double.tryParse(valStr) ?? 0.0;
                                                  
                                                  final newDetails = List<Map<String, dynamic>>.from(creditDetails);
                                                  final idx = newDetails.indexWhere((x) => x['title'] == d['title']);
                                                  if (idx != -1) {
                                                    newDetails[idx] = Map<String, dynamic>.from(newDetails[idx])..['amount'] = val;
                                                  }
                                                  
                                                  final newCredit = newDetails.fold<double>(0.0, (s, x) => s + (x['amount'] as num).toDouble());
                                                  
                                                  final dtParts = label.split(' ');
                                                  final mon = DateFormat.MMM().parse(dtParts[0]).month;
                                                  final yr = int.tryParse(dtParts[1]) ?? DateTime.now().year;
                                                  
                                                  await ref.read(vaultServiceProvider).addOrUpdateMonthlySnapshot(
                                                    yr, mon, newCredit, loanVal,
                                                    creditDetails: newDetails,
                                                    loanDetails: loanDetails,
                                                  );
                                                  Navigator.pop(dctx, true);
                                                }, child: const Text('Save')),
                                              ],
                                            ),
                                          );
                                          if (res == true) {
                                            final newReports = await ref.read(vaultServiceProvider).loadMonthlyReports();
                                            setModalState(() {
                                              reports = newReports;
                                            });
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
                                            }
                                          }
                                        },
                                        child: Text('${d['title']}\n${fmt((d['amount'] as num).toDouble())}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                                      ),
                                    )).toList(),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: loanDetails.map((d) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: GestureDetector(
                                        onTap: () async {
                                          final amtController = TextEditingController(text: (d['amount'] as num).toDouble().toStringAsFixed(0));
                                          final res = await showDialog<bool>(
                                            context: context,
                                            builder: (dctx) => AlertDialog(
                                              title: Text('Edit ${d['title']}'),
                                              content: TextField(
                                                controller: amtController,
                                                keyboardType: TextInputType.number,
                                                decoration: const InputDecoration(labelText: 'Amount'),
                                              ),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
                                                TextButton(onPressed: () async {
                                                  final valStr = amtController.text.replaceAll(RegExp(r'[^0-9.]'), '');
                                                  final val = double.tryParse(valStr) ?? 0.0;
                                                  
                                                  final newDetails = List<Map<String, dynamic>>.from(loanDetails);
                                                  final idx = newDetails.indexWhere((x) => x['title'] == d['title']);
                                                  if (idx != -1) {
                                                    newDetails[idx] = Map<String, dynamic>.from(newDetails[idx])..['amount'] = val;
                                                  }
                                                  
                                                  final newLoan = newDetails.fold<double>(0.0, (s, x) => s + (x['amount'] as num).toDouble());
                                                  
                                                  final dtParts = label.split(' ');
                                                  final mon = DateFormat.MMM().parse(dtParts[0]).month;
                                                  final yr = int.tryParse(dtParts[1]) ?? DateTime.now().year;
                                                  
                                                  await ref.read(vaultServiceProvider).addOrUpdateMonthlySnapshot(
                                                    yr, mon, creditVal, newLoan,
                                                    creditDetails: creditDetails,
                                                    loanDetails: newDetails,
                                                  );
                                                  Navigator.pop(dctx, true);
                                                }, child: const Text('Save')),
                                              ],
                                            ),
                                          );
                                          if (res == true) {
                                            final newReports = await ref.read(vaultServiceProvider).loadMonthlyReports();
                                            setModalState(() {
                                              reports = newReports;
                                            });
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
                                            }
                                          }
                                        },
                                        child: Text('${d['title']}\n${fmt((d['amount'] as num).toDouble())}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1D63D2))),
                                      ),
                                    )).toList(),
                                  ),
                                ),
                                const Expanded(
                                  flex: 2,
                                  child: SizedBox(),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
                ),
              ),
              // Long press hint
              Padding(
                padding: const EdgeInsets.only(bottom: 16, top: 4),
                child: Text(
                  'Long press a month to edit values',
                  style: TextStyle(
                    fontSize: 11,
                    color:
                    isDark ? Colors.white38 : Colors.black38,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  void _markBillAsPaid(Bill bill) {
    ref.read(billsProvider.notifier).markAsPaid(bill.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('${bill.title} marked as paid'),
          backgroundColor: Colors.green,
          duration: const Duration(milliseconds: 1500)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bills = ref.watch(billsProvider);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    final now = DateTime.now();
    for (var bill in bills) {
      if (bill.isPaid && bill.lastPaidDate != null) {
        if (bill.lastPaidDate!.month != now.month ||
            bill.lastPaidDate!.year != now.year) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref
                .read(billsProvider.notifier)
                .updateBill(bill.copyWith(isPaid: false));
          });
        }
      }
    }

    final activeBills = bills.where((b) => !b.isPaid).toList();
    final paidBills = bills.where((b) => b.isPaid).toList();

    void sortBills(List<Bill> list) {
      final typeOrder = {'Loan': 0, 'Credit Card': 1};
      list.sort((a, b) {
        final aO = typeOrder[a.type] ?? 2;
        final bO = typeOrder[b.type] ?? 2;
        if (aO != bO) return aO.compareTo(bO);
        return _daysUntil(a.dueDate).compareTo(_daysUntil(b.dueDate));
      });
    }

    sortBills(activeBills);
    sortBills(paidBills);

    final List<Widget> slivers = [];
    {
      final creditBills = bills
          .where((b) => (b.type ?? 'Credit Card') == 'Credit Card')
          .toList();
      final loanBills =
      bills.where((b) => b.type == 'Loan').toList();
      final otherBills = bills
          .where((b) =>
      !((b.type ?? '') == 'Loan' ||
          (b.type ?? 'Credit Card') == 'Credit Card'))
          .toList();

      if (creditBills.isNotEmpty) {
        slivers.add(
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(
              backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              child: _buildSectionHeader(
                title: 'All Credit Bills (${creditBills.length})',
                color: Colors.orange,
                isExpanded: _creditBillsExpanded,
                isDark: isDark,
                onTap: () => setState(() => _creditBillsExpanded = !_creditBillsExpanded),
              ),
            ),
          ),
        );
        if (_creditBillsExpanded) {
          slivers.add(
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildBillCard(creditBills[index], isDark),
                ),
                childCount: creditBills.length,
              ),
            ),
          );
        } else {
          slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
        }
      }

      if (loanBills.isNotEmpty) {
        slivers.add(
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(
              backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              child: _buildSectionHeader(
                title: 'All Loans (${loanBills.length})',
                color: const Color(0xFF1D63D2),
                isExpanded: _loanBillsExpanded,
                isDark: isDark,
                onTap: () => setState(() => _loanBillsExpanded = !_loanBillsExpanded),
              ),
            ),
          ),
        );
        if (_loanBillsExpanded) {
          slivers.add(
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildBillCard(loanBills[index], isDark),
                ),
                childCount: loanBills.length,
              ),
            ),
          );
        } else {
          slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
        }
      }

      if (otherBills.isNotEmpty) {
        slivers.add(
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(
              backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              child: _buildSectionHeader(
                title: 'Other (${otherBills.length})',
                color: isDark ? Colors.white70 : Colors.black87,
                isExpanded: _otherBillsExpanded,
                isDark: isDark,
                onTap: () => setState(() => _otherBillsExpanded = !_otherBillsExpanded),
              ),
            ),
          ),
        );
        if (_otherBillsExpanded) {
          slivers.add(
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildBillCard(otherBills[index], isDark),
                ),
                childCount: otherBills.length,
              ),
            ),
          );
        } else {
          slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
        }
      }

      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: bills.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long,
                size: 64,
                color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 16),
            Text('No Bills Tracked',
                style: TextStyle(
                    fontSize: 18,
                    color:
                    isDark ? Colors.white54 : Colors.black54)),
            const SizedBox(height: 8),
            const Text(
                'Add a credit card, loan, or subscription to get reminders before due dates.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      )
          : Column(
        children: [
          // View Selector Tab
          Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _buildViewTabButton('List View', 0, isDark),
                  _buildViewTabButton('Calendar View', 1, isDark),
                ],
              ),
            ),
          ),
          Expanded(
            child: _viewTab == 0
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (bills.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 8),
                          child: Builder(builder: (context) {
                            final anyAlertsEnabled =
                            bills.any((b) => b.reminderEnabled);
                            final totalCredit = bills
                                .where((b) =>
                            (b.type ?? 'Credit Card') ==
                                'Credit Card')
                                .fold<double>(
                                0.0, (s, b) => s + b.amount);
                            final totalLoan = bills
                                .where((b) => b.type == 'Loan')
                                .fold<double>(
                                0.0, (s, b) => s + b.amount);
                            final combinedTotal = totalCredit + totalLoan;
                            String fmt(double v) =>
                                '₹${NumberFormat.decimalPattern('en_IN').format(v)}';

                            // ── HEADER SECTION ──────────────────────────
                            return Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                // Top row: title + chart icon
                                Row(
                                  children: [
                                    Text(
                                      'Upcoming Bills',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                    // const SizedBox(width: 8),
                                    const Spacer(), // pushes icon to right

                                    InkWell(
                                      borderRadius:
                                      BorderRadius.circular(8),
                                      onTap: () =>
                                          _showMonthlyReport(bills),
                                      child: Padding(
                                        padding: const EdgeInsets.all(6.0),
                                        child: Image.asset(
                                          'assets/icon/bar-chart.png',
                                          width: 25,
                                          height: 25,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                // ── TOTAL SUMMARY CARD ───────────────────
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF1E293B)
                                        : Colors.grey.shade50,
                                    borderRadius:
                                    BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white10
                                          : Colors.black.withOpacity(0.06),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Credit chip
                                      Expanded(
                                        child: _SummaryChip(
                                          label: 'Credit Cards',
                                          amount: fmt(totalCredit),
                                          color: Colors.orange.shade700,
                                          isDark: isDark,
                                        ),
                                      ),
                                      Container(
                                        width: 1,
                                        height: 36,
                                        color: isDark
                                            ? Colors.white12
                                            : Colors.black12,
                                      ),
                                      // Loan chip
                                      Expanded(
                                        child: _SummaryChip(
                                          label: 'Loans',
                                          amount: fmt(totalLoan),
                                          color:
                                          const Color(0xFF1D63D2),
                                          isDark: isDark,
                                        ),
                                      ),
                                      Container(
                                        width: 1,
                                        height: 36,
                                        color: isDark
                                            ? Colors.white12
                                            : Colors.black12,
                                      ),
                                      // Total chip
                                      Expanded(
                                        child: _SummaryChip(
                                          label: 'Total',
                                          amount: fmt(combinedTotal),
                                          color: Colors.green.shade700,
                                          isDark: isDark,
                                          isBold: true,
                                        ),
                                      ),
                                      Container(
                                        width: 1,
                                        height: 36,
                                        color: isDark
                                            ? Colors.white12
                                            : Colors.black12,
                                      ),
                                      // Alerts toggle
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            left: 10),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              anyAlertsEnabled
                                                  ? Icons
                                                  .notifications_active
                                                  : Icons.notifications_off,
                                              size: 15,
                                              color: anyAlertsEnabled
                                                  ? Colors.orange
                                                  : Colors.grey,
                                            ),
                                            const SizedBox(height: 2),
                                            SizedBox(
                                              height: 22,
                                              child: Transform.scale(
                                                scale: 0.75,
                                                child: Switch(
                                                  value: anyAlertsEnabled,
                                                  onChanged:
                                                      (val) async {
                                                    for (final bill
                                                    in activeBills) {
                                                      final updated =
                                                      bill.copyWith(
                                                          reminderEnabled:
                                                          val);
                                                      await ref
                                                          .read(billsProvider
                                                          .notifier)
                                                          .updateBill(
                                                          updated);
                                                      await NotificationService()
                                                          .scheduleBillNotifications(
                                                        billId: updated.id,
                                                        title:
                                                        'Bill Reminder: ${updated.title}',
                                                        dueDay:
                                                        updated.dueDate,
                                                        reminderDaysBeforeList:
                                                        updated
                                                            .reminderDaysBeforeList,
                                                        hour: updated
                                                            .reminderHour,
                                                        minute: updated
                                                            .reminderMinute,
                                                        enabled: updated
                                                            .reminderEnabled,
                                                      );
                                                    }
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                          context)
                                                          .showSnackBar(
                                                          SnackBar(
                                                            content: Text(val
                                                                ? '🔔 Alerts enabled for all'
                                                                : '🔕 Alerts disabled for all'),
                                                            duration:
                                                            const Duration(
                                                                seconds: 1),
                                                          ));
                                                    }
                                                  },
                                                  activeThumbColor:
                                                  const Color(
                                                      0xFF1D63D2),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: CustomScrollView(
                            slivers: [
                              if (bills.isNotEmpty) ...slivers,
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : _buildCalendarView(bills, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildViewTabButton(String label, int tabIndex, bool isDark) {
    final isActive = _viewTab == tabIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _viewTab = tabIndex),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isActive ? const Color(0xFF1D63D2) : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  int _daysUntil(int dueDay) {
    final now = DateTime.now();
    if (now.day > dueDay) {
      final daysInThisMonth =
          DateTime(now.year, now.month + 1, 0).day;
      return (daysInThisMonth - now.day) + dueDay;
    } else {
      return dueDay - now.day;
    }
  }

  Widget _buildCalendarView(List<Bill> bills, bool isDark) {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final leadSpaces = firstDay.weekday % 7;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final totalCells = leadSpaces + daysInMonth;
    final weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekdays
                .map((w) => Text(w,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)))
                .toList(),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.95,
            ),
            itemCount: totalCells,
            itemBuilder: (context, index) {
              if (index < leadSpaces) return const SizedBox.shrink();
              final day = index - leadSpaces + 1;
              final dayBills =
              bills.where((b) => b.dueDate == day).toList();
              final isToday = now.day == day;
              final anyUnpaid = dayBills.any((b) => !b.isPaid);

              return InkWell(
                onTap: dayBills.isEmpty
                    ? null
                    : () => _showDayBillsSheet(day, dayBills, isDark),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: isToday
                        ? const Color(0xFF1D63D2).withOpacity(0.12)
                        : (isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isToday
                          ? const Color(0xFF1D63D2)
                          : (dayBills.isNotEmpty
                          ? (anyUnpaid
                          ? Colors.orange
                          : Colors.green)
                          : Colors.transparent),
                      width: isToday ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isToday || dayBills.isNotEmpty
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isToday
                              ? const Color(0xFF1D63D2)
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      if (dayBills.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: dayBills
                              .map((b) => Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 1.5),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: b.isPaid
                                  ? Colors.green
                                  : (b.amount > 1000
                                  ? Colors.red
                                  : Colors.orange),
                            ),
                          ))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDayBillsSheet(int day, List<Bill> dayBills, bool isDark) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius:
          const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bills due on the $day${_getSuffix(day)}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: dayBills.length,
                itemBuilder: (c, idx) {
                  final bill = dayBills[idx];
                  return ListTile(
                    leading: Icon(
                        bill.isPaid
                            ? Icons.check_circle
                            : Icons.receipt_long,
                        color:
                        bill.isPaid ? Colors.green : Colors.orange),
                    title: Text(
                        '${bill.title} ${bill.type != null ? "(${bill.type})" : ""}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        '${bill.isPaid ? 'Paid' : 'Unpaid'}${bill.note != null && bill.note!.isNotEmpty ? '\nNote: ${bill.note}' : ''}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (bill.amount > 0)
                          Text(
                              '₹${NumberFormat.decimalPattern('en_IN').format(bill.amount)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: Icon(
                              bill.isPaid
                                  ? Icons.undo
                                  : Icons.check_circle_outline,
                              color: bill.isPaid
                                  ? Colors.grey
                                  : Colors.green),
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (bill.isPaid) {
                              ref.read(billsProvider.notifier).updateBill(
                                  bill.copyWith(
                                      isPaid: false,
                                      lastPaidDate: null));
                            } else {
                              _markBillAsPaid(bill);
                            }
                          },
                        ),
                      ],
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

  Widget _buildBillCard(Bill bill, bool isDark) {
    final daysLeft = _daysUntil(bill.dueDate);
    final isOverdue = daysLeft == 0 && !bill.isPaid;
    final isWarning =
        daysLeft <= bill.reminderDaysBefore && !bill.isPaid;
    final selectedBills = ref.watch(selectedBillsProvider);
    final isSelected = selectedBills.contains(bill.id);
    final isSelectionMode = selectedBills.isNotEmpty;

    Color statusColor;
    String statusText;

    if (bill.isPaid) {
      statusColor = Colors.green;
      statusText = 'Paid';
    } else if (isOverdue) {
      statusColor = Colors.red;
      statusText = 'Due Today';
    } else if (isWarning) {
      statusColor = Colors.orange;
      statusText = 'Due in $daysLeft day${daysLeft == 1 ? "" : "s"}';
    } else {
      statusColor = const Color(0xFF1D63D2);
      statusText = 'Due in $daysLeft days';
    }

    return Card(
      elevation: isSelected ? 4 : 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? const Color(0xFF1D63D2)
              : statusColor.withOpacity(0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      color: isSelected
          ? const Color(0xFF1D63D2).withOpacity(0.08)
          : (isDark ? const Color(0xFF1E293B) : Colors.white),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (isSelectionMode) {
            ref.read(selectedBillsProvider.notifier).toggle(bill.id);
          } else {
            showDialog(
                context: context,
                builder: (ctx) => BillDialog(bill: bill));
          }
        },
        onLongPress: () {
          HapticFeedback.mediumImpact();
          ref.read(selectedBillsProvider.notifier).toggle(bill.id);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? const Color(0xFF1D63D2)
                          : Colors.transparent,
                      border: Border.all(
                          color: isSelected
                              ? const Color(0xFF1D63D2)
                              : Colors.grey,
                          width: 2),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check,
                        size: 14, color: Colors.white)
                        : null,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      shape: BoxShape.circle),
                  child: Icon(Icons.receipt_long,
                      color: statusColor, size: 24),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${bill.title} ${bill.type != null ? "(${bill.type})" : ""}',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.white
                                    : Colors.black87),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                            bill.reminderEnabled
                                ? Icons.notifications_active
                                : Icons.notifications_off,
                            size: 14,
                            color: bill.reminderEnabled
                                ? Colors.orange
                                : Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                        'Due on the ${bill.dueDate}${_getSuffix(bill.dueDate)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white54
                                : Colors.black54)),
                    const SizedBox(height: 3),
                    Text(statusText,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: statusColor)),
                    if (bill.note != null && bill.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Note: ${bill.note}',
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.black54,
                              fontStyle: FontStyle.italic),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              if (!isSelectionMode) ...[
                if (bill.amount > 0) ...[
                  Text(
                      '₹${NumberFormat.decimalPattern('en_IN').format(bill.amount)}',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color:
                          isDark ? Colors.white : Colors.black87)),
                  const SizedBox(width: 4),
                ],
                IconButton(
                  icon: Icon(Icons.more_vert,
                      color:
                      isDark ? Colors.white54 : Colors.black45),
                  onPressed: () => _showBillOptions(bill, isDark),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showBillOptions(Bill bill, bool isDark) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!bill.isPaid)
              ListTile(
                leading:
                const Icon(Icons.check_circle_outline, color: Colors.green),
                title: const Text('Mark as Paid'),
                onTap: () {
                  Navigator.pop(ctx);
                  _markBillAsPaid(bill);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.undo, color: Colors.grey),
                title: const Text('Mark as Unpaid'),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(billsProvider.notifier).updateBill(
                      bill.copyWith(isPaid: false, lastPaidDate: null));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('${bill.title} marked as unpaid'),
                      duration: const Duration(milliseconds: 1500)));
                },
              ),
            ListTile(
              leading: Icon(
                bill.reminderEnabled
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined,
                color: bill.reminderEnabled
                    ? Colors.orange
                    : const Color(0xFF1D63D2),
              ),
              title: Text(bill.reminderEnabled
                  ? 'Disable Alert'
                  : 'Enable Alert'),
              onTap: () async {
                Navigator.pop(ctx);
                final updated =
                bill.copyWith(reminderEnabled: !bill.reminderEnabled);
                ref.read(billsProvider.notifier).updateBill(updated);
                await NotificationService().scheduleBillNotifications(
                  billId: updated.id,
                  title: 'Bill Reminder: ${updated.title}',
                  dueDay: updated.dueDate,
                  reminderDaysBeforeList: updated.reminderDaysBeforeList,
                  hour: updated.reminderHour,
                  minute: updated.reminderMinute,
                  enabled: updated.reminderEnabled,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(updated.reminderEnabled
                        ? 'Alerts enabled for ${updated.title}'
                        : 'Alerts disabled for ${updated.title}'),
                    duration: const Duration(milliseconds: 1500),
                  ));
                }
              },
            ),
            ListTile(
              leading:
              const Icon(Icons.edit_outlined, color: Color(0xFF1D63D2)),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(ctx);
                showDialog(
                    context: context,
                    builder: (c) => BillDialog(bill: bill));
              },
            ),
            ListTile(
              leading:
              const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Delete Bill?'),
                    content:
                    Text('Remove "${bill.title}" and its reminders?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Cancel')),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(c);
                          ref
                              .read(billsProvider.notifier)
                              .deleteBill(bill.id);
                          NotificationService()
                              .cancelBillNotifications(bill.id);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('${bill.title} deleted'),
                              duration:
                              const Duration(milliseconds: 1500)));
                        },
                        child: const Text('Delete',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required Color color,
    required bool isExpanded,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
              width: 1,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: color,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  String _getSuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }
}

// ── Helper widget for the summary row ─────────────────────────────────────────
class _SummaryChip extends StatelessWidget {
  final String label;
  final String amount;
  final Color color;
  final bool isDark;
  final bool isBold;

  const _SummaryChip({
    required this.label,
    required this.amount,
    required this.color,
    required this.isDark,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white38 : Colors.black38,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            amount,
            style: TextStyle(
              fontSize: isBold ? 15 : 13,
              fontWeight:
              isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height = 48.0;
  final Color backgroundColor;

  _StickyHeaderDelegate({
    required this.child,
    required this.backgroundColor,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: height,
      color: backgroundColor,
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return oldDelegate.child != child ||
        oldDelegate.height != height ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
