import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../providers.dart';
import '../profiles/providers/theme_provider.dart';
import '../widgets/empty_state.dart';

class RemindersView extends ConsumerStatefulWidget {
  const RemindersView({super.key});

  @override
  ConsumerState<RemindersView> createState() => _RemindersViewState();
}

class _RemindersViewState extends ConsumerState<RemindersView> {
  @override
  Widget build(BuildContext context) {
    final reminders = ref.watch(remindersProvider);
    final selectedReminders = ref.watch(selectedRemindersProvider);
    final isSelectionMode = selectedReminders.isNotEmpty;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    final now = DateTime.now();
    
    // Active: not dismissed
    final active = reminders.where((r) => !r.isDismissed).toList();
    
    // History: dismissed
    final history = reminders.where((r) => r.isDismissed).toList();

    // Sort active by reminder time ascending (soonest first)
    active.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    
    // Sort history by reminder time descending (most recent first)
    history.sort((a, b) => b.dateTime.compareTo(a.dateTime));

    if (reminders.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: EmptyState(
          icon: Icons.notifications_active_outlined,
          title: 'No Reminders Set',
          subtitle: 'Create reminders to get notified at specific times.',
          actionLabel: 'Add Reminder',
          onAction: () => _showAddEditReminderDialog(context),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddEditReminderDialog(context),
          backgroundColor: const Color(0xFF1D63D2),
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          if (active.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
              child: Text(
                'Active & Upcoming',
                style: GoogleFonts.lexend(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: const Color(0xFF1D63D2),
                ),
              ),
            ),
            ...active.map((reminder) => _buildReminderCard(
                  reminder,
                  true,
                  isDark,
                  selectedReminders.contains(reminder.id),
                  isSelectionMode,
                )),
            const SizedBox(height: 16),
          ],
          if (history.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                'History & Dismissed',
                style: GoogleFonts.lexend(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            ...history.map((reminder) => _buildReminderCard(
                  reminder,
                  false,
                  isDark,
                  selectedReminders.contains(reminder.id),
                  isSelectionMode,
                )),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditReminderDialog(context),
        backgroundColor: const Color(0xFF1D63D2),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildReminderCard(
    Reminder reminder,
    bool isActive,
    bool isDark,
    bool isSelected,
    bool isSelectionMode,
  ) {
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(reminder.dateTime);
    final hasPassed = reminder.dateTime.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? const Color(0xFF1D63D2)
              : (isActive 
                  ? (hasPassed ? Colors.red.withOpacity(0.4) : const Color(0xFF1D63D2).withOpacity(0.2))
                  : (isDark ? Colors.white10 : Colors.black12)),
          width: isSelected ? 2.0 : (isActive ? 1.5 : 1.0),
        ),
      ),
      elevation: 0,
      color: isDark 
          ? (isActive 
              ? (hasPassed ? Colors.red.withOpacity(0.12) : const Color(0xFF0F172A)) 
              : const Color(0xFF0D1117))
          : (isActive 
              ? (hasPassed ? Colors.red.withOpacity(0.05) : const Color(0xFFF1F5F9)) 
              : Colors.white),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (isSelectionMode) {
            ref.read(selectedRemindersProvider.notifier).toggle(reminder.id);
          } else {
            _showAddEditReminderDialog(context, reminder: reminder);
          }
        },
        onLongPress: () {
          ref.read(selectedRemindersProvider.notifier).toggle(reminder.id);
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12, top: 4),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (val) {
                        ref.read(selectedRemindersProvider.notifier).toggle(reminder.id);
                      },
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                )
              else
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    isActive
                        ? (hasPassed ? Icons.warning_amber_rounded : Icons.alarm)
                        : Icons.check_circle_outline,
                    color: isActive
                        ? (hasPassed ? Colors.red : const Color(0xFF1D63D2))
                        : Colors.grey,
                    size: 24,
                  ),
                  onPressed: () {
                    ref.read(remindersProvider.notifier).updateReminder(
                          reminder.copyWith(isDismissed: !reminder.isDismissed),
                        );
                  },
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                        decoration: isActive ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    if (reminder.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        reminder.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white70 : Colors.black54,
                          decoration: isActive ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_filled_rounded,
                          size: 14,
                          color: isActive 
                              ? (hasPassed ? Colors.red : const Color(0xFF1D63D2))
                              : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formattedDate,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isActive 
                                ? (hasPassed ? Colors.red : const Color(0xFF1D63D2))
                                : Colors.grey,
                          ),
                        ),
                        if (isActive && hasPassed) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.red.withOpacity(0.2)
                                  : Colors.red.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'OVERDUE',
                              style: TextStyle(
                                color: isDark ? Colors.red.shade300 : Colors.red.shade900,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (!isSelectionMode)
                Column(
                  children: [
                    if (isActive && hasPassed) ...[
                      IconButton(
                        icon: const Icon(Icons.snooze, size: 20, color: Colors.orange),
                        onPressed: () => _showSnoozeSheet(context, reminder),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4.0),
                        tooltip: 'Snooze',
                      ),
                      const SizedBox(height: 4),
                    ],
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _showAddEditReminderDialog(context, reminder: reminder),
                      color: isDark ? Colors.white70 : Colors.black54,
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4.0),
                    ),
                    const SizedBox(height: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Reminder?'),
                            content: const Text('Are you sure you want to permanently delete this reminder?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  ref.read(remindersProvider.notifier).deleteReminder(reminder.id);
                                  Navigator.pop(context);
                                },
                                child: const Text('Delete', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                      },
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4.0),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddEditReminderDialog(BuildContext context, {Reminder? reminder}) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => ReminderDialog(reminder: reminder),
    );
  }

  void _showSnoozeSheet(BuildContext context, Reminder reminder) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Snooze until…',
                      style: GoogleFonts.lexend(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                _snoozeOption(sheetCtx, reminder, 'Snooze 10 min', const Duration(minutes: 10)),
                _snoozeOption(sheetCtx, reminder, 'Snooze 30 min', const Duration(minutes: 30)),
                _snoozeOption(sheetCtx, reminder, 'Snooze 1 hour', const Duration(hours: 1)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _snoozeOption(BuildContext sheetCtx, Reminder reminder, String label, Duration duration) {
    return ListTile(
      leading: const Icon(Icons.snooze, color: Colors.orange),
      title: Text(label),
      onTap: () {
        Navigator.pop(sheetCtx);
        ref.read(remindersProvider.notifier).updateReminder(
          reminder.copyWith(
            dateTime: DateTime.now().add(duration),
            isDismissed: false,
          ),
        );
      },
    );
  }
}

class ReminderDialog extends ConsumerStatefulWidget {
  final Reminder? reminder;
  const ReminderDialog({super.key, this.reminder});

  @override
  ConsumerState<ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends ConsumerState<ReminderDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late DateTime _selectedDateTime;
  late String _repeatType;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.reminder?.title ?? '');
    _descController = TextEditingController(text: widget.reminder?.description ?? '');
    _selectedDateTime = widget.reminder?.dateTime ?? DateTime.now().add(const Duration(minutes: 5));
    _repeatType = widget.reminder?.repeatType ?? 'none';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null) return;

    if (!mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (time == null) return;

    setState(() {
      _selectedDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.reminder != null;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      title: Row(
        children: [
          Icon(
            isEdit ? Icons.edit_calendar_rounded : Icons.add_alarm_rounded,
            color: const Color(0xFF1D63D2),
          ),
          const SizedBox(width: 10),
          Text(
            isEdit ? 'Edit Reminder' : 'Add Reminder',
            style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Name / Title',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDateTime,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: isDark ? Colors.white30 : Colors.black38),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, color: Color(0xFF1D63D2)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Date & Time',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('dd MMMM yyyy, hh:mm a').format(_selectedDateTime),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Repeat',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final type in ['none', 'daily', 'weekly', 'monthly'])
                        ChoiceChip(
                          label: Text(
                            type == 'none' ? 'None' : type[0].toUpperCase() + type.substring(1),
                          ),
                          selected: _repeatType == type,
                          onSelected: (_) => setState(() => _repeatType = type),
                          selectedColor: const Color(0xFF1D63D2),
                          labelStyle: TextStyle(
                            color: _repeatType == type ? Colors.white : null,
                            fontWeight: _repeatType == type ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() == true) {
              final newReminder = Reminder(
                id: widget.reminder?.id,
                title: _titleController.text.trim(),
                description: _descController.text.trim(),
                dateTime: _selectedDateTime,
                isDismissed: false,
                createdAt: widget.reminder?.createdAt,
                repeatType: _repeatType,
              );
              if (isEdit) {
                ref.read(remindersProvider.notifier).updateReminder(newReminder);
              } else {
                ref.read(remindersProvider.notifier).addReminder(newReminder);
              }
              Navigator.pop(context);
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1D63D2),
          ),
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
