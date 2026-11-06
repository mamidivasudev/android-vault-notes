import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers.dart';

/// Shows "<message>  UNDO" and runs [onUndo] if tapped.
void showUndoSnackBar(ScaffoldMessengerState messenger, String message, Future<void> Function() onUndo) {
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
      // Snackbars with a button stay open forever by default; close after
      // the duration and offer an X to close at once.
      persist: false,
      showCloseIcon: true,
      action: SnackBarAction(label: 'UNDO', onPressed: () => onUndo()),
    ),
  );
}

/// Deletes bills (and their reminders) with an Undo that restores both.
void deleteBillsWithUndo(BuildContext context, WidgetRef ref, List<Bill> bills) {
  if (bills.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(billsProvider.notifier);
  notifier.deleteBills(bills.map((b) => b.id));
  showUndoSnackBar(
    messenger,
    bills.length == 1 ? '${bills.first.title} deleted' : '${bills.length} bills deleted',
    () => notifier.restoreBills(bills),
  );
}

/// Deletes reminders with an Undo that restores them (and their alerts).
void deleteRemindersWithUndo(BuildContext context, WidgetRef ref, List<Reminder> reminders) {
  if (reminders.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(remindersProvider.notifier);
  notifier.deleteReminders(reminders.map((r) => r.id).toList());
  showUndoSnackBar(
    messenger,
    reminders.length == 1 ? 'Reminder deleted' : '${reminders.length} reminders deleted',
    () => notifier.restoreReminders(reminders),
  );
}

/// Deletes a table with an Undo that puts it back.
void deleteTableWithUndo(BuildContext context, WidgetRef ref, VaultTable table) {
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(tablesProvider.notifier);
  notifier.deleteTable(table.id);
  showUndoSnackBar(
    messenger,
    'Table "${table.title.isEmpty ? 'Untitled' : table.title}" deleted',
    () => notifier.restoreTable(table),
  );
}

/// Deletes grocery items with an Undo that puts them back in place.
void deleteGroceryWithUndo(BuildContext context, WidgetRef ref, Set<String> ids) {
  if (ids.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(groceryProvider.notifier);
  final removed = ref.read(groceryProvider).where((i) => ids.contains(i.id)).toList();
  notifier.deleteMultiple(ids);
  showUndoSnackBar(
    messenger,
    removed.length == 1 ? '"${removed.first.name}" removed' : '${removed.length} items removed',
    () => notifier.restoreItems(removed),
  );
}
