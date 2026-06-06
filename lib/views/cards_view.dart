import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart';
import '../providers.dart';
import '../main_helpers.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class CardsView extends ConsumerWidget {
  const CardsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(filteredCardsProvider);
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: cards.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.credit_card_off_outlined, size: 80, color: Colors.grey.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text('No cards saved yet', style: GoogleFonts.lexend(color: Colors.grey, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('Tap + to add your first card', style: GoogleFonts.lexend(color: Colors.grey.withOpacity(0.6), fontSize: 13)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: cards.length,
              itemBuilder: (context, index) => VaultCardWidget(card: cards[index]),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCardEditorDialog(context, ref),
        backgroundColor: const Color(0xFF1D63D2),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class VaultCardWidget extends ConsumerStatefulWidget {
  final VaultCard card;
  const VaultCardWidget({required this.card, super.key});

  @override
  ConsumerState<VaultCardWidget> createState() => _VaultCardWidgetState();
}

class _VaultCardWidgetState extends ConsumerState<VaultCardWidget> {
  Timer? _autoLockTimer;

  void _startAutoLockTimer() {
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) {
        final revealedId = ref.read(revealedCardIdProvider);
        if (revealedId == widget.card.id) {
          ref.read(revealedCardIdProvider.notifier).setRevealed(null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Card auto-locked for security'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    // Use WidgetsBinding to clear Riverpod provider state outside of layout/paint phase safely
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.exists(revealedCardIdProvider)) {
        final revealedId = ref.read(revealedCardIdProvider);
        if (revealedId == widget.card.id) {
          ref.read(revealedCardIdProvider.notifier).setRevealed(null);
        }
      }
    });
    super.dispose();
  }

  String _getCardBrand(String number) {
    String clean = number.replaceAll(' ', '');
    if (clean.startsWith('4')) return 'VISA';
    if (RegExp(r'^5[1-5]').hasMatch(clean)) return 'MasterCard';
    if (RegExp(r'^60|65|81|82').hasMatch(clean)) return 'RuPay';
    if (RegExp(r'^3[47]').hasMatch(clean)) return 'AMEX';
    if (clean.startsWith('6011')) return 'Discover';
    return 'CARD';
  }

  Color _getNetworkBadgeColor(String brand) {
    switch (brand) {
      case 'VISA':       return const Color(0xFF1A56DB);
      case 'MasterCard': return const Color(0xFFE06B00);
      case 'RuPay':      return const Color(0xFF0A7A3B);
      case 'AMEX':       return const Color(0xFF0D2B6B);
      case 'Discover':   return const Color(0xFFB45309);
      default:           return const Color(0xFF6B7280);
    }
  }

  List<Color> _getCardColors(String brand, String type) {
    if (type == 'Credit Card') return [const Color(0xFF334155), const Color(0xFF0F172A)];
    
    switch (brand) {
      case 'VISA': return [const Color(0xFF1A1F71), const Color(0xFF070B4A)];
      case 'MasterCard': return [const Color(0xFF222222), const Color(0xFF000000)];
      case 'RuPay': return [const Color(0xFFFF8C00), const Color(0xFFCC7000)];
      case 'AMEX': return [const Color(0xFF007085), const Color(0xFF004D5C)];
      default: return [const Color(0xFF1D63D2), const Color(0xFF1E40AF)];
    }
  }

  String _maskNumber(String number) {
    String clean = number.replaceAll(' ', '');
    if (clean.length < 4) return number;
    final last4 = clean.substring(clean.length - 4);
    return '**** **** **** $last4';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(revealedCardIdProvider, (previous, next) {
      if (next == widget.card.id) {
        _startAutoLockTimer();
      } else {
        _autoLockTimer?.cancel();
      }
    });
    final brand = _getCardBrand(widget.card.cardNumber);
    final cardColors = _getCardColors(brand, widget.card.cardType);
    final revealedId = ref.watch(revealedCardIdProvider);
    final isRevealed = revealedId == widget.card.id;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isRevealed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0, right: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy_all, color: Color(0xFF1D63D2), size: 20),
                  onPressed: () {
                    final details = 'Card Number: ${widget.card.cardNumber}\n'
                        'Card Holder: ${widget.card.holderName.isEmpty ? 'VAULT USER' : widget.card.holderName}\n'
                        'Expiry: ${widget.card.expiryDate}\n'
                        'CVV: ${widget.card.cvv}';
                    Clipboard.setData(ClipboardData(text: details));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Card details copied to clipboard')),
                    );
                  },
                  tooltip: 'Copy All Details',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey, size: 20),
                  onPressed: () => showCardEditorDialog(context, ref, card: widget.card),
                  tooltip: 'Edit Card',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  onPressed: () => _confirmDeleteCard(context, ref, widget.card),
                  tooltip: 'Delete Card',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.lock_outline, color: Colors.green, size: 20),
                  onPressed: () => ref.read(revealedCardIdProvider.notifier).setRevealed(null),
                  tooltip: 'Lock Card',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: cardColors,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(Icons.credit_card, size: 150, color: Colors.white.withOpacity(0.05)),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.card.bankName.toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              widget.card.cardType.toUpperCase(),
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getNetworkBadgeColor(brand),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          brand,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    width: 45,
                    height: 35,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFDAA520)]),
                    ),
                    child: Center(
                      child: Icon(Icons.grid_3x3, color: Colors.black.withOpacity(0.3), size: 30),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            isRevealed ? widget.card.cardNumber : _maskNumber(widget.card.cardNumber),
                            style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.w500, fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('CARD HOLDER', style: TextStyle(color: Colors.white70, fontSize: 8)),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      widget.card.holderName.isEmpty ? 'VAULT USER' : widget.card.holderName.toUpperCase(),
                                      style: const TextStyle(color: Colors.white, fontSize: 14),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('EXPIRES', style: TextStyle(color: Colors.white70, fontSize: 8)),
                            Text(isRevealed ? widget.card.expiryDate : '**/**', style: const TextStyle(color: Colors.white, fontSize: 14)),
                          ],
                        ),
                      ),
                      if (isRevealed)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('CVV', style: TextStyle(color: Colors.white70, fontSize: 8)),
                              Text(widget.card.cvv, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          if (!isRevealed)
            Positioned.fill(
              child: Material(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: () {
                    verifyPasscode(context, ref, onSuccess: () {
                      ref.read(revealedCardIdProvider.notifier).setRevealed(widget.card.id);
                    });
                  },
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock, color: Colors.white, size: 32),
                        const SizedBox(height: 8),
                        Text('Tap to Reveal', style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
      ],
    );
  }



  void _confirmDeleteCard(BuildContext context, WidgetRef ref, VaultCard card) {
    final cleanNumber = card.cardNumber.replaceAll(' ', '');
    final suffix = cleanNumber.length >= 4 
        ? cleanNumber.substring(cleanNumber.length - 4) 
        : cleanNumber;
    
    final promptText = suffix.isNotEmpty
        ? 'Are you sure you want to delete ${card.bankName} card ending in $suffix?'
        : 'Are you sure you want to delete this ${card.bankName} card?';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Card?'),
        content: Text(promptText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(cardsProvider.notifier).deleteCard(card.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Card deleted')));
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

void showCardEditorDialog(BuildContext context, WidgetRef ref, {VaultCard? card}) {
  final bankController = TextEditingController(text: card?.bankName ?? '');
  final holderController = TextEditingController(text: card?.holderName ?? '');
  final numberController = TextEditingController(text: card?.cardNumber ?? '');
  final expiryController = TextEditingController(text: card?.expiryDate ?? '');
  final cvvController = TextEditingController(text: card?.cvv ?? '');
  final numberFocusNode = FocusNode();
  String cardType = card?.cardType ?? 'Debit Card';

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        void save() {
          if (bankController.text.isEmpty || numberController.text.isEmpty) return;
          
          final newCard = VaultCard(
            id: card?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
            bankName: bankController.text,
            holderName: holderController.text,
            cardNumber: numberController.text,
            expiryDate: expiryController.text,
            cvv: cvvController.text,
            cardType: cardType,
          );

          if (card == null) {
            ref.read(cardsProvider.notifier).addCard(newCard);
          } else {
            ref.read(cardsProvider.notifier).updateCard(newCard);
          }
          Navigator.pop(context);
        }

        return AlertDialog(
          title: Row(
            children: [
              Text(card == null ? 'Add ATM Card' : 'Edit Card', style: GoogleFonts.lexend(fontWeight: FontWeight.bold, fontSize: 18)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                onPressed: save,
                tooltip: 'Save Card',
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: bankController,
                  autofocus: card == null,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Bank Name', hintText: 'e.g. HDFC Bank', prefixIcon: Icon(Icons.account_balance, size: 20)),
                ),
                TextField(
                  controller: holderController,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => numberFocusNode.requestFocus(),
                  decoration: const InputDecoration(labelText: 'Card Holder Name', prefixIcon: Icon(Icons.person, size: 20)),
                ),
                const SizedBox(height: 8),
                ExcludeFocus(
                  child: DropdownButtonFormField<String>(
                    initialValue: cardType,
                    decoration: const InputDecoration(labelText: 'Card Type', prefixIcon: Icon(Icons.credit_card, size: 20)),
                    items: ['Debit Card', 'Credit Card'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (val) => setDialogState(() => cardType = val!),
                  ),
                ),
                TextField(
                  controller: numberController,
                  focusNode: numberFocusNode,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Card Number', hintText: 'XXXX XXXX XXXX XXXX', prefixIcon: Icon(Icons.numbers, size: 20)),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, _CardNumberFormatter()],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: expiryController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Expiry', hintText: 'MM/YY', prefixIcon: Icon(Icons.calendar_today, size: 18)),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, _ExpiryDateFormatter()],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: cvvController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => save(),
                        decoration: const InputDecoration(labelText: 'CVV', hintText: 'XXX', prefixIcon: Icon(Icons.lock_outline, size: 18)),
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 4,
                        buildCounter: (context, {required currentLength, bool? isFocused, maxLength}) => null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))
            ),
            FilledButton.icon(
              onPressed: save,
              icon: const Icon(Icons.save, size: 18),
              label: Text(card == null ? 'Save' : 'Update'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1D63D2)),
            ),
          ],
        );
      },
    ),
  );
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(' ', '');
    if (text.length > 16) return oldValue;
    
    String formatted = '';
    for (int i = 0; i < text.length; i++) {
      formatted += text[i];
      if ((i + 1) % 4 == 0 && (i + 1) != text.length) {
        formatted += ' ';
      }
    }
    return newValue.copyWith(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll('/', '');
    if (text.length > 4) return oldValue;
    
    String formatted = text;
    if (text.length > 2) {
      formatted = '${text.substring(0, 2)}/${text.substring(2)}';
    }
    return newValue.copyWith(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

