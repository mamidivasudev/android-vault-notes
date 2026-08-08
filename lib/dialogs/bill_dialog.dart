import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../notification_service.dart';
import 'package:intl/intl.dart';
class BillDialog extends ConsumerStatefulWidget {
  final Bill? bill;
  const BillDialog({super.key, this.bill});

  @override
  ConsumerState<BillDialog> createState() => _BillDialogState();
}

class _BillDialogState extends ConsumerState<BillDialog> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _totalLoanAmountController = TextEditingController();
  final _totalEmisController = TextEditingController();
  final _paidEmisController = TextEditingController();
  final _titleFocusNode = FocusNode();
  int _dueDay = 1;
  String _type = 'Credit Card';
  List<int> _reminderDaysList = [2];
  TimeOfDay _reminderTime = const TimeOfDay(hour: 9, minute: 0);
  bool _reminderEnabled = true;

  @override
  void initState() {
    super.initState();
    if (widget.bill != null) {
      _titleController.text = widget.bill!.title;
      _amountController.text = widget.bill!.amount > 0 ? NumberFormat.decimalPattern('en_IN').format(widget.bill!.amount) : '';
      _noteController.text = widget.bill!.note ?? '';
      _totalLoanAmountController.text = widget.bill!.totalLoanAmount != null ? NumberFormat.decimalPattern('en_IN').format(widget.bill!.totalLoanAmount!) : '';
      _totalEmisController.text = widget.bill!.totalEmis != null ? widget.bill!.totalEmis.toString() : '';
      _paidEmisController.text = widget.bill!.paidEmis != null ? widget.bill!.paidEmis.toString() : '';
      _dueDay = widget.bill!.dueDate;
      _type = widget.bill!.type ?? 'Credit Card';
      _reminderDaysList = List<int>.from(widget.bill!.reminderDaysBeforeList);
      _reminderTime = TimeOfDay(hour: widget.bill!.reminderHour, minute: widget.bill!.reminderMinute);
      _reminderEnabled = widget.bill!.reminderEnabled;
    } else {
      _dueDay = DateTime.now().day;
      _type = 'Credit Card';
      _reminderDaysList = [2];
      _reminderEnabled = true;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _totalLoanAmountController.dispose();
    _totalEmisController.dispose();
    _paidEmisController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            widget.bill == null ? 'Add Bill / Loan' : 'Edit Bill',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              TextField(
                controller: _titleController,
                focusNode: _titleFocusNode,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Bill Name (e.g. HDFC Card)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.title, size: 16),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 7),
              TextField(
                controller: _amountController,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                decoration: InputDecoration(
                  labelText: 'Amount (Optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.currency_rupee, size: 16),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  IndianThousandsFormatter(),
                ],
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  const Text('Type:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(width: 10),
                  ChoiceChip(
                    label: const Text('Credit Card', style: TextStyle(fontSize: 11)),
                    selected: _type == 'Credit Card',
                    onSelected: (val) { if (val) setState(() => _type = 'Credit Card'); },
                    selectedColor: const Color(0xFF1D63D2).withOpacity(0.2),
                    labelStyle: TextStyle(
                      color: _type == 'Credit Card' ? const Color(0xFF1D63D2) : Colors.black87,
                      fontWeight: _type == 'Credit Card' ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Loan', style: TextStyle(fontSize: 11)),
                    selected: _type == 'Loan',
                    onSelected: (val) { if (val) setState(() => _type = 'Loan'); },
                    selectedColor: const Color(0xFF1D63D2).withOpacity(0.2),
                    labelStyle: TextStyle(
                      color: _type == 'Loan' ? const Color(0xFF1D63D2) : Colors.black87,
                      fontWeight: _type == 'Loan' ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              if (_type == 'Loan') ...[
                TextField(
                  controller: _totalLoanAmountController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Total Loan Amount (Optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.account_balance, size: 16),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    IndianThousandsFormatter(),
                  ],
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _totalEmisController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Total EMIs',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.date_range, size: 16),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: TextField(
                        controller: _paidEmisController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Paid EMIs',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.check_circle_outline, size: 16),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
              ],
              TextField(
                controller: _noteController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Notes (Optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.note, size: 16),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                style: const TextStyle(fontSize: 13),
                maxLines: null,
              ),
              const SizedBox(height: 8),
              const Text('Due Date (Day of Month)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
              const SizedBox(height: 4),
              SizedBox(
                height: 34,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 31,
                  itemBuilder: (context, index) {
                    final day = index + 1;
                    final isSelected = day == _dueDay;
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChoiceChip(
                        label: Text(day.toString(), style: const TextStyle(fontSize: 11)),
                        selected: isSelected,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        onSelected: (val) {
                          if (val) setState(() => _dueDay = day);
                        },
                        selectedColor: const Color(0xFF1D63D2).withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: isSelected ? const Color(0xFF1D63D2) : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Text('Remind before due date (Select up to 3)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
              const SizedBox(height: 4),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [0, 1, 2, 3, 4, 5, 7, 10, 12, 15].map((days) {
                    final isSelected = _reminderDaysList.contains(days);
                    final label = days == 0 ? "Due Day" : '$days ${days == 1 ? "day" : "days"}';
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChoiceChip(
                        label: Text(label, style: const TextStyle(fontSize: 11)),
                        selected: isSelected,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              if (_reminderDaysList.length >= 3) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Maximum 3 reminder days allowed'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                                return;
                              }
                              _reminderDaysList.add(days);
                            } else {
                              _reminderDaysList.remove(days);
                            }
                          });
                        },
                        selectedColor: const Color(0xFF1D63D2).withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: isSelected ? const Color(0xFF1D63D2) : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Reminder Time:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () async {
                      FocusScope.of(context).unfocus();
                      await Future.delayed(const Duration(milliseconds: 200));
                      if (!mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _reminderTime,
                      );
                      if (time != null) setState(() => _reminderTime = time);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF1D63D2).withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFF1D63D2).withOpacity(0.07),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time, size: 15, color: Color(0xFF1D63D2)),
                          const SizedBox(width: 6),
                          Text(
                            _reminderTime.format(context),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1D63D2)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
            ],
          ),
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(widget.bill == null ? 'Add Bill' : 'Update Bill'),
        ),
      ],
    );
  }

  Future<void> _handleSave() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a bill name'), duration: Duration(milliseconds: 1500)));
      return;
    }

    final amountStr = _amountController.text.trim().replaceAll(',', '');
    double amount = 0.0;
    if (amountStr.isNotEmpty) {
      amount = double.tryParse(amountStr) ?? 0.0;
    }

    if (_reminderEnabled && _reminderDaysList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least 1 reminder day'), duration: Duration(milliseconds: 1500)));
      return;
    }

    final newBill = Bill(
      id: widget.bill?.id,
      title: title,
      amount: amount,
      dueDate: _dueDay,
      reminderDaysBefore: _reminderDaysList.isNotEmpty ? _reminderDaysList.first : 2,
      reminderDaysBeforeList: _reminderDaysList,
      reminderHour: _reminderTime.hour,
      reminderMinute: _reminderTime.minute,
      isPaid: widget.bill?.isPaid ?? false,
      lastPaidDate: widget.bill?.lastPaidDate,
      reminderEnabled: _reminderEnabled,
      type: _type,
      note: _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : null,
      totalLoanAmount: _type == 'Loan' && _totalLoanAmountController.text.trim().isNotEmpty ? double.tryParse(_totalLoanAmountController.text.trim().replaceAll(',', '')) : null,
      totalEmis: _type == 'Loan' && _totalEmisController.text.trim().isNotEmpty ? int.tryParse(_totalEmisController.text.trim()) : null,
      paidEmis: _type == 'Loan' && _paidEmisController.text.trim().isNotEmpty ? int.tryParse(_paidEmisController.text.trim()) : null,
    );

    if (widget.bill == null) {
      ref.read(billsProvider.notifier).addBill(newBill);
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm Update'),
          content: const Text('Do you want to update this bill?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Update')),
          ],
        ),
      );
      if (confirm != true) return;
      ref.read(billsProvider.notifier).updateBill(newBill);
    }

    // Schedule notification(s)
    await NotificationService().scheduleBillNotifications(
      billId: newBill.id,
      title: 'Bill Reminder: $title',
      dueDay: _dueDay,
      reminderDaysBeforeList: _reminderDaysList,
      hour: _reminderTime.hour,
      minute: _reminderTime.minute,
      enabled: _reminderEnabled,
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.bill == null ? 'Bill Tracker Added' : 'Bill Updated'), duration: const Duration(milliseconds: 1500)));
    }
  }

  String _getSuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }
}

class IndianThousandsFormatter extends TextInputFormatter {
  final NumberFormat _format = NumberFormat.decimalPattern('en_IN');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    String newText = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');
    List<String> parts = newText.split('.');
    String intPart = parts[0];

    try {
      if (intPart.isNotEmpty) {
        int parsed = int.parse(intPart);
        intPart = _format.format(parsed);
      }
    } catch (e) {
      // ignore parsing errors
    }

    String formattedText = intPart;
    if (parts.length > 1) {
      formattedText += '.' + parts[1];
    }

    return newValue.copyWith(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}
