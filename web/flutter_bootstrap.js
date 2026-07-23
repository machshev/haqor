{{flutter_js}}
{{flutter_build_config}}

// The index page owns service-worker registration so the offline cache and
// cross-origin-isolation headers always come from the same worker.
_flutter.loader.load();
