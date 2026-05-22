import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';

class WordInfoSheet extends StatefulWidget {
  const WordInfoSheet({super.key, required this.word});

  final String word;

  @override
  State<WordInfoSheet> createState() => _WordInfoSheetState();
}

class _WordInfoSheetState extends State<WordInfoSheet> {
  StreamSubscription<RustSignalPack<WordInfo>>? _sub;
  WordInfo? _info;
  final Set<int> _expandedBdb = {};

  @override
  void initState() {
    super.initState();
    _sub = WordInfo.rustSignalStream.listen((pack) {
      if (mounted) {
        setState(() => _info = pack.message);
        _sub?.cancel();
      }
    });
    GetWordInfo(word: widget.word).sendSignalToRust();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _info;

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: info == null
                    ? const Center(child: CircularProgressIndicator())
                    : _buildContent(context, scrollController, info),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    ScrollController scrollController,
    WordInfo info,
  ) {
    final theme = Theme.of(context);

    if (!info.found) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.word,
              style: TextStyle(
                fontFamily: 'Cardo',
                fontFamilyFallback: const ['Noto Serif Hebrew'],
                fontSize: 28,
                color: theme.colorScheme.onSurface,
              ),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 12),
            Text(
              'Not found in database',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      children: [
        // Hebrew word
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            info.word,
            style: TextStyle(
              fontFamily: 'Cardo',
              fontFamilyFallback: const ['Noto Serif Hebrew'],
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
            textDirection: TextDirection.rtl,
          ),
        ),
        if (info.gloss.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            info.gloss,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Morphology',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (info.gender != null) _chip(context, 'Gender', info.gender!),
            if (info.number != null) _chip(context, 'Number', info.number!),
            if (info.prefix != null) _chip(context, 'Prefix', info.prefix!),
            if (info.suffix != null) _chip(context, 'Suffix', info.suffix!),
            if (info.prepositions != null)
              _chip(context, 'Prep', info.prepositions!),
            if (info.article) _chip(context, 'Article', 'ה'),
            if (info.vavCon) _chip(context, 'Vav', 'consecutive'),
          ],
        ),
        if (info.bdbEntries.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'BDB Entries',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          ...info.bdbEntries.indexed.map(
            (entry) {
              final (i, e) = entry;
              final expanded = _expandedBdb.contains(i);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() {
                      if (expanded) {
                        _expandedBdb.remove(i);
                      } else {
                        _expandedBdb.add(i);
                      }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            e.headword,
                            style: TextStyle(
                              fontFamily: 'Cardo',
                              fontFamilyFallback: const ['Noto Serif Hebrew'],
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                            textDirection: TextDirection.rtl,
                          ),
                          if (e.gloss.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '— ${e.gloss}',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ] else
                            const Spacer(),
                          Icon(
                            expanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (expanded && e.contentJson.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _BdbContent(
                        contentJson: e.contentJson,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer.withOpacity(0.7),
              ),
            ),
            TextSpan(
              text: value,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BdbContent extends StatelessWidget {
  const _BdbContent({required this.contentJson});

  final String contentJson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(contentJson) as Map<String, dynamic>;
    } catch (_) {
      return const SizedBox.shrink();
    }
    final senses = data['senses'] as List<dynamic>? ?? [];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: senses
            .map<Widget>(
              (s) => _buildSense(context, s as Map<String, dynamic>, 0),
            )
            .toList(),
      ),
    );
  }

  Widget _buildSense(
    BuildContext context,
    Map<String, dynamic> sense,
    int depth,
  ) {
    final theme = Theme.of(context);
    final num = sense['num'] as String?;
    final form = sense['form'] as String?;
    final definition = sense['definition'] as List<dynamic>?;
    final subSenses = sense['senses'] as List<dynamic>?;

    return Padding(
      padding: EdgeInsets.only(
        left: depth * 12.0,
        bottom: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (form != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                form,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (definition != null)
            RichText(
              text: TextSpan(
                children: [
                  if (num != null)
                    TextSpan(
                      text: '$num ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ..._spansFromDefinition(context, definition),
                ],
              ),
            ),
          if (subSenses != null)
            ...subSenses.map<Widget>(
              (s) => _buildSense(
                context,
                s as Map<String, dynamic>,
                depth + 1,
              ),
            ),
        ],
      ),
    );
  }

  List<InlineSpan> _spansFromDefinition(
    BuildContext context,
    List<dynamic> definition,
  ) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.5,
    );

    return definition.map<InlineSpan>((spanData) {
      final span = spanData as Map<String, dynamic>;
      final text = span['t'] as String? ?? '';
      final bold = span['b'] == true;
      final italic = span['i'] == true;
      final small = span['s'] == true;
      final rtl = span['rtl'] == true;
      final href = span['href'] as String?;

      TextStyle style = (baseStyle ?? const TextStyle()).copyWith(
        fontWeight: bold ? FontWeight.bold : null,
        fontStyle: italic ? FontStyle.italic : null,
        fontSize: small ? (baseStyle?.fontSize ?? 12) * 0.85 : null,
        fontFamily: rtl ? 'Cardo' : null,
        fontFamilyFallback: rtl ? const ['Noto Serif Hebrew'] : null,
        color: href != null ? theme.colorScheme.primary : null,
      );

      return TextSpan(
        text: text,
        style: style,
      );
    }).toList();
  }
}
