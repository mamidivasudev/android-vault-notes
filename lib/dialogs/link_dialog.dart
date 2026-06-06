import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';

class LinkDialog extends ConsumerStatefulWidget {
  final LinkItem? link;
  final String? initialCategory;
  final String? initialTitle;
  final String? initialUrl;
  final bool isSharing;

  const LinkDialog({
    super.key, 
    this.link, 
    this.initialCategory,
    this.initialTitle,
    this.initialUrl,
    this.isSharing = false,
  });

  @override
  ConsumerState<LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends ConsumerState<LinkDialog> {
  final _titleController = TextEditingController();
  final _urlController = TextEditingController();
  final _titleFocusNode = FocusNode();
  late String _selectedCategory;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.link?.category ?? widget.initialCategory ?? 'All';
    if (_selectedCategory == 'General') _selectedCategory = 'All';
    
    if (widget.link != null) {
      _titleController.text = widget.link!.title;
      _urlController.text = widget.link!.url;
    } else {
      if (widget.initialTitle != null) _titleController.text = widget.initialTitle!;
      if (widget.initialUrl != null) _urlController.text = widget.initialUrl!;
    }

    if (widget.link == null) {
      if (_titleController.text == 'Shared Link') {
        _titleController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _titleController.text.length,
        );
      }
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _titleFocusNode.requestFocus();
          SystemChannels.textInput.invokeMethod('TextInput.show');
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = [
      'All',
      ...ref.watch(linkCategoriesProvider).where((c) => c != 'All' && c != 'General'),
    ];

    return AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            widget.link == null ? (widget.isSharing ? 'Save Shared Link' : 'Add Link') : 'Edit Link',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Icon(Icons.link, color: Color(0xFF1D63D2), size: 24),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              focusNode: _titleFocusNode,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. My Favorite Song',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: true,
                suffixIcon: _titleController.text.isNotEmpty 
                  ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _titleController.clear())) 
                  : null,
              ),
              autofocus: false,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _urlController,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'URL',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: true,
                suffixIcon: _urlController.text.isNotEmpty 
                  ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _urlController.clear())) 
                  : null,
              ),
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _handleSave(),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text('Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54)),
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  final isSelected = cat == _selectedCategory;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(cat, style: const TextStyle(fontSize: 10)),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _selectedCategory = cat);
                      },
                      padding: EdgeInsets.zero,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ),
        FilledButton(
          onPressed: _handleSave,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1D63D2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(widget.link == null ? 'Save Link' : 'Update Link'),
        ),
      ],
    );
  }

  void _handleSave() {
    final title = _titleController.text.trim();
    final url = _urlController.text.trim();

    if (title.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    if (!url.contains('.') || (!url.startsWith('http') && !url.startsWith('www'))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid URL')));
      return;
    }

    final linkItem = LinkItem(
      id: widget.link?.id,
      title: title,
      url: url.startsWith('http') ? url : 'https://$url',
      category: _selectedCategory,
      createdAt: widget.link?.createdAt,
    );

    if (widget.link == null) {
      ref.read(linkItemsProvider.notifier).addLink(linkItem);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link Added')));
    } else {
      final hasChanges = linkItem.title != widget.link!.title ||
          linkItem.url != widget.link!.url ||
          linkItem.category != widget.link!.category;

      if (!hasChanges) {
        Navigator.pop(context);
        return;
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Update Link?'),
          content: const Text('Do you want to save the changes to this link?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('No')),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ref.read(linkItemsProvider.notifier).updateLink(linkItem);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link Updated')));
              },
              child: const Text('Yes'),
            ),
          ],
        ),
      );
    }
  }
}
