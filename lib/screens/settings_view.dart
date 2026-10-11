import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/backup.dart';
import '../services/reminders.dart';
import '../services/statement_pdf.dart';
import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/glass_header.dart';
import '../widgets/app_header.dart';
import '../widgets/disclosure_section.dart';
import '../widgets/neopop.dart';
import '../widgets/section_card.dart';
import '../widgets/tag_manager.dart';
import 'account_setup.dart';
import 'add_transaction.dart';

/// Who you are and how the app behaves — identity, the categories and tags you
/// label money with, and the app's own settings. Reached from the avatar in
/// the header rather than a tab, because it is not somewhere you go daily.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool _editingName = false;
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = context.read<SettingsStore>().userName;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final store = context.watch<AppStore>();
    final settings = context.watch<SettingsStore>();
    final code = settings.currencyCode;
    final symbol = currencySymbol(code);

    return Scaffold(
      backgroundColor: oc.bg,
      body: SafeArea(
        top: !ExpndGlass.enabled,
        bottom: false,
        child: GlassHeaderLayout(
          header: ExpndHeader(
            icon: 'person.fill',
            title: 'SETTINGS',
            actions: [
              HeaderAction(
                icon: 'xmark',
                onPressed: () => Navigator.of(context).maybePop(),
                semanticLabel: 'Close settings',
              ),
            ],
          ),
          body: (context, top) => ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              16,
              16 + top,
              16,
              ExpndSpacing.scrollBottom,
            ),
            children: [
              _avatarCard(oc, store, settings),
              const SizedBox(height: 20),
              DisclosureSection(
                title: 'General',
                icon: 'gearshape.fill',
                tint: oc.muted,
                subtitle: 'Currency, entry type and app lock',
                child: _generalSection(oc, store, settings),
              ),
              const SizedBox(height: 12),
              DisclosureSection(
                title: 'Reminders & alerts',
                icon: 'bell.fill',
                tint: hexColor('F97316'),
                subtitle: 'Bills, budgets and daily nudges',
                child: _notificationsSection(oc, settings),
              ),
              const SizedBox(height: 12),
              DisclosureSection(
                title: 'Categories & tags',
                icon: 'tag.fill',
                tint: hexColor('A855F7'),
                subtitle: 'Organize transactions your way',
                child: Column(
                  children: [
                    _manageCategoriesSection(oc, store),
                    if (store.allTags.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _manageTagsSection(oc, store, code),
                    ],
                  ],
                ),
              ),
              if (Platform.isIOS) ...[
                const SizedBox(height: 12),
                DisclosureSection(
                  title: 'Quick capture',
                  icon: 'bolt.fill',
                  tint: oc.accent,
                  subtitle: 'Widget buttons and Back Tap setup',
                  child: Column(
                    children: [
                      _quickLogSection(oc, settings, symbol),
                      const SizedBox(height: 20),
                      _backTapSection(oc),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              DisclosureSection(
                title: 'Appearance',
                icon: 'circle.lefthalf.filled',
                tint: hexColor('3B82F6'),
                subtitle: 'Light, dark or match device',
                child: _appearanceSection(oc, settings),
              ),
              const SizedBox(height: 12),
              DisclosureSection(
                title: 'Data',
                icon: 'archivebox.fill',
                tint: ExpndColors.green,
                subtitle: 'Backup, restore and export',
                child: _dataSection(oc, store, symbol),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _saveName(SettingsStore settings) {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    settings.userName = name;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _editingName = false);
  }

  /// The 1.0 profile card: a raised gold NeoPOP block with an ink monogram,
  /// WELCOME BACK over your name, and a strip of ledger stats.
  Widget _avatarCard(
    ExpndColors oc,
    AppStore store,
    SettingsStore settings,
  ) {
    final ink = ExpndColors.ink;
    final name = settings.userName.trim();
    final named = name.isNotEmpty && name != 'Your Name';
    final initial = named ? name.characters.first.toUpperCase() : '?';
    final oldest = store.transactionsAscending.firstOrNull?.date;
    final days = oldest == null
        ? 0
        : DateTime.now().difference(oldest).inDays.clamp(0, 99999) + 1;
    final inkButton = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? ink.withValues(alpha: 0.25)
            : ink,
      ),
      foregroundColor: WidgetStatePropertyAll(ExpndColors.gold),
    );

    Widget stat(String value, String label) => Expanded(
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: ink,
                ),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: ink.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );

    // Matches the Home balance card: rounded gold face, gold-dark rim and a
    // 6pt offset edge.
    return NeoPopElevated(
      faceColor: ExpndColors.gold,
      depthColor: ExpndColors.goldDark,
      borderColor: ExpndColors.goldDark,
      borderWidth: 1.5,
      depth: 6,
      cornerRadius: 12,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Flat outlined monogram tile: hard ink border, no heavy block.
                ExcludeSemantics(
                  child: Container(
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: ink.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WELCOME BACK',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: ink.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        named ? name : 'Add your name',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: ink,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_editingName)
                  IconButton(
                    tooltip: 'Edit name',
                    onPressed: () {
                      _nameCtrl.text = named ? settings.userName : '';
                      setState(() => _editingName = true);
                    },
                    icon: Icon(sfIcon('pencil'), size: 18, color: ink),
                  ),
              ],
            ),
            if (_editingName) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _saveName(settings),
                onChanged: (_) => setState(() {}),
                cursorColor: ink,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
                decoration: InputDecoration(
                  labelText: 'Your name',
                  labelStyle: TextStyle(color: ink.withValues(alpha: 0.7)),
                  floatingLabelStyle: TextStyle(color: ink),
                  filled: true,
                  fillColor: ink.withValues(alpha: 0.06),
                  contentPadding: const EdgeInsets.all(14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: ink.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: ink, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    style: inkButton,
                    onPressed: _nameCtrl.text.trim().isEmpty
                        ? null
                        : () => _saveName(settings),
                    child: const Text('Save name'),
                  ),
                  TextButton(
                    style: ButtonStyle(
                      foregroundColor: WidgetStatePropertyAll(ink),
                    ),
                    onPressed: () {
                      _nameCtrl.text = settings.userName;
                      FocusManager.instance.primaryFocus?.unfocus();
                      setState(() => _editingName = false);
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Container(height: 1, color: ink.withValues(alpha: 0.16)),
            const SizedBox(height: 14),
            Row(
              children: [
                stat('${store.transactions.length}', 'ENTRIES'),
                stat('${store.accounts.length}', 'ACCOUNTS'),
                stat('$days', days == 1 ? 'DAY TRACKED' : 'DAYS TRACKED'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  Widget _manageCategoriesSection(ExpndColors oc, AppStore store) {
    final cats = store.customCategories;
    return sectionCard(
      oc,
      'CUSTOM CATEGORIES',
      Column(
        children: [
          if (cats.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Icon(sfIcon('plus.circle'), size: 20, color: oc.dimmed),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Create your own categories to log spending your way.',
                      style: TextStyle(fontSize: 12, color: oc.muted),
                    ),
                  ),
                ],
              ),
            )
          else
            for (int i = 0; i < cats.length; i++) ...[
              _categoryManageRow(oc, cats[i]),
              if (i < cats.length - 1) sectionDivider(oc),
            ],
          sectionDivider(oc),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showCustomCategorySheet(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(sfIcon('plus.circle.fill'), size: 20, color: oc.accent),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'New category',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: oc.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryManageRow(ExpndColors oc, CustomCategory c) {
    final color = hexColor(c.colorHex);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showCustomCategorySheet(context, editing: c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(c.emoji, style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: oc.text,
                    ),
                  ),
                  Text(
                    (c.applicableType?.raw ?? 'Both').toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: oc.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(sfIcon('pencil'), size: 14, color: oc.dimmed),
          ],
        ),
      ),
    );
  }

  // ── Manage tags ───────────────────────────────────────────────────────────

  Widget _manageTagsSection(ExpndColors oc, AppStore store, String code) {
    final tags = store.allTags;
    return sectionCard(
      oc,
      'TAGS',
      Column(
        children: [
          for (int i = 0; i < tags.length; i++) ...[
            _tagManageRow(oc, store, tags[i], code),
            if (i < tags.length - 1) sectionDivider(oc),
          ],
        ],
      ),
    );
  }

  Widget _tagManageRow(
    ExpndColors oc,
    AppStore store,
    String tag,
    String code,
  ) {
    final count = store.transactionsWithTag(tag).length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showTagManager(context, tag),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ExpndColors.gold.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: ExpndColors.gold.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                '#',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: oc.accent,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: oc.text,
                    ),
                  ),
                  Text(
                    '$count transaction${count == 1 ? '' : 's'} · '
                    '${formatCurrency(store.spentOnTag(tag), code)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: oc.muted),
                  ),
                ],
              ),
            ),
            Icon(sfIcon('chevron.right'), size: 14, color: oc.dimmed),
          ],
        ),
      ),
    );
  }

  /// The amounts the Quick Log widget offers as one-tap buttons. A tap logs
  /// straight away with no confirmation, so these have to be amounts the user
  /// actually spends — which only they know.
  Widget _quickLogSection(
    ExpndColors oc,
    SettingsStore settings,
    String symbol,
  ) {
    final presets = settings.quickCapturePresets;
    return sectionCard(
      oc,
      'QUICK LOG',
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(sfIcon('bolt.fill'), size: 20, color: oc.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Widget Amounts',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: oc.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to change. Logged amounts wait in your inbox '
                        'until you categorise them.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: oc.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: Row(
              children: [
                for (var i = 0; i < presets.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _editPreset(settings, presets, i, symbol),
                      child: Container(
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: oc.card,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: oc.border, width: 1.5),
                        ),
                        child: Text(
                          '$symbol'
                          '${amountInputText(presets[i], settings.currencyCode)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: oc.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// How to put Quick Add on a double-tap of the back of the phone.
  ///
  /// This is instructions rather than a switch because it has to be: iOS gives
  /// apps no API to read Back Tap, or to assign itself to it. All the app can do
  /// is publish the "Quick Add" shortcut (see ios/Runner/ExpndAppIntents.swift)
  /// and tell the user where to point the gesture. The app also can't deep-link
  /// into that Settings pane — the URL for it is private API, and EXPND ships no
  /// URL launcher at all — so the path is spelled out to be followed by hand.
  Widget _backTapSection(ExpndColors oc) {
    Widget step(String n, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(
              n,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: oc.accent,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, height: 1.4, color: oc.text),
            ),
          ),
        ],
      ),
    );

    return sectionCard(
      oc,
      'BACK TAP',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(sfIcon('hand.raised.fill'), size: 20, color: oc.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Double-tap to log',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: oc.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap the back of your iPhone twice to open Quick Add. '
                        'Set it up once in iOS Settings:',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: oc.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          step('1.', 'Settings › Accessibility › Touch › Back Tap'),
          step('2.', 'Choose Double Tap (or Triple Tap)'),
          step('3.', 'Scroll to Shortcuts and pick “Quick Add”'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text(
              'Not listed? Open Shortcuts, make a new shortcut with EXPND’s '
              '“Quick Add” action, save it, then it appears in step 3. '
              'Back Tap needs iPhone 8 or later.',
              style: TextStyle(fontSize: 11, height: 1.35, color: oc.muted),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editPreset(
    SettingsStore settings,
    List<double> presets,
    int index,
    String symbol,
  ) async {
    final oc = context.oc;
    final code = settings.currencyCode;
    final ctrl = TextEditingController(
      text: amountInputText(presets[index], code),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: oc.surface,
        title: Text(
          'QUICK AMOUNT',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: oc.text,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: amountFormattersFor(code),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: oc.text,
          ),
          decoration: InputDecoration(
            prefixText: '$symbol ',
            prefixStyle: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: oc.muted,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('CANCEL', style: TextStyle(color: oc.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(parseAmount(ctrl.text)),
            child: Text('SET', style: TextStyle(color: oc.accent)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value == null || value <= 0) return;
    final next = List<double>.from(presets);
    next[index] = value;
    settings.quickCapturePresets = next;
  }

  Widget _generalSection(
    ExpndColors oc,
    AppStore store,
    SettingsStore settings,
  ) {
    // Amounts are stored without FX conversion, so the app-wide currency is
    // fixed once any transaction references it — changing it would relabel
    // existing amounts rather than convert them. Lock it after the first tx.
    final currencyLocked =
        store.transactions.isNotEmpty || store.accounts.isNotEmpty;
    return Column(
      children: [
        // Currency
        GestureDetector(
          onTap: () async {
            if (currencyLocked) {
              _snack(
                'Currency is locked — amounts aren\'t converted, so it can\'t change once you have transactions.',
              );
              return;
            }
            final picked = await showCurrencyPicker(
              context,
              settings.currencyCode,
            );
            if (picked != null) settings.currencyCode = picked;
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  sfIcon('dollarsign.circle.fill'),
                  size: 20,
                  color: currencyLocked ? oc.dimmed : oc.accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Currency',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: oc.text,
                        ),
                      ),
                      Text(
                        currencyLocked
                            ? 'Locked — you have transactions'
                            : supportedCurrencies
                                      .where(
                                        (c) => c.code == settings.currencyCode,
                                      )
                                      .map((c) => c.name)
                                      .firstOrNull ??
                                  'US Dollar',
                        style: TextStyle(fontSize: 11, color: oc.muted),
                      ),
                    ],
                  ),
                ),
                Text(
                  settings.currencyCode,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: currencyLocked ? oc.muted : oc.accent,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  sfIcon(currencyLocked ? 'lock.fill' : 'chevron.right'),
                  size: 12,
                  color: oc.dimmed,
                ),
              ],
            ),
          ),
        ),
        sectionDivider(oc),
        // Default type
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                sfIcon('arrow.left.arrow.right'),
                size: 20,
                color: oc.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Default Type',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: oc.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Scales down rather than overflowing when the label beside it
              // is long and the system text size is turned up.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: _segmented(
                    oc,
                    [('expense', 'EXPENSE'), ('income', 'INCOME')],
                    settings.defaultTransactionType,
                    (v) {
                      Haptics.light();
                      settings.defaultTransactionType = v;
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        sectionDivider(oc),
        // Haptics
        _toggleRow(
          oc,
          'hand.raised.fill',
          'Haptics',
          'Tactile feedback on actions',
          settings.hapticsEnabled,
          (v) {
            settings.hapticsEnabled = v;
            if (v) Haptics.medium();
          },
        ),
        sectionDivider(oc),
        // Biometric app lock. Name the platform's own method — "Face ID" is
        // Apple's trademark and reads as broken on an Android phone, the same
        // way LockScreen picks its label from what the device actually has.
        _toggleRow(
          oc,
          'faceid',
          'Biometric Lock',
          Platform.isIOS
              ? 'Require Face ID / Touch ID to open'
              : 'Require fingerprint to open',
          settings.biometricLockEnabled,
          (v) async {
            Haptics.light();
            if (!v) {
              settings.biometricLockEnabled = false;
              return;
            }
            try {
              final auth = LocalAuthentication();
              final available = await auth.getAvailableBiometrics();
              final supported =
                  await auth.canCheckBiometrics ||
                  await auth.isDeviceSupported();
              if (!mounted) return;
              if (!supported || available.isEmpty) {
                _snack('Set up Face ID / Touch ID before enabling the lock.');
                return;
              }
              final ok = await auth.authenticate(
                localizedReason: 'Enable the EXPND app lock',
                biometricOnly: true,
              );
              if (mounted && ok) settings.biometricLockEnabled = true;
            } catch (_) {
              if (mounted) _snack('Biometric setup was not completed.');
            }
          },
        ),
        // Grace window before a re-open asks for Face ID again — so briefly
        // hopping to another app doesn't demand a fresh scan every time.
        if (settings.biometricLockEnabled)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pickAutoLockDelay(settings),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(48, 0, 16, 14),
              child: Row(
                children: [
                  Text(
                    'Ask again',
                    style: TextStyle(fontSize: 12, color: oc.muted),
                  ),
                  const Spacer(),
                  Text(
                    _autoLockLabel(settings.autoLockGraceSeconds),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: oc.accent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(sfIcon('chevron.right'), size: 12, color: oc.dimmed),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _notificationsSection(ExpndColors oc, SettingsStore settings) {
    return Column(
      children: [
        // Notifications — all scheduled on-device, no server involved.
        _toggleRow(
          oc,
          'bell.fill',
          'Daily Reminder',
          settings.dailyReminder
              ? 'Every day at ${_timeLabel(settings.reminderTime)}'
              : 'A nightly nudge to log your spending',
          settings.dailyReminder,
          (v) => _setReminder(settings, v),
        ),
        if (settings.dailyReminder) ...[
          _subRow(
            oc,
            'Reminder time',
            _timeLabel(settings.reminderTime),
            () => _pickReminderTime(settings),
          ),
          _subRow(
            oc,
            'Active days',
            _daysLabel(settings.reminderDays),
            () => _pickReminderDays(settings),
          ),
          _subRow(
            oc,
            'Message',
            _messageModeLabel(settings.reminderMessageMode),
            () => _pickMessage(settings),
          ),
          _subRow(
            oc,
            'Tone',
            _toneLabel(settings.reminderTone),
            () => _pickTone(settings),
          ),
        ],
        sectionDivider(oc),
        // Event alerts — each opts in separately; all share the OS permission.
        _toggleRow(
          oc,
          'calendar.badge.clock',
          'Bills due soon',
          'A heads-up the night before a bill or EMI',
          settings.alertBillsDue,
          (v) => _setAlert(settings, () => settings.alertBillsDue = v, v),
        ),
        _toggleRow(
          oc,
          'exclamationmark.triangle.fill',
          'Over budget',
          'When the month crosses your budget',
          settings.alertOverBudget,
          (v) => _setAlert(settings, () => settings.alertOverBudget = v, v),
        ),
        _toggleRow(
          oc,
          'flag.fill',
          'Goal reached',
          'When a savings goal is fully funded',
          settings.alertGoalReached,
          (v) => _setAlert(settings, () => settings.alertGoalReached = v, v),
        ),
        sectionDivider(oc),
        // The optional weekly roundup.
        _toggleRow(
          oc,
          'chart.bar.fill',
          'Weekly summary',
          settings.weeklySummary
              ? 'Every ${_weekdayName(settings.weeklySummaryDay)}'
              : 'A once-a-week look at where it went',
          settings.weeklySummary,
          (v) => _setAlert(settings, () => settings.weeklySummary = v, v),
        ),
        if (settings.weeklySummary)
          _subRow(
            oc,
            'Day',
            _weekdayName(settings.weeklySummaryDay),
            () => _pickWeeklyDay(settings),
          ),
      ],
    );
  }

  String _timeLabel(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  /// Turning the reminder on asks the OS first. If permission is refused the
  /// setting stays off — a toggle that says "on" while the OS silently drops
  /// every notification is worse than no toggle.

  Future<void> _setReminder(SettingsStore settings, bool on) async {
    Haptics.light();
    if (!on) {
      settings.dailyReminder = false;
      await _refresh(settings);
      return;
    }
    final granted = await Reminders.requestPermission();
    if (!granted) {
      if (mounted) {
        _snack(
          'Notifications are off for EXPND. Turn them on in Settings to '
          'get the reminder.',
        );
      }
      return;
    }
    settings.dailyReminder = true;
    await _refresh(settings);
  }

  Future<void> _pickReminderTime(SettingsStore settings) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: settings.reminderTime,
    );
    if (picked == null) return;
    settings.reminderMinuteOfDay = picked.hour * 60 + picked.minute;
    await _refresh(settings);
  }

  /// Rebuilds every notification from the current settings + ledger. The single
  /// place this screen re-arms the schedule, so every knob below — time, tone,
  /// message, active days, the event toggles — takes effect the same way.
  Future<void> _refresh(SettingsStore settings) async {
    await Reminders.refreshAll(context.read<AppStore>(), settings);
  }

  // ── Reminder sub-rows, labels & pickers ─────────────────────────────────────

  /// The indented "label ……… value ›" row under a toggle. One helper so the
  /// reminder's time, days, message and tone rows all line up identically.
  Widget _subRow(
    ExpndColors oc,
    String label,
    String value,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 0, 16, 14),
        child: Row(
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: oc.muted)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: oc.accent,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(sfIcon('chevron.right'), size: 12, color: oc.dimmed),
          ],
        ),
      ),
    );
  }

  /// Turning an event alert on asks the OS the same way the daily reminder does
  /// — permission refused means the toggle stays off rather than claiming an
  /// alert that will never fire. [apply] flips the specific setting.
  Future<void> _setAlert(
    SettingsStore settings,
    VoidCallback apply,
    bool on,
  ) async {
    Haptics.light();
    if (!on) {
      apply();
      await _refresh(settings);
      return;
    }
    final granted = await Reminders.requestPermission();
    if (!granted) {
      if (mounted) {
        _snack(
          'Notifications are off for EXPND. Turn them on in Settings to '
          'get alerts.',
        );
      }
      return;
    }
    apply();
    await _refresh(settings);
  }

  static const List<String> _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const List<String> _weekdayShort = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  String _weekdayName(int weekday) => _weekdayNames[(weekday - 1).clamp(0, 6)];

  String _daysLabel(Set<int> days) {
    if (days.length >= 7) return 'Every day';
    if (days.length == 5 && days.containsAll(const {1, 2, 3, 4, 5})) {
      return 'Weekdays';
    }
    if (days.length == 2 && days.containsAll(const {6, 7})) return 'Weekends';
    final sorted = days.toList()..sort();
    return sorted.map((d) => _weekdayShort[d - 1]).join(', ');
  }

  String _messageModeLabel(String mode) {
    switch (mode) {
      case 'custom':
        return 'My own';
      case 'mixed':
        return 'Mixed';
      default:
        return 'Auto';
    }
  }

  String _messageModeHint(String mode) {
    switch (mode) {
      case 'custom':
        return 'Your line, every night.';
      case 'mixed':
        return 'Your line, rotated in among the auto insights.';
      default:
        return 'Written from your ledger — trends, bills and streaks.';
    }
  }

  String _toneLabel(String tone) =>
      tone.isEmpty ? 'Neutral' : tone[0].toUpperCase() + tone.substring(1);

  /// A single-select bottom sheet, checkmark against the current [selected].
  /// Shared by the tone and weekly-day pickers.
  Future<T?> _pickFromSheet<T>({
    required String title,
    required List<(T, String, String?)> options,
    required T selected,
  }) {
    Haptics.light();
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: context.oc.surface,
      builder: (sheet) {
        final oc = sheet.oc;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: oc.text,
                  ),
                ),
              ),
              Container(height: 1, color: oc.border),
              for (final (value, label, subtitle) in options)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(sheet).pop(value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: oc.text,
                                ),
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: oc.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (value == selected)
                          Icon(sfIcon('checkmark'), size: 16, color: oc.accent),
                      ],
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(sheet).pop(),
                  child: Text('Cancel', style: TextStyle(color: oc.muted)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickTone(SettingsStore settings) async {
    final picked = await _pickFromSheet<String>(
      title: 'REMINDER TONE',
      selected: settings.reminderTone,
      options: const [
        ('neutral', 'Neutral', 'Plain and to the point'),
        ('gentle', 'Gentle', 'Soft, no pressure'),
        ('blunt', 'Blunt', 'Short and direct'),
        ('playful', 'Playful', 'Light and a little cheeky'),
      ],
    );
    if (picked == null) return;
    settings.reminderTone = picked;
    await _refresh(settings);
  }

  Future<void> _pickWeeklyDay(SettingsStore settings) async {
    final picked = await _pickFromSheet<int>(
      title: 'WEEKLY SUMMARY DAY',
      selected: settings.weeklySummaryDay,
      options: [for (var d = 1; d <= 7; d++) (d, _weekdayNames[d - 1], null)],
    );
    if (picked == null) return;
    settings.weeklySummaryDay = picked;
    await _refresh(settings);
  }

  /// Which weekdays the nightly nudge fires. Multi-select, and the last day
  /// can't be unticked — an empty set would silence a reminder the toggle still
  /// reads as on (the store guards this too).
  Future<void> _pickReminderDays(SettingsStore settings) async {
    Haptics.light();
    final chosen = {...settings.reminderDays};
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      backgroundColor: context.oc.surface,
      builder: (sheet) {
        final oc = sheet.oc;
        return StatefulBuilder(
          builder: (context, setSheet) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Text(
                      'ACTIVE DAYS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: oc.text,
                      ),
                    ),
                  ),
                  Container(height: 1, color: oc.border),
                  for (var d = 1; d <= 7; d++)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Haptics.light();
                        setSheet(() {
                          if (chosen.contains(d)) {
                            if (chosen.length > 1) chosen.remove(d);
                          } else {
                            chosen.add(d);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Text(
                              _weekdayNames[d - 1],
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: oc.text,
                              ),
                            ),
                            const Spacer(),
                            if (chosen.contains(d))
                              Icon(
                                sfIcon('checkmark'),
                                size: 16,
                                color: oc.accent,
                              ),
                          ],
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(sheet).pop(chosen),
                      child: Text(
                        'Done',
                        style: TextStyle(
                          color: oc.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (result == null) return;
    settings.reminderDays = result;
    await _refresh(settings);
  }

  /// The message source (Auto / My own / Mixed) and, for the latter two, the
  /// line to use. Kept in one sheet so switching to "My own" and typing the
  /// line is a single trip.
  Future<void> _pickMessage(SettingsStore settings) async {
    Haptics.light();
    final controller = TextEditingController(
      text: settings.reminderCustomMessage,
    );
    var mode = settings.reminderMessageMode;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true, // so the keyboard doesn't cover the field
      backgroundColor: context.oc.surface,
      builder: (sheet) {
        final oc = sheet.oc;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheet).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'REMINDER MESSAGE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: oc.text,
                          ),
                        ),
                      ),
                    ),
                    Container(height: 1, color: oc.border),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _segmented(
                          oc,
                          const [
                            ('auto', 'AUTO'),
                            ('custom', 'MY OWN'),
                            ('mixed', 'MIXED'),
                          ],
                          mode,
                          (v) => setSheet(() => mode = v),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _messageModeHint(mode),
                          style: TextStyle(fontSize: 12, color: oc.muted),
                        ),
                      ),
                    ),
                    if (mode != 'auto')
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: TextField(
                          controller: controller,
                          maxLength: 120,
                          minLines: 1,
                          maxLines: 2,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(color: oc.text, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'e.g. Did you log lunch?',
                            hintStyle: TextStyle(color: oc.dimmed),
                            filled: true,
                            fillColor: oc.border.withValues(alpha: 0.3),
                            counterStyle: TextStyle(color: oc.dimmed),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(sheet).pop(false),
                              child: Text(
                                'Cancel',
                                style: TextStyle(color: oc.muted),
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(sheet).pop(true),
                              child: Text(
                                'Save',
                                style: TextStyle(
                                  color: oc.accent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    if (saved == true) {
      settings.reminderMessageMode = mode;
      settings.reminderCustomMessage = controller.text.trim();
      await _refresh(settings);
    }
    controller.dispose();
  }

  // The auto-lock grace choices, in seconds. 0 keeps the old "lock the instant
  // you leave" behaviour; the rest are windows a quick app-switch fits inside.
  static const List<(int, String)> _autoLockOptions = [
    (0, 'Immediately'),
    (30, 'After 30 seconds'),
    (60, 'After 1 minute'),
    (300, 'After 5 minutes'),
    (900, 'After 15 minutes'),
  ];

  String _autoLockLabel(int seconds) {
    for (final (v, label) in _autoLockOptions) {
      if (v == seconds) return label;
    }
    return 'Immediately';
  }

  Future<void> _pickAutoLockDelay(SettingsStore settings) async {
    Haptics.light();
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.oc.surface,
      builder: (sheet) {
        final oc = sheet.oc;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Text(
                  'ASK FOR FACE ID AGAIN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: oc.text,
                  ),
                ),
              ),
              Container(height: 1, color: oc.border),
              for (final (seconds, label) in _autoLockOptions)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(sheet).pop(seconds),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                    child: Row(
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: oc.text,
                          ),
                        ),
                        const Spacer(),
                        if (settings.autoLockGraceSeconds == seconds)
                          Icon(sfIcon('checkmark'), size: 16, color: oc.accent),
                      ],
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(sheet).pop(),
                  child: Text('Cancel', style: TextStyle(color: oc.muted)),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    settings.autoLockGraceSeconds = picked;
  }

  Widget _toggleRow(
    ExpndColors oc,
    String icon,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(sfIcon(icon), size: 20, color: oc.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: oc.text,
                  ),
                ),
                Text(subtitle, style: TextStyle(fontSize: 11, color: oc.muted)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: oc.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _segmented(
    ExpndColors oc,
    List<(String, String)> options,
    String selected,
    ValueChanged<String> onSelect,
  ) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: oc.border.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: oc.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (val, label) in options)
            GestureDetector(
              onTap: () => onSelect(val),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: selected == val
                      ? ExpndColors.gold
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: selected == val ? ExpndColors.ink : oc.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Appearance ───────────────────────────────────────────────────────────

  Widget _appearanceSection(ExpndColors oc, SettingsStore settings) {
    final modes = [
      ('system', 'circle.lefthalf.filled'),
      ('dark', 'moon.fill'),
      ('light', 'sun.max.fill'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(sfIcon('paintbrush.fill'), size: 20, color: oc.accent),
          const SizedBox(width: 12),
          Text(
            'Theme',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: oc.text,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: oc.border.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: oc.border, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (mode, icon) in modes)
                  GestureDetector(
                    onTap: () {
                      Haptics.light();
                      settings.appearanceMode = mode;
                    },
                    child: Container(
                      width: 30,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: settings.appearanceMode == mode
                            ? ExpndColors.gold
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        sfIcon(icon),
                        size: 11,
                        color: settings.appearanceMode == mode
                            ? ExpndColors.ink
                            : oc.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  Widget _dataSection(ExpndColors oc, AppStore store, String symbol) {
    Widget row(
      String icon,
      Color iconColor,
      String title,
      String subtitle,
      VoidCallback onTap, {
      bool enabled = true,
    }) {
      return GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(sfIcon(icon), size: 20, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: title == 'Clear All Data'
                              ? ExpndColors.red
                              : oc.text,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11, color: oc.muted),
                      ),
                    ],
                  ),
                ),
                Icon(sfIcon('chevron.right'), size: 12, color: oc.dimmed),
              ],
            ),
          ),
        ),
      );
    }

    final count = store.transactions.length;
    final hasAnything =
        count > 0 ||
        store.accounts.isNotEmpty ||
        store.goals.isNotEmpty ||
        store.emis.isNotEmpty;
    return Column(
      children: [
        // Everything lives on this device and nowhere else, so a backup file
        // is the only thing standing between the user and a total loss.
        // Listed first for that reason.
        row(
          'lock.shield.fill',
          ExpndColors.gold,
          'Back Up Everything',
          'Accounts, budgets, goals, EMIs, receipts',
          () => _backup(store),
          enabled: hasAnything,
        ),
        sectionDivider(oc),
        _autoBackupRow(oc, store),
        sectionDivider(oc),
        row(
          'arrow.down.circle.fill',
          ExpndColors.green,
          'Restore Backup',
          'Replaces everything from a backup file',
          () => _restore(store),
        ),
        sectionDivider(oc),
        row(
          'square.and.arrow.up',
          ExpndColors.gold,
          'Import Transactions',
          'Load from CSV file',
          () => _importCSV(store),
        ),
        sectionDivider(oc),
        row(
          'square.and.arrow.up',
          ExpndColors.green,
          'Export Transactions',
          'Transactions only — use Back Up for everything',
          () => _exportCSV(store),
          enabled: count > 0,
        ),
        sectionDivider(oc),
        row(
          'doc.on.doc',
          ExpndColors.gold,
          'Monthly Statement',
          'A readable summary of a month, ready to share',
          () => _exportStatement(store),
          enabled: count > 0,
        ),
        sectionDivider(oc),
        row(
          'trash.fill',
          ExpndColors.red,
          'Clear All Data',
          '$count transaction${count == 1 ? "" : "s"} will be removed',
          () => _confirmClear(store),
          enabled: count > 0,
        ),
      ],
    );
  }

  // ── Backup / restore ──────────────────────────────────────────────────────

  /// Automatic snapshots, with how long it has been since the last one.
  ///
  /// The staleness line is the point of the row: a backup feature nobody looks
  /// at is indistinguishable from no backup at all, so the screen says out
  /// loud when the last one was and offers to take one now.
  Widget _autoBackupRow(ExpndColors oc, AppStore store) {
    final settings = context.watch<SettingsStore>();
    final last = settings.lastAutoBackupAt;
    final on = settings.autoBackupEnabled;

    String subtitle() {
      if (!on) return 'Off — only manual backups are kept';
      if (last == null) return 'No snapshot yet';
      final days = DateTime.now().difference(last).inDays;
      if (days == 0) return 'Last snapshot today';
      if (days == 1) return 'Last snapshot yesterday';
      return 'Last snapshot $days days ago';
    }

    final stale =
        on && (last == null || DateTime.now().difference(last).inDays >= 3);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                sfIcon('clock.fill'),
                size: 20,
                color: stale ? ExpndColors.red : ExpndColors.green,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Automatic Snapshots',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: oc.text,
                      ),
                    ),
                    Text(
                      subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: stale ? ExpndColors.red : oc.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: on,
                activeThumbColor: oc.accent,
                onChanged: (v) {
                  Haptics.light();
                  settings.autoBackupEnabled = v;
                },
              ),
            ],
          ),
        ),
        if (on)
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 16, 12),
            child: Row(
              children: [
                _miniButton(oc, 'Snapshot now', () => _snapshotNow(store)),
                const SizedBox(width: 8),
                _miniButton(oc, 'Restore a snapshot', _restoreSnapshot),
              ],
            ),
          ),
      ],
    );
  }

  Widget _miniButton(ExpndColors oc, String label, VoidCallback onTap) {
    return Flexible(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: ExpndColors.gold.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: oc.accent,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _snapshotNow(AppStore store) async {
    Haptics.light();
    final settings = context.read<SettingsStore>();
    final dir = await getApplicationDocumentsDirectory();
    final file = await writeAutoBackup(store, settings, dir);
    if (!mounted) return;
    _snack(file == null ? "Couldn't write a snapshot" : 'Snapshot saved');
  }

  /// Restores from a snapshot the app took itself — no file picker, because
  /// the whole point is that it is already here.
  Future<void> _restoreSnapshot() async {
    Haptics.light();
    final oc = context.oc;
    final dir = await getApplicationDocumentsDirectory();
    final files = listAutoBackups(dir);
    if (!mounted) return;
    if (files.isEmpty) {
      _snack('No snapshots yet');
      return;
    }

    final chosen = await showModalBottomSheet<File>(
      context: context,
      backgroundColor: oc.surface,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(
              'RESTORE A SNAPSHOT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: oc.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Replaces everything currently in the app',
              style: TextStyle(fontSize: 11, color: oc.muted),
            ),
            const SizedBox(height: 10),
            for (final f in files)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(sheetCtx).pop(f),
                child: Container(
                  width: double.infinity,
                  color: Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Icon(sfIcon('clock.fill'), size: 15, color: oc.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _snapshotLabel(f),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: oc.text,
                          ),
                        ),
                      ),
                      Icon(sfIcon('chevron.right'), size: 12, color: oc.dimmed),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await _restoreFromFile(chosen);
  }

  /// "Jul 24, 2026 · 21:04" out of an expnd-YYYYMMDD-HHMMSS.json filename,
  /// falling back to the file's own timestamp if the name is unexpected.
  String _snapshotLabel(File f) {
    final name = f.uri.pathSegments.last;
    final m = RegExp(r'(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})').firstMatch(name);
    final when = m == null
        ? f.statSync().modified
        : DateTime(
            int.parse(m.group(1)!),
            int.parse(m.group(2)!),
            int.parse(m.group(3)!),
            int.parse(m.group(4)!),
            int.parse(m.group(5)!),
          );
    return '${_shortDate(when)} · '
        '${when.hour.toString().padLeft(2, '0')}:'
        '${when.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _backup(AppStore store) async {
    final settings = context.read<SettingsStore>();
    try {
      final data = buildBackup(store, settings);
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now();
      final name =
          'expnd-backup-${stamp.year}-'
          '${stamp.month.toString().padLeft(2, '0')}-'
          '${stamp.day.toString().padLeft(2, '0')}.json';
      final file = File('${dir.path}/$name');
      await file.writeAsString(jsonEncode(data));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text:
              'EXPND backup — keep this file safe. '
              'Restoring it brings everything back.',
        ),
      );
    } catch (e) {
      if (mounted) _snack('Backup failed: $e');
    }
  }

  Future<void> _restore(AppStore store) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;
    await _restoreFromFile(File(result.files.single.path!));
  }

  /// Confirms, then replaces everything with the contents of [file].
  ///
  /// Shared by both doors into restore — the file picker and the snapshot
  /// list — so a snapshot can never be applied with less ceremony than an
  /// imported file. For the data currently in the app, either is a delete.
  Future<void> _restoreFromFile(File file) async {
    final store = context.read<AppStore>();
    final String content;
    try {
      content = await file.readAsString();
    } catch (_) {
      if (mounted) _snack('Couldn\'t read that file.');
      return;
    }
    if (!mounted) return;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.oc.surface,
      builder: (sheet) {
        final oc = sheet.oc;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Restore this backup?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: oc.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Everything currently in EXPND is replaced by the '
                  'contents of the file. This cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: oc.muted),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheet).pop(true),
                    child: Text(
                      'Replace Everything',
                      style: TextStyle(
                        color: ExpndColors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheet).pop(false),
                    child: Text('Cancel', style: TextStyle(color: oc.muted)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (ok != true || !mounted) return;

    final settings = context.read<SettingsStore>();
    final dir = await getApplicationDocumentsDirectory();
    try {
      final summary = await restoreBackup(content, store, settings, dir);
      Haptics.success();
      if (!mounted) return;
      _snack(
        'Restored ${summary.transactions} transaction'
        '${summary.transactions == 1 ? "" : "s"}, '
        '${summary.accounts} account${summary.accounts == 1 ? "" : "s"}'
        '${summary.photos > 0 ? ', ${summary.photos} receipt${summary.photos == 1 ? "" : "s"}' : ''}.',
      );
    } on BackupException catch (e) {
      Haptics.warning();
      if (mounted) _snack(e.message);
    } catch (_) {
      Haptics.warning();
      if (mounted) _snack('That backup couldn\'t be restored.');
    }
  }

  /// Shares a readable statement for a chosen month.
  ///
  /// Offers the months that actually have transactions in them, newest first —
  /// a date picker would happily let you export an empty March.
  Future<void> _exportStatement(AppStore store) async {
    Haptics.light();
    final oc = context.oc;
    final months = <DateTime>{
      for (final t in store.transactions) DateTime(t.date.year, t.date.month),
    }.toList()..sort((a, b) => b.compareTo(a));
    if (months.isEmpty) return;

    final chosen = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: oc.surface,
      builder: (sheetCtx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const SizedBox(height: 14),
            Center(
              child: Text(
                'STATEMENT FOR',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: oc.text,
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (final m in months.take(24))
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(sheetCtx).pop(m),
                child: Container(
                  width: double.infinity,
                  color: Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Icon(sfIcon('calendar'), size: 15, color: oc.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _statementMonthLabel(m),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: oc.text,
                          ),
                        ),
                      ),
                      Icon(sfIcon('chevron.right'), size: 12, color: oc.dimmed),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    final settings = context.read<SettingsStore>();
    final bytes = await buildMonthlyStatementPdf(
      store,
      settings.currencyCode,
      chosen,
      userName: settings.userName,
    );
    final dir = await getTemporaryDirectory();
    final name =
        'expnd-statement-${chosen.year}-${chosen.month.toString().padLeft(2, '0')}.pdf';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'EXPND statement — ${_statementMonthLabel(chosen)}',
      ),
    );
  }

  String _statementMonthLabel(DateTime m) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${names[m.month - 1]} ${m.year}';
  }

  Future<void> _exportCSV(AppStore store) async {
    final buf = StringBuffer('Date,Category,Type,Amount,Note\n');
    for (final t in store.transactions) {
      buf.write(
        '${_csv(t.date.toIso8601String())},${_csv(t.category.raw)},'
        '${_csv(t.type.raw)},${t.amount.toStringAsFixed(2)},${_csv(t.note)}\n',
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/expnd-transactions.csv');
    await file.writeAsString(buf.toString());
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'EXPND transactions export'),
    );
  }

  Future<void> _importCSV(AppStore store) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (result == null || result.files.single.path == null) return;
    final content = await File(result.files.single.path!).readAsString();
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map(_parseCsvLine)
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length < 2) {
      _snack('No valid rows found.');
      return;
    }
    var added = 0;
    for (final line in lines.skip(1)) {
      final cols = line;
      if (cols.length < 4) continue;
      final date = _parseDate(cols[0].trim());
      final amount = double.tryParse(cols[3].trim());
      if (date == null || amount == null || amount <= 0) continue;
      final type = TransactionType.fromRaw(
        cols[2].trim().isEmpty
            ? null
            : cols[2].trim()[0].toUpperCase() +
                  cols[2].trim().substring(1).toLowerCase(),
      );
      final cat = TransactionCategory.values.firstWhere(
        (c) => c.raw.toLowerCase() == cols[1].trim().toLowerCase(),
        orElse: () => TransactionCategory.other,
      );
      final custom = store.customCategories
          .where((c) => c.name.toLowerCase() == cols[1].trim().toLowerCase())
          .firstOrNull;
      store.addTransaction(
        Transaction(
          note: cols.length >= 5 ? cols[4].trim() : '',
          amount: amount,
          category: cat,
          type: type,
          date: date,
          customCategoryId: custom?.id,
        ),
      );
      added++;
    }
    Haptics.success();
    _snack(added > 0 ? 'Imported $added transactions' : 'No valid rows found.');
  }

  String _csv(String value) {
    final escaped = value.replaceAll('"', '""');
    return RegExp(r'[,"\r\n]').hasMatch(value) ? '"$escaped"' : escaped;
  }

  List<String> _parseCsvLine(String line) {
    final out = <String>[];
    final field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (ch == ',' && !quoted) {
        out.add(field.toString().trim());
        field.clear();
      } else {
        field.write(ch);
      }
    }
    if (field.isNotEmpty || out.isNotEmpty) out.add(field.toString().trim());
    return out;
  }

  DateTime? _parseDate(String s) {
    // try ISO / common formats
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    // MMM d, yyyy  e.g. "Jan 5, 2026"
    final m = RegExp(r'^(\w{3}) (\d{1,2}), (\d{4})$').firstMatch(s);
    if (m != null) {
      const months = {
        'Jan': 1,
        'Feb': 2,
        'Mar': 3,
        'Apr': 4,
        'May': 5,
        'Jun': 6,
        'Jul': 7,
        'Aug': 8,
        'Sep': 9,
        'Oct': 10,
        'Nov': 11,
        'Dec': 12,
      };
      final mm = months[m.group(1)];
      if (mm != null) {
        return DateTime(int.parse(m.group(3)!), mm, int.parse(m.group(2)!));
      }
    }
    // MM/dd/yyyy
    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s);
    if (slash != null) {
      return DateTime(
        int.parse(slash.group(3)!),
        int.parse(slash.group(1)!),
        int.parse(slash.group(2)!),
      );
    }
    return null;
  }

  void _confirmClear(AppStore store) {
    final oc = context.oc;
    final count = store.transactions.length;
    showModalBottomSheet(
      context: context,
      backgroundColor: oc.surface,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Clear all transactions?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: oc.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This will permanently delete $count transaction${count == 1 ? "" : "s"}. This cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: oc.muted),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    for (final t in store.transactions) {
                      store.deleteTransaction(t);
                    }
                    Haptics.warning();
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Clear All Data',
                    style: TextStyle(
                      color: ExpndColors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: TextStyle(color: oc.muted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _shortDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

/// The header avatar: the user's initial, tapped to open [SettingsView].
///
/// Profile used to be a bottom tab, which put a screen you visit rarely beside
/// the ones you open daily. It lives up here now — the spot every other
/// finance app reserves for identity — and the freed tab went to PLAN.
class SettingsAvatarAction extends StatelessWidget {
  const SettingsAvatarAction({super.key});

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final name = context.watch<SettingsStore>().userName.trim();
    // 'Your Name' is the setup screen's placeholder, not a name: showing its
    // "Y" made the avatar look like someone else's.
    final initial = name.isNotEmpty && name != 'Your Name'
        ? name.characters.first.toUpperCase()
        : '?';
    return HeaderAction.custom(
      semanticLabel: 'Profile and settings',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.light();
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SettingsView()));
        },
        // HeaderAction supplies the disc, so the initial sits on the same
        // shape as every other header button.
        child: SizedBox.expand(
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: oc.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
