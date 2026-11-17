import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notification_service.dart';
import '../widgets/top_toast.dart';
import 'extras_models.dart';
import 'extras_store.dart';
import 'extras_widgets.dart';
import '../utils/voice_parsers.dart';
import '../widgets/voice_mic.dart';

class MedicinesView extends ConsumerStatefulWidget {
  const MedicinesView({super.key});

  @override
  ConsumerState<MedicinesView> createState() => _MedicinesViewState();
}

class _MedicinesViewState extends ConsumerState<MedicinesView> {
  final Set<String> _selected = {};
  bool _selecting = false;

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  void _stopSelecting() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  /// "Dolo 650 at 8 AM and 9 PM" → the form, filled in, to check.
  Future<void> _byVoice() async {
    final words = await listenOnce(context, title: 'Medicine by voice', hint: 'e.g. "Dolo 650 at 8 AM and 9 PM"');
    if (words == null || !mounted) return;
    final p = parseSpokenMedicine(words);
    showMedicineEditor(context, ref, null, draft: Medicine(name: p.name, dose: p.dose, times: p.times));
  }

  Future<void> _deleteSelected(List<Medicine> all) async {
    if (_selected.isEmpty) {
      showTopToast(context, 'Tick the medicines to delete first', icon: Icons.info, color: kToastBlue);
      return;
    }
    final n = _selected.length;
    if (!await confirmYesNo(context, 'Delete?', 'Delete $n medicine${n == 1 ? '' : 's'} and their alerts?')) return;
    final removed = all.where((m) => _selected.contains(m.id)).toList();
    final notifier = ref.read(medicinesProvider.notifier);
    await notifier.deleteMany({..._selected});
    if (!mounted) return;
    _stopSelecting();
    showTopToast(context, '$n medicine${n == 1 ? '' : 's'} deleted',
        icon: Icons.delete, color: kToastRed, actionLabel: 'UNDO', onAction: () => notifier.restoreMany(removed));
  }

