import 'package:url_launcher/url_launcher.dart';

/// Open [uri] outside the app, in a new tab. Whether it opened.
Future<bool> openExternalLink(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
