import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';


import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main_helpers.dart';
import '../models.dart';
import '../providers.dart';

// ---------- Mileage View ----------
class MileageView extends ConsumerStatefulWidget {
  final Future<void> Function()? onGlobalSync;
  const MileageView({super.key, this.onGlobalSync});

  @override
  ConsumerState<MileageView> createState() => _MileageViewState();
}

class _MileageViewState extends ConsumerState<MileageView> {
  bool _isServiceTab = false;
  late final PageController _pageController;
  bool _isSyncingLocal = false;
  static const _prefsKey = 'fuel_entries';
  static const _seededKey = 'fuel_seeded_v1';
  double? _lastServiceOdo;
  double? _nextServiceOdo;
  static const _tankKey = 'bike_tank_capacity';
  double _tankCapacity = 5.1;

  Future<void> _editTankCapacity() async {
    final controller = TextEditingController(text: _tankCapacity.toString());
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fuel tank capacity'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'L', helperText: 'Used for "petrol left before fill"'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim());
              if (v != null && v > 0) Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_tankKey, value);
    ref.read(vaultServiceProvider).exportAppSettings();
    if (mounted) setState(() => _tankCapacity = value);
  }
  bool _isLoading = true;



  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _seedAndLoad();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _seedAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadySeeded = prefs.getBool(_seededKey) ?? false;
    // Wait for the vault to load first: seeding must never replace existing
    // history (a fresh install pointed at an old vault used to wipe it).
    final fuelNotifier = ref.read(fuelEntriesProvider.notifier);
    await fuelNotifier.ready;
    if (!mounted) return;
    // Sample history used to be written into every new, empty vault. That put
    // someone else's fuel log into a fresh install, so it is no longer seeded.
    if (!alreadySeeded) await prefs.setBool(_seededKey, true);
    if (!mounted) return;

    setState(() {
      _lastServiceOdo = prefs.getDouble('last_service_odo');
      _nextServiceOdo = prefs.getDouble('next_service_odo');
      _tankCapacity = prefs.getDouble(_tankKey) ?? 5.1;
      _isLoading = false;
    });
  }

  Future<void> _confirmAndDeleteService(ServiceEntry entry) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Service?'),
        content: const Text('Are you sure you want to delete this service entry?'),
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
      ref.read(serviceEntriesProvider.notifier).deleteEntry(entry.id);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Service entry deleted'),
            // Snackbars with a button stay open forever by default; close after
            // the duration and offer an X to close at once.
            persist: false,
            showCloseIcon: true,
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => ref.read(serviceEntriesProvider.notifier).restoreEntry(entry),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
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
            // Snackbars with a button stay open forever by default; close after
            // the duration and offer an X to close at once.
            persist: false,
            showCloseIcon: true,
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                ref.read(fuelEntriesProvider.notifier).restoreEntry(entry);
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
  /// Distance between the lowest and highest recorded odometer readings
  /// (0 = not recorded, so those entries are ignored).
  double _totalKm(List<FuelEntry> entries) {
    final odo = entries.where((e) => e.hasOdometer).map((e) => e.odometer).toList();
    if (odo.length < 2) return 0;
    return odo.reduce((a, b) => a > b ? a : b) - odo.reduce((a, b) => a < b ? a : b);
  }

  double _totalCost(List<FuelEntry> entries) {
    return entries.fold(0.0, (sum, e) => sum + e.rupees);
  }

  /// Average mileage (km/l) using the full-tank method: between two full
  /// fills, distance travelled ÷ all litres added after the first one (partial
  /// top-ups included). Entries saved before the "full tank" flag existed count
  /// as full fills. Fills without an odometer reading can't start or end a
  /// segment, but their litres are still counted.
  double? _averageMileage(List<FuelEntry> entries) => averageMileage(entries);

  void _exportData(List<FuelEntry> fuel, List<ServiceEntry> service) {
    if (fuel.isEmpty && service.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data to export')));
      return;
    }
    
    final buffer = StringBuffer();
    buffer.writeln('Mileage & Service Export');
    buffer.writeln('======================\n');
    
    if (fuel.isNotEmpty) {
      buffer.writeln('FUEL HISTORY');
      buffer.writeln('------------');
      for (final entry in fuel.reversed) {
        buffer.writeln('Date: ${DateFormat('d MMM yyyy').format(_parseDate(entry.date))}');
        buffer.writeln('Odometer: ${entry.odometer.toStringAsFixed(1)} km');
        buffer.writeln('Amount Paid: ${entry.rupees.toStringAsFixed(0)} rs');
        if (entry.liters != null) buffer.writeln('Liters: ${entry.liters!.toStringAsFixed(2)} L');
        if (entry.airFilled) buffer.writeln('Air Filled: Yes');
        if (entry.comments != null && entry.comments!.isNotEmpty) buffer.writeln('Comments: ${entry.comments}');
        buffer.writeln();
      }
    }
    
    if (service.isNotEmpty) {
      buffer.writeln('SERVICE HISTORY');
      buffer.writeln('---------------');
      for (final entry in service.reversed) {
        buffer.writeln('Date: ${DateFormat('d MMM yyyy').format(_parseDate(entry.date))}');
        buffer.writeln('Odometer: ${entry.odometer.toStringAsFixed(0)} km');
        buffer.writeln('Cost: ${entry.cost.toStringAsFixed(0)} rs');
        if (entry.comments != null && entry.comments!.isNotEmpty) buffer.writeln('Comments: ${entry.comments}');
        buffer.writeln();
      }
    }
    
    if (fuel.isNotEmpty) {
      buffer.writeln('\nTotal Distance: ${_totalKm(fuel).toStringAsFixed(0)} km');
      buffer.writeln('Total Cost: ${_totalCost(fuel).toStringAsFixed(0)} rs');
      final avg = _averageMileage(fuel);
      if (avg != null) {
        buffer.writeln('Average Mileage: ${avg.toStringAsFixed(1)} km/l');
      }
    }
    
    Share.share(buffer.toString(), subject: 'Mileage Tracker Data Export');
  }

  Future<void> _backupData() async {
    try {
      final fuel = ref.read(fuelEntriesProvider);
      final service = ref.read(serviceEntriesProvider);
      final data = {
        'fuel': fuel.map((e) => e.toJson()).toList(),
        'service': service.map((e) => e.toJson()).toList(),
      };
      final raw = jsonEncode(data);
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
        final decoded = jsonDecode(raw);
        
        List<FuelEntry> importedFuel = [];
        List<ServiceEntry> importedService = [];
        
        if (decoded is List) {
          // Old format (only fuel)
          importedFuel = decoded.map((e) => FuelEntry.fromJson(e)).toList();
        } else if (decoded is Map) {
          // New format
          if (decoded['fuel'] != null) {
            importedFuel = (decoded['fuel'] as List).map((e) => FuelEntry.fromJson(e)).toList();
          }
          if (decoded['service'] != null) {
            importedService = (decoded['service'] as List).map((e) => ServiceEntry.fromJson(e)).toList();
          }
        }

        // Merge Fuel
        final currentFuel = ref.read(fuelEntriesProvider);
        final Map<String, FuelEntry> uniqueFuel = {};
        for (var e in currentFuel) { uniqueFuel['${e.date}_${e.odometer}'] = e; }
        for (var e in importedFuel) { uniqueFuel['${e.date}_${e.odometer}'] = e; }
        final mergedFuel = uniqueFuel.values.toList()..sort((a, b) => a.date.compareTo(b.date));
        ref.read(fuelEntriesProvider.notifier).setEntries(mergedFuel);

        // Merge Service
        if (importedService.isNotEmpty) {
          final currentService = ref.read(serviceEntriesProvider);
          final Map<String, ServiceEntry> uniqueService = {};
          for (var e in currentService) { uniqueService['${e.date}_${e.odometer}'] = e; }
          for (var e in importedService) { uniqueService['${e.date}_${e.odometer}'] = e; }
          final mergedService = uniqueService.values.toList()..sort((a, b) => a.date.compareTo(b.date));
          ref.read(serviceEntriesProvider.notifier).setEntries(mergedService);
        }

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data imported successfully')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
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

  List<Widget> _buildServiceList() {
    final services = ref.watch(serviceEntriesProvider);
    if (services.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: Center(child: Text('No service history found', style: TextStyle(color: Colors.white70))),
        )
      ];
    }
    return services.map((s) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1530),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: ListTile(
          onTap: () => _showAddServiceSheet(context, s),
          title: Text(DateFormat('d MMM yyyy').format(_parseDate(s.date)), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text('Service KM: ${s.odometer.toStringAsFixed(0)} km', style: const TextStyle(color: Colors.white70)),
              if (s.comments != null && s.comments!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(s.comments!, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
              ],
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${s.cost.toStringAsFixed(0)} rs', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _confirmAndDeleteService(s),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  void _showAddServiceSheet(BuildContext context, ServiceEntry? entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E2336),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => AddServiceSheet(
        initialEntry: entry,
        onSave: (newEntry) async {
          if (entry == null) {
            ref.read(serviceEntriesProvider.notifier).addEntry(newEntry);
          } else {
            ref.read(serviceEntriesProvider.notifier).updateEntry(newEntry);
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('last_service_odo', newEntry.odometer);
          await prefs.setDouble('next_service_odo', newEntry.nextServiceOdometer);
          setState(() {
            _lastServiceOdo = newEntry.odometer;
            _nextServiceOdo = newEntry.nextServiceOdometer;
          });
        },
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
    // Entries are kept sorted by date, so the first one is the purchase/start date.
    final purchaseDate = DateTime.tryParse(entries.first.date) ?? DateTime.now();
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
    
    return 'Purchased: ${DateFormat('MMM d, yyyy').format(purchaseDate)}\n$result';
  }

  String? _getAirFilledMessage(List<FuelEntry> entries) {
    try {
      final lastAirEntry = entries.lastWhere((e) => e.airFilled);
      final airDate = _parseDate(lastAirEntry.date);
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
    final withOdo = entries.where((e) => e.hasOdometer).toList();
    if (withOdo.isEmpty) return const SizedBox.shrink();
    final currentOdo = withOdo.last.odometer;
    final lastService = _lastServiceOdo;
    final nextService = _nextServiceOdo;
    if (lastService == null || nextService == null) {
      if (_isLoading) return const SizedBox.shrink();
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
            Builder(
              builder: (context) {
                return IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: (_isSyncingLocal || ref.watch(localSyncingProvider))
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync, color: Colors.white),
                  onPressed: _isSyncingLocal
                    ? null 
                    : () {
                        verifyPasscode(context, ref, onSuccess: () async {
                          setState(() => _isSyncingLocal = true);
                          try {
                            if (widget.onGlobalSync != null) {
                              await widget.onGlobalSync!();
                              await Future.delayed(const Duration(seconds: 1));
                            }
                          } catch(e) {}
                          if (mounted) setState(() => _isSyncingLocal = false);
                        });
                      },
                  tooltip: _isSyncingLocal ? 'Syncing Local...' : 'Sync Local',
                );
              },
            ),
            PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'settings') {
                _openSettings();
              } else if (value == 'share') _exportData(entries, ref.read(serviceEntriesProvider));
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
                  Container(
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _isServiceTab = false);
                                _pageController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: !_isServiceTab ? Colors.deepPurple : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: const Text('Fuel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _isServiceTab = true);
                                _pageController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _isServiceTab ? Colors.deepPurple : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: const Text('Service', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ),
          Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _isServiceTab = index == 1;
                  });
                },
                children: [
                  ListView(
                    padding: const EdgeInsets.only(bottom: 100),
                    children: [
                      for (final month in grouped.keys)
                        _MonthSection(
                          month: month,
                          entries: grouped[month]!,
                          tankCapacity: _tankCapacity,
                          onEditTank: _editTankCapacity,
                          onDelete: (entry) {
                            _confirmAndDelete(entry);
                          },
                          onEdit: (entry) {
                            _openEntrySheet(entryToEdit: entry);
                          },
                        ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.only(bottom: 100),
                    children: _buildServiceList(),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_isServiceTab) {
            _showAddServiceSheet(context, null);
          } else {
            _openEntrySheet();
          }
        },
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(_isServiceTab ? 'Add Service' : 'Add Fuel'),
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
      final d = _parseDate(e.date);
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
  final double tankCapacity;
  final VoidCallback onEditTank;

  const _MonthSection({
    required this.month,
    required this.entries,
    required this.tankCapacity,
    required this.onEditTank,
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
              title: Text(DateFormat('d MMM yyyy').format(_parseDate(entries[i].date)), style: const TextStyle(color: Colors.white)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('Odometer : ${entries[i].odometer.toStringAsFixed(0)} km', style: const TextStyle(color: Colors.white70)),
                  if (entries[i].liters != null) Text('Liters filled : ${entries[i].liters!.toStringAsFixed(2)} L', style: const TextStyle(color: Colors.white70)),
                  if (entries[i].isFullTank == false)
                    const Text('Partial fill', style: TextStyle(color: Colors.orangeAccent)),
                  // Only meaningful for a fill to the brim: tank size − litres added.
                  if (entries[i].liters != null && entries[i].isFullTank != false)
                    GestureDetector(
                      onTap: onEditTank,
                      child: Text(
                        'Petrol left before fill : ${(tankCapacity - entries[i].liters!).clamp(0, tankCapacity).toStringAsFixed(2)} L'
                        ' (tank ${tankCapacity.toStringAsFixed(1)} L ✎)',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    ),
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
  bool _fullTank = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialEntry != null) {
      final entry = widget.initialEntry!;
      _selectedDate = _parseDate(entry.date);
      _odoController.text = entry.odometer.toString();
      _rupeesController.text = entry.rupees.toString();
      if (entry.liters != null) _litersController.text = entry.liters.toString();
      if (entry.comments != null) _commentsController.text = entry.comments!;
      _airFilled = entry.airFilled;
      _fullTank = entry.isFullTank ?? true;
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
                  validator: (v) => _parseNum(v) == null ? 'Enter odometer km' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _rupeesController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount paid (rs)'),
                  style: const TextStyle(color: Colors.white),
                  validator: (v) => _parseNum(v) == null ? 'Enter amount' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _litersController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Liters filled (optional, only if full tank)',
                  ),
                  style: const TextStyle(color: Colors.white),
                  validator: (v) => (v != null && v.trim().isNotEmpty && _parseNum(v) == null) ? 'Enter a valid number' : null,
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
                  title: const Text('Full tank', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Turn off for a partial top-up (keeps mileage accurate)',
                      style: TextStyle(color: Colors.white54, fontSize: 11)),
                  value: _fullTank,
                  onChanged: (val) => setState(() => _fullTank = val),
                  activeThumbColor: Colors.deepPurple,
                ),
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
                        odometer: _parseNum(_odoController.text)!,
                        rupees: _parseNum(_rupeesController.text)!,
                        liters: _litersController.text.trim().isEmpty ? null : _parseNum(_litersController.text),
                        comments: _commentsController.text.trim().isEmpty ? null : _commentsController.text.trim(),
                        airFilled: _airFilled,
                        isFullTank: _litersController.text.trim().isEmpty ? null : _fullTank,
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


// ---------- Add Service Sheet ----------
class AddServiceSheet extends StatefulWidget {
  final void Function(ServiceEntry) onSave;
  final ServiceEntry? initialEntry;
  
  const AddServiceSheet({super.key, required this.onSave, this.initialEntry});

  @override
  State<AddServiceSheet> createState() => _AddServiceSheetState();
}

class _AddServiceSheetState extends State<AddServiceSheet> {
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  final _odoController = TextEditingController();
  final _costController = TextEditingController();
  final _nextOdoController = TextEditingController();
  final _commentsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialEntry != null) {
      final entry = widget.initialEntry!;
      _selectedDate = _parseDate(entry.date);
      _odoController.text = entry.odometer.toString();
      _costController.text = entry.cost.toString();
      _nextOdoController.text = entry.nextServiceOdometer.toString();
      if (entry.comments != null) _commentsController.text = entry.comments!;
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
                Text(widget.initialEntry == null ? 'Add Service' : 'Edit Service', 
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
                  decoration: const InputDecoration(labelText: 'Service Odometer (km)'),
                  style: const TextStyle(color: Colors.white),
                  validator: (v) => _parseNum(v) == null ? 'Enter service km' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _nextOdoController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Next Due Odometer (km)'),
                  style: const TextStyle(color: Colors.white),
                  validator: (v) => _parseNum(v) == null ? 'Enter next due km' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _costController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount paid (rs)'),
                  style: const TextStyle(color: Colors.white),
                  validator: (v) => _parseNum(v) == null ? 'Enter amount' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _commentsController,
                  decoration: const InputDecoration(labelText: 'Comments (what was done)'),
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      final entry = ServiceEntry(
                        id: widget.initialEntry?.id ?? const Uuid().v4(),
                        date: DateFormat('yyyy-MM-dd').format(_selectedDate),
                        odometer: _parseNum(_odoController.text)!,
                        cost: _parseNum(_costController.text)!,
                        nextServiceOdometer: _parseNum(_nextOdoController.text)!,
                        comments: _commentsController.text.trim().isEmpty ? null : _commentsController.text.trim(),
                      );
                      widget.onSave(entry);
                      Navigator.pop(context);
                    }
                  },
                  child: Text(widget.initialEntry == null ? 'Save Service' : 'Update Service', style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Parses a user-typed number, accepting thousands separators ("1,250.5").
double? _parseNum(String? v) {
  if (v == null) return null;
  final cleaned = v.replaceAll(',', '').trim();
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// Parses a stored yyyy-MM-dd date; malformed values fall back to today
/// instead of crashing the whole Mileage tab.
DateTime _parseDate(String value) => DateTime.tryParse(value) ?? DateTime.now();

/// See [_MileageViewState._averageMileage]. Top-level so it can be unit tested.
double? averageMileage(List<FuelEntry> entries) {
  double distance = 0, litres = 0, pending = 0;
  FuelEntry? lastFull;
  for (final e in entries) {
    final l = e.liters;
    if (l == null || l <= 0) continue;
    if (!e.hasOdometer) {
      if (lastFull != null) pending += l;
      continue;
    }
    final isFull = e.isFullTank ?? true;
    if (lastFull == null) {
      if (isFull) lastFull = e;
      continue;
    }
    pending += l;
    if (isFull) {
      final d = e.odometer - lastFull.odometer;
      if (d > 0) {
        distance += d;
        litres += pending;
      }
      lastFull = e;
      pending = 0;
    }
  }
  return litres > 0 ? distance / litres : null;
}
