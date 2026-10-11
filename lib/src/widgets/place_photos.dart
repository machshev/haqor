import 'package:flutter/material.dart';

import '../bindings/bindings.dart';
import '../external_link.dart';
import 'side_scroll.dart';

/// OpenBible.info's licence code as a reader would write it: `CC-BY-SA-4.0`
/// is "CC BY-SA 4.0", `PD` "public domain".
String licenseLabel(String code) => switch (code) {
  'PD' || 'CC-PD-Mark' => 'public domain',
  'CC-Zero' => 'CC0',
  'attribution' => 'attribution',
  _ when code.startsWith('CC-') =>
    'CC ${code.substring(3).replaceFirstMapped(RegExp(r'-(\d)'), (m) => ' ${m[1]}')}',
  _ => code,
};

/// The photo's credit line: who took it and under what licence.
String photoCredit(PlaceImageEntry photo) => [
  if (photo.credit.isNotEmpty) photo.credit,
  if (photo.license.isNotEmpty) licenseLabel(photo.license),
].join(' · ');

Color? _hexColor(String hex) {
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

/// What stands in for a photo while it loads, or when it cannot (offline):
/// OpenBible.info's colours for it, top to bottom, or the surface's.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.photo, this.failed = false});

  final PlaceImageEntry photo;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = photo.placeholder.map(_hexColor).nonNulls.toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        gradient: colors.length > 1
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors,
              )
            : null,
      ),
      child: failed
          ? Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: scheme.onSurfaceVariant,
              ),
            )
          : const SizedBox.expand(),
    );
  }
}

Widget _photo(PlaceImageEntry photo, String url, BoxFit fit) => Image.network(
  url,
  fit: fit,
  frameBuilder: (context, child, frame, sync) => Stack(
    fit: StackFit.passthrough,
    children: [
      if (frame == null && !sync) _Placeholder(photo: photo),
      AnimatedOpacity(
        opacity: frame == null && !sync ? 0 : 1,
        duration: const Duration(milliseconds: 200),
        child: child,
      ),
    ],
  ),
  errorBuilder: (context, _, _) => _Placeholder(photo: photo, failed: true),
);

/// A strip of photographs of the sites a place may have been, each with
/// what it shows; tapping one opens it alone, with its credit.
class PlacePhotoStrip extends StatelessWidget {
  const PlacePhotoStrip({
    super.key,
    required this.photos,
    required this.siteLabel,
  });

  final List<PlaceImageEntry> photos;

  /// The name of the site a photo shows, by [PlaceImageEntry.location].
  final String Function(int location) siteLabel;

  static const double height = 168;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: SideScroll.builder(
        builder: (context, controller) => ListView.separated(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 10),
          itemCount: photos.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final photo = photos[i];
            final aspect = photo.width > 0 && photo.height > 0
                ? (photo.width / photo.height).clamp(0.75, 1.8)
                : 4 / 3;
            return Semantics(
              button: true,
              label: photo.description,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: (height - 36) * aspect,
                  child: Material(
                    color: theme.colorScheme.surfaceContainerLow,
                    child: InkWell(
                      onTap: () => showPlacePhoto(
                        context,
                        photo,
                        siteLabel(photo.location),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _photo(
                              photo,
                              photo.thumbnailUrl,
                              BoxFit.cover,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                            child: Text(
                              photo.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One photograph shown large, with what it shows, the site it is of, its
/// credit and licence, and its page on Wikimedia Commons.
Future<void> showPlacePhoto(
  BuildContext context,
  PlaceImageEntry photo,
  String site,
) => showDialog<void>(
  context: context,
  builder: (context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: AspectRatio(
                aspectRatio: photo.width > 0 && photo.height > 0
                    ? photo.width / photo.height
                    : 4 / 3,
                child: InteractiveViewer(
                  maxScale: 4,
                  child: _photo(photo, photo.largeUrl, BoxFit.contain),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(photo.description, style: theme.textTheme.titleSmall),
                  if (site.isNotEmpty && !photo.description.contains(site))
                    Text(site, style: muted),
                  const SizedBox(height: 4),
                  Text(
                    'Photo: ${photoCredit(photo)}, via Wikimedia Commons',
                    style: muted,
                  ),
                ],
              ),
            ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Wikimedia Commons'),
                  onPressed: () => openExternalLink(Uri.parse(photo.pageUrl)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  },
);
