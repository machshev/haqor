import 'dart:math' show min;

import 'package:flutter/material.dart';

class ChapterSelectorSheet extends StatelessWidget {
  const ChapterSelectorSheet({
    super.key,
    required this.total,
    required this.current,
  });
  final int total;
  final int current;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);

    const gap = 3.0;
    const minTile = 22.0;
    const maxTile = 48.0;
    // Usable width: screen minus 12px padding each side
    final availW = mq.size.width - 24.0;
    // Usable height: ~92% of screen, minus safe areas, minus handle+padding overhead
    final availH =
        mq.size.height * 0.92 - mq.padding.top - mq.padding.bottom - 60;

    // Find the column count that maximises tile size while fitting all chapters.
    // As columns increase: tileW shrinks, rows shrink so tileH grows.
    // The optimum is at the crossing point of tileW and tileH.
    double bestTile = 0;
    for (int c = 1; c <= total; c++) {
      final tW = (availW + gap) / c - gap;
      if (tW < minTile) break; // further columns only make tiles smaller
      final rows = (total / c).ceil();
      final tH = (availH + gap) / rows - gap;
      final t = min(tW, tH);
      if (t > bestTile) {
        bestTile = t;
      }
    }
    final tileSize = bestTile.clamp(minTile, maxTile);
    final fontSize = (tileSize * 0.38).clamp(9.0, 16.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        16 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (int ch = 1; ch <= total; ch++)
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(ch),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: tileSize,
                    height: tileSize,
                    decoration: BoxDecoration(
                      color: ch == current
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Center(
                      child: Text(
                        '$ch',
                        style: TextStyle(
                          fontSize: fontSize,
                          color: ch == current
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                          fontWeight: ch == current
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
