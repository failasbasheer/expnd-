import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/currencies.dart';
import '../theme/expnd_theme.dart';

/// A single field surface: currency is a label, the number is the input.
/// Explicit decorations prevent the app theme from nesting a second box inside.
class MoneyField extends StatefulWidget {
  final TextEditingController controller;
  final String currencyCode;
  final String label;
  final ValueChanged<String>? onChanged;
  final bool prominent;
  final bool autofocus;
  final Widget? trailing;
  final bool error;
  final List<TextInputFormatter>? inputFormatters;

  const MoneyField({
    super.key,
    required this.controller,
    required this.currencyCode,
    required this.label,
    this.onChanged,
    this.prominent = false,
    this.autofocus = false,
    this.trailing,
    this.error = false,
    this.inputFormatters,
  });

  @override
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final decimals = currencyDecimalDigits(widget.currencyCode);
    final hint = decimals == 0 ? '0' : '0.${'0' * decimals}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: oc.surface,
        borderRadius: BorderRadius.circular(ExpndRadius.button),
        border: Border.all(
          color: widget.error
              ? ExpndColors.red
              : _focus.hasFocus
              ? oc.accent
              : oc.border,
          width: _focus.hasFocus || widget.error ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Text(
              currencySymbol(widget.currencyCode),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: oc.muted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              label: '${widget.label}, ${widget.currencyCode}',
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: decimals > 0,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _focus.unfocus(),
                onChanged: widget.onChanged,
                inputFormatters:
                    widget.inputFormatters ??
                    [AmountInputFormatter(decimalDigits: decimals)],
                style: TextStyle(
                  fontSize: widget.prominent ? 32 : 20,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: oc.text,
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                    color: oc.dimmed,
                    fontWeight: FontWeight.w400,
                  ),
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          if (_focus.hasFocus)
            IconButton(
              tooltip: 'Done entering ${widget.label.toLowerCase()}',
              onPressed: _focus.unfocus,
              icon: Icon(Icons.check, size: 20, color: oc.accent),
            ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}
