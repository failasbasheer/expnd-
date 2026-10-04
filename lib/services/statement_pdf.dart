import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';
import '../store/app_store.dart';
import '../theme/currencies.dart';
import 'statement.dart';

/// Renders one month's [StatementData] as a branded PDF, styled to match the
/// app's NeoPOP look — ink-black pages, a gold wordmark, a summary of stat
/// tiles, category bars and a full day-grouped ledger.
///
/// Needs the embedded Noto Sans faces (declared in `pubspec.yaml`): the PDF
/// standard fonts can't draw ₹ and most non-Latin currency symbols, but Noto
/// covers them. Amounts are never privacy-masked — a saved document must always
/// carry the real figures.
Future<Uint8List> buildMonthlyStatementPdf(
  AppStore store,
  String code,
  DateTime month, {
  String? userName,
  DateTime? generatedAt,
}) async {
  final d = buildStatementData(
    store,
    code,
    month,
    userName: userName,
    generatedAt: generatedAt,
  );

  final base = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
  );

  // ── Palette (mirrors ExpndColors dark mode) ─────────────────────────────────
  final bg = PdfColor.fromInt(0xFF0D0D0D);
  final card = PdfColor.fromInt(0xFF161616);
  final cardBorder = PdfColor.fromInt(0xFF262626);
  final track = PdfColor.fromInt(0xFF262626);
  final gold = PdfColor.fromInt(0xFFFFEB34);
  final white = PdfColor.fromInt(0xFFFFFFFF);
  final muted = PdfColor.fromInt(0xFF8A8A8A);
  final dim = PdfColor.fromInt(0xFF5A5A5A);
  final green = PdfColor.fromInt(0xFF06C270);
  final red = PdfColor.fromInt(0xFFEE4D37);

  String money(double v) => formatCurrency(v, code, maskable: false);
  final monthLabel = DateFormat('MMMM yyyy').format(month);

  // ── Reusable text styles ────────────────────────────────────────────────────
  pw.TextStyle label(PdfColor c, {double size = 8, double spacing = 1.2}) =>
      pw.TextStyle(
        font: bold,
        fontSize: size,
        color: c,
        letterSpacing: spacing,
      );
  pw.TextStyle body(PdfColor c, {double size = 10, bool strong = false}) =>
      pw.TextStyle(font: strong ? bold : base, fontSize: size, color: c);

  // ── Header ──────────────────────────────────────────────────────────────────
  pw.Widget header() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'EXPND',
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 24,
                  color: gold,
                  letterSpacing: 3,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text('MONTHLY STATEMENT', style: label(muted, spacing: 2)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(monthLabel, style: body(white, size: 15, strong: true)),
              pw.SizedBox(height: 3),
              pw.Text(
                'Generated ${DateFormat('MMM d, yyyy').format(d.generatedAt)}',
                style: body(muted, size: 9),
              ),
              if (d.userName != null && d.userName!.trim().isNotEmpty)
                pw.Text(d.userName!.trim(), style: body(muted, size: 9)),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 12),
      pw.Container(height: 2, color: gold),
    ],
  );

  // ── Summary stat tiles ──────────────────────────────────────────────────────
  pw.Widget tile(String cap, String value, PdfColor valueColor) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: pw.BoxDecoration(
        color: card,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: cardBorder, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(cap, style: label(muted)),
          pw.SizedBox(height: 6),
          pw.Text(value, style: body(valueColor, size: 14, strong: true)),
        ],
      ),
    ),
  );

  pw.Widget summary() => pw.Row(
    children: [
      tile('INCOME', money(d.income), green),
      pw.SizedBox(width: 10),
      tile('EXPENSES', money(d.expenses), white),
      pw.SizedBox(width: 10),
      tile('NET', money(d.net), d.net >= 0 ? gold : red),
    ],
  );

  pw.Widget sectionTitle(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Text(t, style: label(gold, size: 10, spacing: 1.5)),
  );

  // ── A category line: name · proportional bar · share · amount ───────────────
  pw.Widget categoryRow(StatementCategory c) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          flex: 5,
          child: pw.Text(
            c.name,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: body(white),
          ),
        ),
        pw.Expanded(
          flex: 5,
          child: pw.Container(
            height: 7,
            decoration: pw.BoxDecoration(
              color: track,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              children: [
                if (c.sharePct > 0)
                  pw.Expanded(
                    flex: c.sharePct,
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        color: gold,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                    ),
                  ),
                if (c.sharePct < 100)
                  pw.Expanded(flex: 100 - c.sharePct, child: pw.SizedBox()),
              ],
            ),
          ),
        ),
        pw.SizedBox(
          width: 40,
          child: pw.Text(
            '${c.sharePct}%',
            textAlign: pw.TextAlign.right,
            style: body(muted, size: 9),
          ),
        ),
        pw.SizedBox(
          width: 100,
          child: pw.Text(
            money(c.amount),
            textAlign: pw.TextAlign.right,
            style: body(white, size: 10, strong: true),
          ),
        ),
      ],
    ),
  );

  pw.Widget accountRow(StatementAccount a) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            a.name,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: body(white),
          ),
        ),
        pw.Text(money(a.balance), style: body(white, size: 10, strong: true)),
      ],
    ),
  );

  pw.Widget dayHeading(DateTime day) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 11, bottom: 3),
    child: pw.Text(
      DateFormat('EEEE, MMM d').format(day).toUpperCase(),
      style: label(dim, size: 8, spacing: 1),
    ),
  );

  pw.Widget transactionRow(StatementLine line) {
    final (sign, color) = switch (line.type) {
      TransactionType.income => ('+', green),
      TransactionType.expense => ('-', white),
      TransactionType.transfer => ('', muted),
    };
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              line.label,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: body(white),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(
            '$sign${money(line.amount)}',
            style: body(color, size: 10, strong: true),
          ),
        ],
      ),
    );
  }

  // ── Assemble the page body ──────────────────────────────────────────────────
  final content = <pw.Widget>[
    header(),
    pw.SizedBox(height: 18),
    summary(),
    pw.SizedBox(height: 6),
    pw.Text(
      '${d.txnCount} transaction${d.txnCount == 1 ? '' : 's'} this month',
      style: body(muted, size: 9),
    ),
    pw.SizedBox(height: 22),
  ];

  if (d.isEmpty) {
    content.add(
      pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(vertical: 60),
        child: pw.Text(
          'No transactions recorded this month.',
          style: body(muted, size: 11),
        ),
      ),
    );
  } else {
    if (d.categories.isNotEmpty) {
      content
        ..add(sectionTitle('SPENDING BY CATEGORY'))
        ..addAll(d.categories.map(categoryRow))
        ..add(pw.SizedBox(height: 22));
    }
    if (d.accounts.isNotEmpty) {
      content
        ..add(
          sectionTitle(
            'ACCOUNTS AS OF ${DateFormat('MMM d').format(d.generatedAt).toUpperCase()}',
          ),
        )
        ..addAll(d.accounts.map(accountRow))
        ..add(pw.SizedBox(height: 22));
    }
    content.add(sectionTitle('TRANSACTIONS'));
    DateTime? day;
    for (final line in d.lines) {
      final dd = DateTime(line.date.year, line.date.month, line.date.day);
      if (day != dd) {
        content.add(dayHeading(dd));
        day = dd;
      }
      content.add(transactionRow(line));
    }
  }

  final doc = pw.Document(
    title: 'EXPND Statement — $monthLabel',
    author: 'EXPND',
    creator: 'EXPND',
  );

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 40, 34, 32),
        theme: pw.ThemeData.withFont(base: base, bold: bold),
        buildBackground: (ctx) =>
            pw.FullPage(ignoreMargins: true, child: pw.Container(color: bg)),
      ),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          'EXPND  ·  ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: body(dim, size: 8),
        ),
      ),
      build: (ctx) => content,
    ),
  );

  return doc.save();
}
