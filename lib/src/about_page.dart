import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import 'app_info.dart';
import 'bindings/bindings.dart';
import 'db_version.dart';

/// Show the About sheet: app and database versions, and the credits for the
/// bundled data. Several of those sources are used under licences that require
/// attribution, so this view is the app-side half of that obligation (the
/// other half is the Attribution section of the README).
Future<void> showAbout(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * 0.72,
  ),
  builder: (_) => const _AboutSheet(),
);

class _AboutSheet extends StatefulWidget {
  const _AboutSheet();

  @override
  State<_AboutSheet> createState() => _AboutSheetState();
}

class _AboutSheetState extends State<_AboutSheet> {
  StreamSubscription<RustSignalPack<BuildInfo>>? _buildInfoSub;

  /// Reported by the core, not assumed by the app: the Rust crate version and
  /// the build stamp of the database it actually opened.
  String? _coreVersion;
  String? _dataVersion;

  /// The bundled build stamp, which is what the core reports once the runtime
  /// database carries a `meta` table. Until then it is all there is.
  String? _bundledVersion;

  @override
  void initState() {
    super.initState();
    _buildInfoSub = BuildInfo.rustSignalStream.listen(_onBuildInfo);
    GetBuildInfo().sendSignalToRust();
    unawaited(
      bundledDbVersion().then((version) {
        if (mounted) setState(() => _bundledVersion = version);
      }),
    );
  }

  @override
  void dispose() {
    _buildInfoSub?.cancel();
    super.dispose();
  }

  void _onBuildInfo(RustSignalPack<BuildInfo> pack) {
    if (!mounted) return;
    setState(() {
      _coreVersion = pack.message.coreVersion;
      final reported = pack.message.dataVersion;
      _dataVersion = reported.isEmpty ? null : reported;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text('Haqor', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Read the Hebrew Bible.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _VersionRow(label: 'App version', value: appVersion),
        _VersionRow(label: 'Core version', value: _coreVersion ?? '…'),
        _VersionRow(
          label: 'Database build',
          value: _dataVersion ?? _bundledVersion ?? '…',
        ),
        const SizedBox(height: 24),
        Text('Data sources', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final credit in dataSourceCredits) _CreditTile(credit: credit),
      ],
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditTile extends StatelessWidget {
  const _CreditTile({required this.credit});

  final DataSourceCredit credit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(credit.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(credit.description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 2),
          Text(credit.licence, style: muted),
          if (credit.url != null) SelectableText(credit.url!, style: muted),
          if (credit.note != null) ...[
            const SizedBox(height: 6),
            // The SEDRA terms prescribe the wording of the acknowledgement, so
            // it is quoted rather than paraphrased.
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 3,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
                child: Text(
                  credit.note!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
