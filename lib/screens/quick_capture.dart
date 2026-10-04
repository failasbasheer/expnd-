import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/app_header.dart';
import '../widgets/neopop.dart';
import '../widgets/money_field.dart';

/// The screen a Back Tap lands on: type an amount, optionally tap a category,
/// done.
///
/// It deliberately saves a [PendingCapture] rather than a [Transaction]. The
/// gesture that opens this is meant to be fired mid-transaction — at the
/// counter, in the cab — so it asks only for what the user knows in that moment
/// and leaves the rest (which account, the date, tags, a receipt) to the inbox's
/// FILE step later. That also keeps balances honest: nothing reaches the ledger
/// until an account has been chosen, so no capture can move a balance by
/// guessing one.
///
/// Compared with [showAddTransaction] this is the same first two fields and
/// none of the other ten, which is the entire point — a full add sheet is a
/// worse answer to "I have four seconds".
Future<void> showQuickCapture(BuildContext context, {String source = 'quick'}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => QuickCaptureScreen(source: source),
    ),
  );
}

class QuickCaptureScreen extends StatefulWidget {
  /// Stamped onto the capture so the inbox can label where it came from.
  final String source;

  const QuickCaptureScreen({super.key, this.source = 'quick'});

  @override
  State<QuickCaptureScreen> createState() => _QuickCaptureScreenState();
}

