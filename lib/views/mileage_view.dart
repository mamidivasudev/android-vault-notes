import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';


import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';

// ---------- Mileage View ----------
class MileageView extends ConsumerStatefulWidget {
  const MileageView({super.key});

  @override
  ConsumerState<MileageView> createState() => _MileageViewState();
}

class _MileageViewState extends ConsumerState<MileageView> {
  static const _prefsKey = 'fuel_entries';
  static const _seededKey = 'fuel_seeded_v1';
  double? _lastServiceOdo;
  double? _nextServiceOdo;

  // ---- Historical seed data ----
  static const List<Map<String, dynamic>> _seedData = [
    // Date, odometer(km), rupees, liters (null = no liters recorded)
    {'date': '2026-03-15', 'odometer': 12.0,  'rupees': 107.0,    'liters': 1.00},
    {'date': '2026-03-19', 'odometer': 71.0,  'rupees': 120.0,    'liters': 1.12},
    {'date': '2026-03-22', 'odometer': 0.0,   'rupees': 100.0,    'liters': 0.93},  // ODO not recorded
    {'date': '2026-03-23', 'odometer': 74.0,  'rupees': 200.0,    'liters': 1.86},
    {'date': '2026-03-27', 'odometer': 108.0, 'rupees': 350.0,    'liters': 3.27},  // Full tank
    {'date': '2026-04-14', 'odometer': 244.0, 'rupees': 380.0,    'liters': 3.53},  // Full tank
    {'date': '2026-05-09', 'odometer': 500.0, 'rupees': 300.0,    'liters': 2.79},  // Partial refill
    // 13 May — 1st Service (no fuel, skipped)
    {'date': '2026-05-16', 'odometer': 571.0, 'rupees': 270.0,    'liters': 2.33},  // Partial refill
    {'date': '2026-05-28', 'odometer': 665.0, 'rupees': 364.0,    'liters': 3.14},  // Full tank
    {'date': '2026-06-13', 'odometer': 844.0, 'rupees': 460.81,   'liters': 3.98},  // Full tank
  ];

  @override
  void initState() {
    super.initState();
    _seedAndLoad();
  }

  Future<void> _seedAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadySeeded = prefs.getBool(_seededKey) ?? false;
    if (!alreadySeeded) {
      final seeded = _seedData
          .map((m) => FuelEntry(
                date: m['date'],
                odometer: m['odometer'],
                rupees: m['rupees'],
                liters: m['liters'],
              ))
          .toList();
      ref.read(fuelEntriesProvider.notifier).setEntries(seeded);
      await prefs.setBool(_seededKey, true);
    }
    
