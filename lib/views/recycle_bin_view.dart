import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../providers.dart';
import '../widgets/empty_state.dart';

class RecycleBinView extends ConsumerStatefulWidget {
  const RecycleBinView({super.key});

  @override
  ConsumerState<RecycleBinView> createState() => _RecycleBinViewState();
}

class _RecycleBinViewState extends ConsumerState<RecycleBinView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deletedNotes = ref.watch(deletedNotesProvider);
    final deletedExps = ref.watch(deletedExpensesProvider);
    final deletedLinks = ref.watch(deletedLinksProvider);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.05),
            border: Border(bottom: BorderSide(color: Colors.red.withOpacity(0.1))),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (_tabController.index == 0) {
                      _restoreAllNotes();
                    } else if (_tabController.index == 1) _restoreAllExpenses();
                    else _restoreAllLinks();
                  },
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Restore All'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1D63D2),
                    side: const BorderSide(color: Color(0xFF1D63D2)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (_tabController.index == 0) {
                      _emptyNotesBin();
                    } else if (_tabController.index == 1) _emptyExpensesBin();
                    else _emptyLinksBin();
                  },
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: const Text('Empty Bin'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF1D63D2),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF1D63D2),
          tabs: const [
            Tab(text: 'Notes'),
            Tab(text: 'Expenses'),
            Tab(text: 'Links'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDeletedNotesList(deletedNotes),
              _buildDeletedExpensesList(deletedExps),
              _buildDeletedLinksList(deletedLinks),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeletedNotesList(List<Note> notes) {
    if (notes.isEmpty) {
      return const EmptyState(
        icon: Icons.delete_outline,
        title: 'Notes Bin is Empty',
        subtitle: 'Deleted notes will appear here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ListTile(
            title: Text(note.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Category: ${note.category}'),
            trailing: _buildOptions(note: note),
          ),
        );
      },
    );
  }

  Widget _buildDeletedExpensesList(List<Expense> exps) {
    if (exps.isEmpty) {
      return const EmptyState(
        icon: Icons.delete_outline,
        title: 'Expenses Bin is Empty',
        subtitle: 'Deleted expenses will appear here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: exps.length,
      itemBuilder: (context, index) {
        final exp = exps[index];
        final currencyFormatter = NumberFormat.decimalPattern('en_IN');
        return Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ListTile(
            title: Text(exp.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('₹${currencyFormatter.format(exp.amount)} - ${exp.category}'),
            trailing: _buildOptions(expense: exp),
          ),
        );
      },
    );
  }

  Widget _buildDeletedLinksList(List<LinkItem> links) {
    if (links.isEmpty) {
      return const EmptyState(
        icon: Icons.delete_outline,
        title: 'Links Bin is Empty',
        subtitle: 'Deleted links will appear here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: links.length,
      itemBuilder: (context, index) {
        final link = links[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ListTile(
            title: Text(link.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(link.url, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: _buildOptions(link: link),
          ),
        );
      },
    );
  }

  Widget _buildOptions({Note? note, Expense? expense, LinkItem? link}) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.grey),
      onSelected: (val) {
        if (val == 'restore') {
          if (note != null) ref.read(deletedNotesProvider.notifier).restoreNote(note.id);
          if (expense != null) ref.read(deletedExpensesProvider.notifier).restoreExpense(expense.id);
          if (link != null) ref.read(deletedLinksProvider.notifier).restoreLink(link.id);
        } else if (val == 'delete') {
          if (note != null) ref.read(deletedNotesProvider.notifier).deletePermanently(note.id);
          if (expense != null) ref.read(deletedExpensesProvider.notifier).deletePermanently(expense.id);
          if (link != null) ref.read(deletedLinksProvider.notifier).deletePermanently(link.id);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'restore', 
          child: ListTile(leading: Icon(Icons.restore, size: 20), title: Text('Restore'), dense: true, contentPadding: EdgeInsets.zero),
        ),
        const PopupMenuItem(
          value: 'delete', 
          child: ListTile(leading: Icon(Icons.delete_forever, color: Colors.red, size: 20), title: Text('Delete Permanently', style: TextStyle(color: Colors.red)), dense: true, contentPadding: EdgeInsets.zero),
        ),
      ],
    );
  }

  void _restoreAllNotes() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore All Notes?'),
        content: const Text('This will restore all notes from the Recycle Bin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(deletedNotesProvider.notifier).restoreAll();
              Navigator.pop(context);
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  void _restoreAllExpenses() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore All Expenses?'),
        content: const Text('This will restore all expenses from the Recycle Bin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(deletedExpensesProvider.notifier).restoreAll();
              Navigator.pop(context);
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  void _restoreAllLinks() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore All Links?'),
        content: const Text('This will restore all links from the Recycle Bin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(deletedLinksProvider.notifier).restoreAll();
              Navigator.pop(context);
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  void _emptyNotesBin() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty Notes Bin?'),
        content: const Text('Are you sure? This will permanently delete all notes in the Recycle Bin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(deletedNotesProvider.notifier).deleteAll();
              Navigator.pop(context);
            },
            child: const Text('Empty Permanently', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _emptyExpensesBin() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty Expenses Bin?'),
        content: const Text('Are you sure? This will permanently delete all expenses in the Recycle Bin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(deletedExpensesProvider.notifier).deleteAll();
              Navigator.pop(context);
            },
            child: const Text('Empty Permanently', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _emptyLinksBin() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty Links Bin?'),
        content: const Text('Are you sure? This will permanently delete all links in the Recycle Bin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(deletedLinksProvider.notifier).deleteAll();
              Navigator.pop(context);
            },
            child: const Text('Empty Permanently', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
