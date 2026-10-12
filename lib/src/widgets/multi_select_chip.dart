import 'package:flutter/material.dart';

/// One choice in a [MultiSelectChip]'s menu.
class MultiSelectOption<T> {
  const MultiSelectOption(this.value, this.label, {this.heading});

  final T value;
  final String label;

  /// The heading this choice begins, if it begins one.
  final String? heading;
}

/// A chip naming a filter's choices, whose menu ticks any number of them and
/// stays open while they are ticked; none ticked is every one.
class MultiSelectChip<T> extends StatelessWidget {
  const MultiSelectChip({
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.allLabel,
    required this.plural,
    this.icon,
    super.key,
  });

  final List<MultiSelectOption<T>> options;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;

  /// The chip's label, and the menu's first item, for none ticked.
  final String allLabel;

  /// The chip's label for [count] ticked, more than one.
  final String Function(int count) plural;

  final IconData? icon;

  String get _label => switch (selected.length) {
    0 => allLabel,
    1 => options.firstWhere((o) => o.value == selected.single).label,
    final n => plural(n),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MenuAnchor(
      menuChildren: [
        CheckboxMenuButton(
          value: selected.isEmpty,
          closeOnActivate: false,
          onChanged: (_) => onChanged({}),
          child: Text(allLabel),
        ),
        for (final o in options) ...[
          if (o.heading case final heading?) ...[
            const Divider(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Text(
                heading,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
          CheckboxMenuButton(
            value: selected.contains(o.value),
            closeOnActivate: false,
            onChanged: (on) => onChanged(
              on! ? {...selected, o.value} : ({...selected}..remove(o.value)),
            ),
            child: Text(o.label),
          ),
        ],
      ],
      builder: (context, controller, _) => InputChip(
        avatar: icon == null ? null : Icon(icon, size: 18),
        label: Text(_label),
        selected: selected.isNotEmpty,
        showCheckmark: false,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        onDeleted: selected.isEmpty ? null : () => onChanged({}),
        deleteButtonTooltipMessage: allLabel,
      ),
    );
  }
}
