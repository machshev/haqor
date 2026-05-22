import 'dart:async';

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
          const SizedBox(height: 8),
          ...info.bdbEntries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  ],
                ],
              ),
            ),
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
