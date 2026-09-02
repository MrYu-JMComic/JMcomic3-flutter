/// Runtime backend injection point used during the MethodChannel -> FRB
/// migration. The default is null, so legacy platform channels remain the
/// safe fallback on builds that do not bundle the private Rust bridge.
typedef BackendInvoker = Future<String> Function(String method, dynamic params);

class BackendInvokerRegistry {
  BackendInvokerRegistry._();

  static BackendInvoker? _handler;

  static BackendInvoker? get handler => _handler;

  /// Install a backend implementation before the first API call.
  static void install(BackendInvoker handler) {
    _handler = handler;
  }

  /// Restore the platform-channel backend, primarily for tests and logout of
  /// an experimental bridge.
  static void reset() {
    _handler = null;
  }
}
