import 'dart:async';

import 'package:flutter/services.dart';

/// The embedder does not expose a synchronous getter for the current system
/// UI mode.  Keep the app-owned value in one small coordinator so a reader can
/// restore the mode that was active before it was pushed.  Callers outside the
/// coordinator should use [setTrackedSystemUiMode] as well.
class TrackedSystemUiState {
  const TrackedSystemUiState(this.mode, this.overlays);

  final SystemUiMode mode;
  final List<SystemUiOverlay> overlays;

  TrackedSystemUiState copy() =>
      TrackedSystemUiState(mode, List<SystemUiOverlay>.of(overlays));
}

TrackedSystemUiState _currentSystemUi = TrackedSystemUiState(
  SystemUiMode.edgeToEdge,
  List<SystemUiOverlay>.of(SystemUiOverlay.values),
);

Future<void> setTrackedSystemUiMode(
  SystemUiMode mode, {
  List<SystemUiOverlay>? overlays,
}) async {
  final effectiveOverlays = List<SystemUiOverlay>.of(
    overlays ?? _currentSystemUi.overlays,
  );
  final state = TrackedSystemUiState(mode, effectiveOverlays);
  _currentSystemUi = state;
  await _enqueueSystemUi(state);
}

TrackedSystemUiState currentTrackedSystemUiMode() => _currentSystemUi.copy();

// Platform channel calls are asynchronous. Serializing them is important for
// a reader lease: an enter/full-screen call that started before dispose must
// complete before the release restore is sent, otherwise the late enter can
// put the app back into full-screen after the route has gone away.
Future<void> _systemUiTail = Future<void>.value();

Future<void> _enqueueSystemUi(TrackedSystemUiState state) {
  final operation = _systemUiTail.then<void>((_) {
    return SystemChrome.setEnabledSystemUIMode(
      state.mode,
      overlays: state.mode == SystemUiMode.manual ? state.overlays : null,
    );
  });
  // Keep the queue usable after a platform failure while preserving the
  // failure for the caller awaiting this particular operation.
  _systemUiTail = operation.then<void>(
    (_) {},
    onError: (Object _, StackTrace __) {},
  );
  return operation;
}

class ReaderSystemUiLease {
  ReaderSystemUiLease._(this._entry);

  final _ReaderUiEntry _entry;

  Future<void> setFullScreen(bool fullScreen) {
    if (_entry.released) {
      return Future<void>.value();
    }
    return setTrackedSystemUiMode(
      fullScreen ? SystemUiMode.manual : SystemUiMode.edgeToEdge,
      overlays: fullScreen ? const <SystemUiOverlay>[] : SystemUiOverlay.values,
    );
  }

  Future<void> release() async {
    if (_entry.released) {
      return;
    }
    _entry.released = true;
    await _releaseEntriesFromTop();
  }
}

class _ReaderUiEntry {
  _ReaderUiEntry(this.previous);

  final TrackedSystemUiState previous;
  bool released = false;
}

final List<_ReaderUiEntry> _readerUiEntries = <_ReaderUiEntry>[];

Future<void> _releaseEntriesFromTop() {
  Future<void> last = Future<void>.value();
  while (_readerUiEntries.isNotEmpty && _readerUiEntries.last.released) {
    final entry = _readerUiEntries.removeLast();
    _currentSystemUi = entry.previous.copy();
    last = _enqueueSystemUi(_currentSystemUi);
  }
  return last;
}

ReaderSystemUiLease enterReaderSystemUi({required bool fullScreen}) {
  final entry = _ReaderUiEntry(_currentSystemUi.copy());
  _readerUiEntries.add(entry);
  final lease = ReaderSystemUiLease._(entry);
  unawaited(lease.setFullScreen(fullScreen).catchError((_) {}));
  return lease;
}
