/// The boot screen belongs to the web build: `web/index.html` paints it before
/// any Dart runs, because there the runtime, the engine and the database all
/// arrive over the network. A native build shows its platform's own splash and
/// opens the database from local storage, so every one of these is a no-op.
library;

void reportBootStatus(String message, {double? progress, String? detail}) {}

void reportBootFailure(String message, {String? detail}) {}

void bootFinished() {}