class _QuickCaptureScreenState extends State<QuickCaptureScreen> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  /// At most one of these is set, mirroring [PendingCapture]. Null/null means
  /// the user skipped the category — a valid outcome here, not an error.
  TransactionCategory? _category;
  CustomCategory? _custom;

  bool _saved = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountCtrl.text) ?? 0;

  bool get _isValid => _amount > 0;

  void _close() {
    // Release focus first, or iOS leaves the keyboard stuck open over the
    // screen behind this one.
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
  }

  void _save() {
    if (!_isValid || _saved) return;
    // The save button stays mounted while the pop animates, so guard against a
    // double tap queueing two captures for one amount.
    _saved = true;
    Haptics.medium();
    context.read<AppStore>().addPendingCaptures([
      PendingCapture(
        // Prefixed like the native queue's ids so the inbox's id space reads
        // uniformly, but minted locally — this capture never goes through the
        // App Group.
        id: 'cap-${newId()}',
        amount: _amount,
        note: _noteCtrl.text.trim(),
        source: widget.source,
        categoryRaw: _custom == null ? _category?.raw : null,
        customCategoryId: _custom?.id,
      ),
    ]);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final settings = context.watch<SettingsStore>();
    final symbol = currencySymbol(settings.currencyCode);

    return Scaffold(
      backgroundColor: oc.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ExpndHeader(
              icon: 'bolt.fill',
              title: 'Quick add',
              actions: [
                HeaderAction(
                  icon: 'xmark',
                  onPressed: _close,
                  semanticLabel: 'Close quick add',
                ),
              ],
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  children: [
                    _amountField(oc, symbol),
                    const SizedBox(height: 22),
                    _categoryGrid(oc, store),
                    const SizedBox(height: 22),
                    _noteField(oc),
                    const SizedBox(height: 18),
                    _explainer(oc),
                  ],
                ),
              ),
            ),
            _saveBar(oc),
          ],
        ),
      ),
    );
  }

  Widget _amountField(ExpndColors oc, String symbol) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label(oc, 'Amount'),
      const SizedBox(height: 10),
      MoneyField(
        controller: _amountCtrl,
        currencyCode: context.read<SettingsStore>().currencyCode,
        label: 'Amount',
        prominent: true,
        autofocus: true,
        onChanged: (_) => setState(() {}),
      ),
    ],
  );

  /// Expense categories only — nothing fired from a pocket gesture is income or
  /// a transfer, and both of those need a counterparty account this screen
  /// doesn't ask for.
  ///
  /// Ordered by how often the user actually spends in each, so the categories
  /// that matter sit under the thumb. Unlike the add sheet there's no sort
  /// control: a screen whose promise is "four seconds" shouldn't offer settings.
  Widget _categoryGrid(ExpndColors oc, AppStore store) {
    final counts = <String, int>{};
    for (final t in store.transactions) {
      if (t.type != TransactionType.expense) continue;
      final key = t.customCategoryId != null
          ? 'custom:${t.customCategoryId}'
          : t.category.raw;
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final entries = <({TransactionCategory? builtin, CustomCategory? custom})>[
      for (final c in TransactionCategory.categoriesFor(
        TransactionType.expense,
      ))
        (builtin: c, custom: null),
      for (final c in store.customCategories.where(
        (c) =>
            c.applicableType == null ||
            c.applicableType == TransactionType.expense,
      ))
        (builtin: null, custom: c),
    ];

    int usage(({TransactionCategory? builtin, CustomCategory? custom}) e) =>
        counts[e.custom != null ? 'custom:${e.custom!.id}' : e.builtin!.raw] ??
        0;

    // Stable within equal usage: a grid that reshuffles between launches would
    // defeat the muscle memory this ordering exists to build.
    entries.sort((a, b) {
      final byUse = usage(b).compareTo(usage(a));
      if (byUse != 0) return byUse;
      final an = a.custom?.name ?? a.builtin!.raw;
      final bn = b.custom?.name ?? b.builtin!.raw;
      return an.toLowerCase().compareTo(bn.toLowerCase());
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label(oc, 'CATEGORY'),
            const SizedBox(width: 8),
            Text(
              'OPTIONAL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: oc.muted.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.15,
          children: [
            for (final e in entries)
              if (e.builtin != null)
                _catChip(
                  oc,
                  selected: _custom == null && _category == e.builtin,
                  label: e.builtin!.raw,
                  glyph: (selected) => Icon(
                    sfIcon(e.builtin!.icon),
                    size: 18,
                    color: selected ? ExpndColors.ink : e.builtin!.color,
                  ),
                  onTap: () => setState(() {
                    _custom = null;
                    _category = _category == e.builtin ? null : e.builtin;
                  }),
                )
              else
                _catChip(
                  oc,
                  selected: _custom?.id == e.custom!.id,
                  label: e.custom!.name,
                  // Custom categories are identified by an emoji, not an SF
                  // Symbol — the create sheet only offers emoji.
                  glyph: (_) => Text(
                    e.custom!.emoji,
                    style: const TextStyle(fontSize: 17),
                  ),
                  onTap: () => setState(() {
                    _category = null;
                    _custom = _custom?.id == e.custom!.id ? null : e.custom;
                  }),
                ),
          ],
        ),
      ],
    );
  }

  /// [glyph] is a builder rather than a widget because the icon has to invert to
  /// ink on the gold selected face, and only the chip knows it's selected.
  Widget _catChip(
    ExpndColors oc, {
    required String label,
    required Widget Function(bool selected) glyph,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return NeoPopElevated(
      faceColor: selected ? ExpndColors.gold : oc.surface,
      depthColor: selected ? ExpndColors.goldDark : oc.edge,
      borderColor: selected ? ExpndColors.goldDark : oc.border,
      depth: 0,
      cornerRadius: 6,
      child: InkWell(
        onTap: () {
          Haptics.light();
          onTap();
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            glyph(selected),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                  color: selected ? ExpndColors.ink : oc.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noteField(ExpndColors oc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label(oc, 'NOTE'),
            const SizedBox(width: 8),
            Text(
              'OPTIONAL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: oc.muted.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: oc.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: oc.border, width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: TextField(
            controller: _noteCtrl,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: oc.text,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: 'What was it for?',
              hintStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: oc.muted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Says out loud that this isn't a finished transaction. Without it, a capture
  /// that never shows up in the ledger reads as a bug rather than as a queue.
  Widget _explainer(ExpndColors oc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(sfIcon('tray'), size: 14, color: oc.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Saved to your inbox, not the ledger. Pick an account when you '
            'file it — and add tags, a date or a receipt then if you need to.',
            style: TextStyle(fontSize: 11, height: 1.4, color: oc.muted),
          ),
        ),
      ],
    );
  }

  Widget _label(ExpndColors oc, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.3,
      color: oc.muted,
    ),
  );

  Widget _saveBar(ExpndColors oc) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: oc.bg,
        border: Border(top: BorderSide(color: oc.border, width: 1.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          // NeoPopButton's `enabled` only withholds the tap — it deliberately
          // leaves appearance to the caller, so the colours have to be switched
          // here too or a dead button looks live. Same treatment as the add
          // sheet's submit bar.
          child: NeoPopButton(
            enabled: _isValid,
            onPressed: _save,
            faceColor: _isValid ? ExpndColors.gold : oc.surface,
            depthColor: _isValid ? ExpndColors.goldDark : oc.edge,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Center(
                child: Text(
                  'ADD TO INBOX',
                  style: ExpndType.label(
                    _isValid ? ExpndColors.ink : oc.dimmed,
                  ).copyWith(fontSize: 13, letterSpacing: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
