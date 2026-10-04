import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/app_store.dart';
import '../store/settings_store.dart';
import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import 'neopop.dart';

/// Rename / delete a tag from anywhere. Tags are typed by hand, so
/// "japan"/"Japan"/"Japan Trip" pile up as three things; `renameTag`/`deleteTag`
/// already exist on the store, this is the shared way in (History tag chips and
/// the Profile tag list both call it).
///
/// [onRenamed]/[onDeleted] let a caller sync local state — e.g. History keeps
/// its active tag filter pointed at the renamed tag, or clears it on delete.
Future<void> showTagManager(
  BuildContext context,
  String tag, {
  void Function(String newName)? onRenamed,
  VoidCallback? onDeleted,
}) async {
  Haptics.light();
  final oc = context.oc;
  final store = context.read<AppStore>();
  final code = context.read<SettingsStore>().currencyCode;
  final count = store.transactionsWithTag(tag).length;

  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: oc.surface,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Text(
            '#${tag.toUpperCase()}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: oc.text,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$count transaction${count == 1 ? '' : 's'} · '
            '${formatCurrency(store.spentOnTag(tag), code)}',
            style: TextStyle(fontSize: 11, color: oc.muted),
          ),
          const SizedBox(height: 14),
          _actionRow(sheetCtx, 'pencil', 'Rename tag', 'rename', oc.text),
          _actionRow(
            sheetCtx,
            'trash',
            'Delete tag',
            'delete',
            ExpndColors.red,
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  if (action == 'rename') {
    await _renameSheet(context, store, tag, onRenamed);
  } else if (action == 'delete') {
    await _confirmDelete(context, store, tag, onDeleted);
  }
}

Widget _actionRow(
  BuildContext sheetCtx,
  String icon,
  String label,
  String value,
  Color color,
) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {
      Haptics.light();
      Navigator.of(sheetCtx).pop(value);
    },
    child: Container(
      width: double.infinity,
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
      child: Row(
        children: [
          Icon(sfIcon(icon), size: 16, color: color),
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _renameSheet(
  BuildContext context,
  AppStore store,
  String tag,
  void Function(String)? onRenamed,
) async {
  final oc = context.oc;
  final ctrl = TextEditingController(text: tag);
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      final insets = MediaQuery.of(sheetCtx).viewInsets.bottom;
      return Container(
        margin: EdgeInsets.only(bottom: insets),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: oc.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: oc.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'RENAME TAG',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: oc.text,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: oc.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: oc.border, width: 1.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.of(sheetCtx).pop(v.trim()),
                style: TextStyle(fontSize: 14, color: oc.text),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                  hintText: 'Tag name',
                ),
              ),
            ),
            const SizedBox(height: 16),
            NeoPopButton(
              onPressed: () => Navigator.of(sheetCtx).pop(ctrl.text.trim()),
              enabled: true,
              faceColor: ExpndColors.gold,
              depthColor: ExpndColors.goldDark,
              depth: 4,
              cornerRadius: 6,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Center(
                    child: Text(
                      'SAVE',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: ExpndColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  ctrl.dispose();
  final target = (result ?? '').trim();
  if (target.isEmpty || target == tag) return;
  store.renameTag(tag, target);
  onRenamed?.call(target);
  Haptics.success();
}

Future<void> _confirmDelete(
  BuildContext context,
  AppStore store,
  String tag,
  VoidCallback? onDeleted,
) async {
  final oc = context.oc;
  final count = store.transactionsWithTag(tag).length;
  await showModalBottomSheet(
    context: context,
    backgroundColor: oc.surface,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Delete #$tag?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: oc.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              count == 0
                  ? "This tag isn't used anywhere."
                  : 'Removed from $count transaction${count == 1 ? '' : 's'}. '
                        'The transactions themselves stay. This cannot be undone.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: oc.muted),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  store.deleteTag(tag);
                  onDeleted?.call();
                  Haptics.warning();
                  Navigator.of(sheetCtx).pop();
                },
                child: Text(
                  'Delete',
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
                onPressed: () => Navigator.of(sheetCtx).pop(),
                child: Text('Cancel', style: TextStyle(color: oc.muted)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
