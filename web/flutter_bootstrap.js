{{flutter_js}}
{{flutter_build_config}}

// The index page owns service-worker registration so the offline cache and
// cross-origin-isolation headers always come from the same worker.
// Exercise Firefox's JavaScript fallback in release smoke tests on Chrome.
const haqorForceDart2js = new URLSearchParams(window.location.search).has('test-dart2js');
_flutter.loader.load({
  config: haqorForceDart2js ? {wasmAllowList: {blink: false, gecko: false}} : {},
});
