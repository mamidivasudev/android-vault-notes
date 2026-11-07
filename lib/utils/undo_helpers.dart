import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers.dart';
import '../widgets/top_toast.dart';

/// Shows a red "<message>  UNDO" toast at the top and runs [onUndo] if tapped.
void showUndoSnackBar(ScaffoldMessengerState messenger, String message, Future<void> Function() onUndo) {
  messenger.hideCurrentSnackBar();
  showTopToast(
    messenger.context,
    message,
    icon: Icons.delete,
    color: kToastRed,
    actionLabel: 'UNDO',
    onAction: () => onUndo(),
  );
}

/// Deletes bills (and their reminders) with an Undo that restores both.
/// Asks Yes/No first unless [confirm] is false. Returns true if deleted.
Future<bool> deleteBillsWithUndo(BuildContext context, WidgetRef ref, List<Bill> bills, {bool confirm = true}) async {
  if (bills.isEmpty) return false;
  if (confirm &&
      !await confirmYesNo(context, 'Delete?',
          bills.length == 1 ? 'Delete "${bills.first.title}"?' : 'Delete ${bills.length} bills?')) {
    return false;
  }
  if (!context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(billsProvider.notifier);
  notifier.deleteBills(bills.map((b) => b.id));
  showUndoSnackBar(
    messenger,
    bills.length == 1 ? '${bills.first.title} deleted' : '${bills.length} bills deleted',
    () => notifier.restoreBills(bills),
  );
  return true;
}

/// Deletes reminders with an Undo that restores them (and their alerts).
Future<bool> deleteRemindersWithUndo(BuildContext context, WidgetRef ref, List<Reminder> reminders,
    {bool confirm = true}) async {
  if (reminders.isEmpty) return false;
  if (confirm &&
      !await confirmYesNo(context, 'Delete?',
          reminders.length == 1 ? 'Delete this reminder?' : 'Delete ${reminders.length} reminders?')) {
    return false;
  }
  if (!context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(remindersProvider.notifier);
  notifier.deleteReminders(reminders.map((r) => r.id).toList());
  showUndoSnackBar(
    messenger,
    reminders.length == 1 ? 'Reminder deleted' : '${reminders.length} reminders deleted',
    () => notifier.restoreReminders(reminders),
  );
  return true;
}

/// Deletes a table with an Undo that puts it back.
Future<bool> deleteTableWithUndo(BuildContext context, WidgetRef ref, VaultTable table, {bool confirm = true}) async {
  if (confirm &&
      !await confirmYesNo(context, 'Delete?', 'Delete table "${table.title.isEmpty ? 'Untitled' : table.title}"?')) {
    return false;
  }
  if (!context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(tablesProvider.notifier);
  notifier.deleteTable(table.id);
  showUndoSnackBar(
    messenger,
    'Table "${table.title.isEmpty ? 'Untitled' : table.title}" deleted',
    () => notifier.restoreTable(table),
  );
  return true;
}

/// Deletes grocery items with an Undo that puts them back in place.
Future<bool> deleteGroceryWithUndo(BuildContext context, WidgetRef ref, Set<String> ids, {bool confirm = true}) async {
  if (ids.isEmpty) return false;
  final notifier = ref.read(groceryProvider.notifier);
  final removed = ref.read(groceryProvider).where((i) => ids.contains(i.id)).toList();
  if (confirm &&
      !await confirmYesNo(context, 'Remove?',
          removed.length == 1 ? 'Remove ${removed.first.name} from your list?' : 'Remove ${removed.length} items?')) {
    return false;
  }
  if (!context.mounted) return false;
  notifier.deleteMultiple(ids);
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  showTopToast(
    context,
    removed.length == 1 ? '${removed.first.name} removed' : '${removed.length} items removed',
    icon: Icons.remove_circle,
    color: kToastRed,
    actionLabel: 'UNDO',
    onAction: () => notifier.restoreItems(removed),
  );
  return true;
}