  @override
  Widget build(BuildContext context) {
    final meds = ref.watch(medicinesProvider);
    final scheme = Theme.of(context).colorScheme;
    final today = dayKey(DateTime.now());
    final doses = [
      for (final m in meds.where((m) => m.active))
        for (final t in m.times) (med: m, time: t),
    ]..sort((a, b) => a.time.compareTo(b.time));
    final takenCount = doses.where((d) => d.med.isTaken(today, d.time)).length;
    final allSelected = meds.isNotEmpty && _selected.length == meds.length;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopSelecting();
      },
      child: ExtrasScaffold(
        onAdd: () => showMedicineEditor(context, ref, null),
        onVoice: _byVoice,
        child: Column(
          children: [
            if (_selecting)
              Material(
                color: scheme.primary.withValues(alpha: 0.08),
                child: Row(
                  children: [
                    IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close), onPressed: _stopSelecting),
                    Expanded(child: Text('${_selected.length} selected', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                    IconButton(
                      tooltip: 'Select all',
                      icon: Icon(allSelected ? Icons.check_box : Icons.check_box_outline_blank),
                      onPressed: () => setState(() {
                        allSelected ? _selected.clear() : _selected.addAll(meds.map((m) => m.id));
                      }),
                    ),
                    IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteSelected(meds)),
                  ],
                ),
              ),
            Expanded(
              child: meds.isEmpty
                  ? const ExtrasEmpty(icon: Icons.medication_outlined, text: 'No medicines yet', hint: 'Tap + to add a medicine and its times')
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                      children: [
                        if (doses.isNotEmpty && !_selecting) ...[
                          ExtrasHeading('Today', trailing: '$takenCount of ${doses.length} taken'),
                          for (final d in doses)
                            Card(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              child: CheckboxListTile(
                                value: d.med.isTaken(today, d.time),
                                onChanged: (_) {
                                  HapticFeedback.selectionClick();
                                  ref.read(medicinesProvider.notifier).toggleTaken(d.med.id, today, d.time);
                                },
                                secondary: Text(formatTime(d.time), style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary)),
                                title: Text(
                                  d.med.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    decoration: d.med.isTaken(today, d.time) ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                subtitle: d.med.dose.isEmpty ? null : Text(d.med.dose),
                              ),
                            ),
                          const SizedBox(height: 12),
                        ],
                        const ExtrasHeading('All medicines'),
                        for (final m in meds)
                          Card(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            color: _selected.contains(m.id) ? scheme.primary.withValues(alpha: 0.15) : null,
                            child: ListTile(
                              onTap: () => _selecting ? _toggle(m.id) : showMedicineEditor(context, ref, m),
                              onLongPress: () => _selecting
                                  ? _toggle(m.id)
                                  : setState(() {
                                      _selecting = true;
                                      _selected.add(m.id);
                                    }),
                              leading: _selecting
                                  ? Checkbox(value: _selected.contains(m.id), onChanged: (_) => _toggle(m.id))
                                  : CircleAvatar(
                                      backgroundColor: (m.isLow ? Colors.red : scheme.primary).withValues(alpha: 0.12),
                                      child: Icon(Icons.medication, color: m.isLow ? Colors.red : scheme.primary),
                                    ),
                              title: Text(m.name, style: TextStyle(fontWeight: FontWeight.w600, color: m.active ? null : Colors.grey)),
                              subtitle: Text([
                                if (m.dose.isNotEmpty) m.dose,
                                if (m.times.isNotEmpty) m.times.map(formatTime).join(', ') else 'No times set',
                                if (!m.active) 'Paused',
                              ].join('  ·  ')),
                              trailing: m.stock == null
                                  ? null
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('${m.stock} left', style: TextStyle(fontWeight: FontWeight.w700, color: m.isLow ? Colors.red : null)),
                                        if (m.isLow) const Text('Low stock', style: TextStyle(color: Colors.red, fontSize: 11)),
                                      ],
                                    ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "08:00" → "8:00 AM".
String formatTime(String hhmm) {
  final p = hhmm.split(':');
  final h = int.tryParse(p[0]) ?? 0;
  final m = p.length > 1 ? p[1] : '00';
  return '${h % 12 == 0 ? 12 : h % 12}:$m ${h < 12 ? 'AM' : 'PM'}';
}

/// [draft] pre-fills a new medicine (from voice); it is still saved as new.
Future<void> showMedicineEditor(BuildContext context, WidgetRef ref, Medicine? med, {Medicine? draft}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MedicineEditor(med: med, draft: draft),
  );
}

class _MedicineEditor extends ConsumerStatefulWidget {
  final Medicine? med;
  final Medicine? draft;
  const _MedicineEditor({this.med, this.draft});

  @override
  ConsumerState<_MedicineEditor> createState() => _MedicineEditorState();
}

class _MedicineEditorState extends ConsumerState<_MedicineEditor> {
  Medicine? get _start => widget.med ?? widget.draft;
  late final _name = TextEditingController(text: _start?.name ?? '');
  late final _dose = TextEditingController(text: _start?.dose ?? '');
  late final _stock = TextEditingController(text: _start?.stock?.toString() ?? '');
  late final _perDose = TextEditingController(text: (_start?.perDose ?? 1).toString());
  late final _lowAt = TextEditingController(text: (_start?.lowStockAt ?? 5).toString());
  late final _notes = TextEditingController(text: _start?.notes ?? '');
  late List<String> _times = [...?_start?.times];
  late bool _active = widget.med?.active ?? true;

  @override
  void dispose() {
    for (final c in [_name, _dose, _stock, _perDose, _lowAt, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (picked == null) return;
    final t = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    if (!_times.contains(t)) setState(() => _times = [..._times, t]..sort());
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showTopToast(context, 'Enter the medicine name', icon: Icons.info, color: kToastBlue);
      return;
    }
    // Changing a saved medicine asks first.
    if (widget.med != null && !await confirmYesNo(context, 'Update?', 'Save the changes to $name?')) return;
    if (!mounted) return;
    final stock = int.tryParse(_stock.text.trim());
    final base = widget.med ?? Medicine(name: name);
    final med = base.copyWith(
      name: name,
      dose: _dose.text.trim(),
      times: _times,
      stock: stock,
      perDose: (int.tryParse(_perDose.text.trim()) ?? 1).clamp(1, 1000),
      lowStockAt: (int.tryParse(_lowAt.text.trim()) ?? 5).clamp(0, 100000),
      notes: _notes.text.trim(),
      active: _active,
    );
    if (_times.isNotEmpty) await NotificationService().requestPermissions();
    await ref.read(medicinesProvider.notifier).save(med);
    if (!mounted) return;
    showTopToast(context, widget.med == null ? '$name added' : '$name updated');
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final med = widget.med!;
    if (!await confirmYesNo(context, 'Delete?', 'Delete ${med.name} and its alerts?')) return;
    final notifier = ref.read(medicinesProvider.notifier);
    await notifier.delete(med.id);
    if (!mounted) return;
    showTopToast(context, '${med.name} deleted', icon: Icons.delete, color: kToastRed, actionLabel: 'UNDO', onAction: () => notifier.save(med));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const number = TextInputType.number;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return ExtrasSheet(
      title: widget.med == null ? 'New medicine' : 'Edit medicine',
      onSave: _save,
      saveLabel: widget.med == null ? 'Save' : 'Update',
      onDelete: widget.med == null ? null : _delete,
      children: [
        TextField(controller: _name, autofocus: widget.med == null, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Medicine name', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _dose, decoration: const InputDecoration(labelText: 'Dose (optional)', hintText: 'e.g. 1 tablet, 5 ml', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        const Text('Times', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in _times)
              InputChip(label: Text(formatTime(t)), onDeleted: () => setState(() => _times = [..._times]..remove(t))),
            ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Add time'), onPressed: _addTime),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: TextField(controller: _stock, keyboardType: number, inputFormatters: digits, decoration: const InputDecoration(labelText: 'Tablets left', hintText: 'optional', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _perDose, keyboardType: number, inputFormatters: digits, decoration: const InputDecoration(labelText: 'Per dose', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _lowAt, keyboardType: number, inputFormatters: digits, decoration: const InputDecoration(labelText: 'Warn at', border: OutlineInputBorder()))),
          ],
        ),
        const SizedBox(height: 12),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'e.g. after food', border: OutlineInputBorder())),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          subtitle: const Text('Turn off to pause its alerts'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
      ],
    );
  }
}