    setState(() {
      _lastServiceOdo = prefs.getDouble('last_service_odo');
      _nextServiceOdo = prefs.getDouble('next_service_odo');
    });
  }

  Future<void> _confirmAndDelete(FuelEntry entry) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry?'),
        content: const Text('Are you sure you want to delete this fuel entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      ref.read(fuelEntriesProvider.notifier).deleteEntry(entry);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Entry deleted'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                ref.read(fuelEntriesProvider.notifier).addEntry(entry);
              },
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _editEntry(FuelEntry oldEntry, FuelEntry newEntry) {
    ref.read(fuelEntriesProvider.notifier).updateEntry(oldEntry, newEntry);
  }

  // ---- Calculations ----
  double _totalKm(List<FuelEntry> entries) {
    if (entries.length < 2) return 0;
    return entries.last.odometer - entries.first.odometer;
  }

  double _totalCost(List<FuelEntry> entries) {
    return entries.fold(0.0, (sum, e) => sum + e.rupees);
  }

  /// Average mileage (km/l) computed from consecutive full-tank fills
  /// that have liters recorded. Distance between two fills / liters
  /// used on the later fill.
  double? _averageMileage(List<FuelEntry> entries) {
    final fullFills = entries.where((e) => e.liters != null && e.liters! > 0).toList();
    if (fullFills.length < 2) return null;

    double totalDistance = 0;
    double totalLiters = 0;
    for (int i = 1; i < fullFills.length; i++) {
      final distance = fullFills[i].odometer - fullFills[i - 1].odometer;
      final liters = fullFills[i].liters!;
      if (distance > 0 && liters > 0) {
        totalDistance += distance;
        totalLiters += liters;
      }
    }
    if (totalLiters == 0) return null;
    return totalDistance / totalLiters;
  }

  void _exportData(List<FuelEntry> entries) {
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data to export')));
      return;
    }
    
    final buffer = StringBuffer();
    buffer.writeln('Mileage Tracker Export');
    buffer.writeln('======================\n');
    
    for (final entry in entries.reversed) {
      buffer.writeln('Date: ${DateFormat('d MMM yyyy').format(DateTime.parse(entry.date))}');
      buffer.writeln('Odometer: ${entry.odometer.toStringAsFixed(1)} km');
      buffer.writeln('Amount Paid: ${entry.rupees.toStringAsFixed(0)} rs');
      if (entry.liters != null) {
        buffer.writeln('Liters: ${entry.liters!.toStringAsFixed(2)} L');
      }
      if (entry.airFilled) {
        buffer.writeln('Air Filled: Yes');
      }
      if (entry.comments != null && entry.comments!.isNotEmpty) {
        buffer.writeln('Comments: ${entry.comments}');
      }
      buffer.writeln('----------------------');
    }
    
    buffer.writeln('\nTotal Distance: ${_totalKm(entries).toStringAsFixed(0)} km');
    buffer.writeln('Total Cost: ${_totalCost(entries).toStringAsFixed(0)} rs');
    final avg = _averageMileage(entries);
    if (avg != null) {
      buffer.writeln('Average Mileage: ${avg.toStringAsFixed(1)} km/l');
    }
    
    Share.share(buffer.toString(), subject: 'Mileage Tracker Data Export');
  }

  Future<void> _backupData() async {
    try {
      final entries = ref.read(fuelEntriesProvider);
      final raw = jsonEncode(entries.map((e) => e.toJson()).toList());
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/mileage_backup.json');
      await file.writeAsString(raw);
      await Share.shareXFiles([XFile(file.path)], text: 'Mileage Tracker Backup');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  Future<void> _restoreData() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(type: FileType.any);
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final raw = await file.readAsString();
        final List decoded = jsonDecode(raw);
        final imported = decoded.map((e) => FuelEntry.fromJson(e)).toList();
        final current = ref.read(fuelEntriesProvider);
        final Map<String, FuelEntry> unique = {};
        for (var e in current) {
          unique['${e.date}_${e.odometer}'] = e;
        }
        for (var e in imported) {
          unique['${e.date}_${e.odometer}'] = e;
        }
        final newEntries = unique.values.toList();
        newEntries.sort((a, b) => a.date.compareTo(b.date));
        ref.read(fuelEntriesProvider.notifier).setEntries(newEntries);
        
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restore successful!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }

  void _openSettings() {
    final odoController = TextEditingController(text: _lastServiceOdo?.toString() ?? '');
    final nextServiceController = TextEditingController(text: _nextServiceOdo?.toString() ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Service Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: odoController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Last Service Odometer (km)'),
            ),
            TextField(
              controller: nextServiceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Next Service Odometer (km)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final odo = double.tryParse(odoController.text);
              final nextService = double.tryParse(nextServiceController.text);
              if (odo != null) {
                await prefs.setDouble('last_service_odo', odo);
              } else {
                await prefs.remove('last_service_odo');
              }
              if (nextService != null) {
                await prefs.setDouble('next_service_odo', nextService);
              } else {
                await prefs.remove('next_service_odo');
              }
              setState(() {
                _lastServiceOdo = odo;
                _nextServiceOdo = nextService;
              });
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _openEntrySheet({FuelEntry? entryToEdit}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F1530),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => AddEntrySheet(
        initialEntry: entryToEdit,
        onSave: (newEntry) {
          if (entryToEdit == null) {
            ref.read(fuelEntriesProvider.notifier).addEntry(newEntry);
          } else {
            ref.read(fuelEntriesProvider.notifier).updateEntry(entryToEdit, newEntry);
          }
        },
      ),
    );
  }

  String _getBikeAgeString(List<FuelEntry> entries) {
    if (entries.isEmpty) return 'No data yet';
    final purchaseDate = DateTime(2026, 3, 15);
    final now = DateTime.now();
    
    int months = now.month - purchaseDate.month + (12 * (now.year - purchaseDate.year));
    int days = now.day - purchaseDate.day;

    if (days < 0) {
      months--;
      final previousMonth = DateTime(now.year, now.month, 0); 
      days += previousMonth.day;
    }
    
    String result = '';
    if (months > 0) {
      result += '$months month${months == 1 ? '' : 's'}';
    }
    if (days > 0) {
      if (result.isNotEmpty) result += ' - ';
      result += '$days day${days == 1 ? '' : 's'}';
    }
    if (result.isEmpty) {
      result = '0 days';
    }
    
    return 'Purchased: Mar 15, 2026\n$result';
  }

  String? _getAirFilledMessage(List<FuelEntry> entries) {
    try {
      final lastAirEntry = entries.lastWhere((e) => e.airFilled);
      final airDate = DateTime.parse(lastAirEntry.date);
      final now = DateTime.now();
      final diff = now.difference(airDate).inDays;
      if (diff >= 15) {
        return 'Air filled $diff days before';
      }
    } catch (_) {
      // No entry found with airFilled == true
    }
    return null;
  }

  Widget _buildServiceReminder(List<FuelEntry> entries) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final currentOdo = entries.last.odometer;
    final lastService = _lastServiceOdo;
    final nextService = _nextServiceOdo;
    if (lastService == null || nextService == null) {
      return Container(
        margin: const EdgeInsets.only(left: 16, right: 16, top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
        child: const Text('Set Last & Next Service Odometer in Service Details to enable Reminders.',
            style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
      );
    }
    
    final remaining = nextService - currentOdo;
    
    Color color = Colors.teal;
    String kmNum = remaining.abs().toStringAsFixed(0);
    String prefixText = 'Next service due in ';
    String suffixText = '';
    
    if (remaining <= 0) {
      color = Colors.red;
      prefixText = 'Service is OVERDUE by ';
      suffixText = '!';
    } else if (remaining < 300) {
      color = Colors.orange;
      prefixText = 'Next service due VERY SOON (';
      suffixText = ')';
    }

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.5))),
      child: Row(
        children: [
          Icon(Icons.build, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
                children: [
                  TextSpan(text: prefixText),
                  TextSpan(text: kmNum, style: const TextStyle(color: Colors.redAccent, fontSize: 15)),
                  TextSpan(text: ' km', style: TextStyle(color: color, fontSize: 15)),
                  TextSpan(text: suffixText),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(fuelEntriesProvider);
    final mileage = _averageMileage(entries);
    final grouped = _groupByMonth(entries);
    final airMessage = _getAirFilledMessage(entries);

    return Scaffold(
      backgroundColor: const Color(0xFF080C1F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => Scaffold.of(context).openDrawer(),
          tooltip: 'Menu',
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2.0),
                  child: Icon(Icons.two_wheeler, color: Colors.white70, size: 20),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getBikeAgeString(entries),
                    style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            if (airMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                airMessage,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ]
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'settings') {
                _openSettings();
              } else if (value == 'share') _exportData(entries);
              else if (value == 'import') _restoreData();
              else if (value == 'export') _backupData();
            },
            color: const Color(0xFF0F1530),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'settings', child: Text('Service Details', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'share', child: Text('Share (Text)', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'import', child: Text('Import Data (JSON)', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'export', child: Text('Export Data (JSON)', style: TextStyle(color: Colors.white))),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildServiceReminder(entries) ?? const SizedBox.shrink(),
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _statCard(
                          'Total Kms',
                          '${_totalKm(entries).toStringAsFixed(0)} km',
                          Colors.teal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _statCard(
                          'Total Cost',
                          '${_totalCost(entries).toStringAsFixed(0)} rs',
                          Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _statCard(
                          'Avg Mil.',
                          mileage != null
                              ? '${mileage.toStringAsFixed(1)} km/l'
                              : 'N/A',
                          Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Fuel entries', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                for (final month in grouped.keys)
                  _MonthSection(
                    month: month,
                    entries: grouped[month]!,
                    onDelete: (entry) {
                      _confirmAndDelete(entry);
                    },
                    onEdit: (entry) {
                      _openEntrySheet(entryToEdit: entry);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEntrySheet(),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Entry'),
      ),
    );
  }

  Widget _statCard(String label, String value, Color color, {bool fullWidth = false}) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Map<String, List<FuelEntry>> _groupByMonth(List<FuelEntry> entries) {
    final Map<String, List<FuelEntry>> map = {};
    for (final e in entries.reversed) {
      final d = DateTime.parse(e.date);
      final key = DateFormat('MMMM yyyy').format(d);
      map.putIfAbsent(key, () => []).add(e);
    }
    return map;
  }
}

class _MonthSection extends StatelessWidget {
  final String month;
  final List<FuelEntry> entries;
  final void Function(FuelEntry) onDelete;
  final void Function(FuelEntry) onEdit;

  const _MonthSection({
    required this.month,
    required this.entries,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final totalKm = entries.length;
    final totalRupees = entries.fold(0.0, (s, e) => s + e.rupees);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1530),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: ExpansionTile(
        title: Text(month, style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
        subtitle: Text('$totalKm entr${totalKm == 1 ? 'y' : 'ies'} · ${totalRupees.toStringAsFixed(0)} rs', style: const TextStyle(color: Colors.white70)),
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white12),
            ListTile(
              onTap: () => onEdit(entries[i]),
              title: Text(DateFormat('d MMM yyyy').format(DateTime.parse(entries[i].date)), style: const TextStyle(color: Colors.white)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('Odometer : ${entries[i].odometer.toStringAsFixed(0)} km', style: const TextStyle(color: Colors.white70)),
                  if (entries[i].liters != null) Text('Liters filled : ${entries[i].liters!.toStringAsFixed(2)} L', style: const TextStyle(color: Colors.white70)),
                  if (entries[i].liters != null)
                    Text('Petrol left : ${(5.1 - entries[i].liters!).toStringAsFixed(2)} L',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  if (entries[i].airFilled)
                    Row(
                      children: const [
                        Text('Air filled ', style: TextStyle(color: Colors.white70)),
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                      ],
                    ),
                  if (entries[i].comments != null && entries[i].comments!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entries[i].comments!,
                      style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                    ),
                  ],
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${entries[i].rupees.toStringAsFixed(0)} rs', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () => onDelete(entries[i]),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------- Add Entry Sheet ----------
class AddEntrySheet extends StatefulWidget {
  final void Function(FuelEntry) onSave;
  final FuelEntry? initialEntry;
  
  const AddEntrySheet({super.key, required this.onSave, this.initialEntry});

  @override
  State<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<AddEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  final _odoController = TextEditingController();
  final _rupeesController = TextEditingController();
  final _litersController = TextEditingController();
  final _commentsController = TextEditingController();
  bool _airFilled = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialEntry != null) {
      final entry = widget.initialEntry!;
      _selectedDate = DateTime.parse(entry.date);
      _odoController.text = entry.odometer.toString();
      _rupeesController.text = entry.rupees.toString();
      if (entry.liters != null) _litersController.text = entry.liters.toString();
      if (entry.comments != null) _commentsController.text = entry.comments!;
      _airFilled = entry.airFilled;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: const InputDecorationTheme(
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.initialEntry == null ? 'Add Fuel Entry' : 'Edit Fuel Entry', 
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Date: ${DateFormat('d MMM yyyy').format(_selectedDate)}', style: const TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.calendar_today, size: 18, color: Colors.white),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _selectedDate = picked);
                  },
                ),
                TextFormField(
                  controller: _odoController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Odometer reading (km)'),
                  style: const TextStyle(color: Colors.white),
                  validator: (v) => (v == null || v.isEmpty) ? 'Enter odometer km' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _rupeesController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount paid (rs)'),
                  style: const TextStyle(color: Colors.white),
                  validator: (v) => (v == null || v.isEmpty) ? 'Enter amount' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _litersController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Liters filled (optional, only if full tank)',
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _commentsController,
                  decoration: const InputDecoration(labelText: 'Comments (optional)'),
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Air filled', style: TextStyle(color: Colors.white)),
                  value: _airFilled,
                  onChanged: (val) => setState(() => _airFilled = val),
                  activeThumbColor: Colors.deepPurple,
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      if (widget.initialEntry != null) {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Update Entry?'),
                            content: const Text('Are you sure you want to update this fuel entry?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('No'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Yes', style: TextStyle(color: Colors.deepPurple)),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                      }

                      final entry = FuelEntry(
                        date: DateFormat('yyyy-MM-dd').format(_selectedDate),
                        odometer: double.parse(_odoController.text),
                        rupees: double.parse(_rupeesController.text),
                        liters: _litersController.text.isEmpty ? null : double.parse(_litersController.text),
                        comments: _commentsController.text.trim().isEmpty ? null : _commentsController.text.trim(),
                        airFilled: _airFilled,
                      );
                      widget.onSave(entry);
                      Navigator.pop(context);
                    }
                  },
                  child: Text(widget.initialEntry == null ? 'Save Entry' : 'Update Entry', style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
