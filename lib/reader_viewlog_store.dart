import 'dart:convert';

import 'package:jmcomic3/basic/methods.dart';

/// Durable storage boundary for pending reader view-log snapshots.
///
/// The queue only depends on this small interface so tests and a future native
/// file owner can provide their own atomic storage without changing queue
/// ordering or retry semantics.
abstract interface class ReaderViewlogStore {
  Future<List<Map<String, dynamic>>> read(String key);

  Future<void> write(String key, List<Map<String, dynamic>> events);
}

/// Bounded, versioned storage backed by the existing Rust property store.
///
/// This is an opt-in journal, not the offline image owner. It stores only
/// pending view-log snapshots and never stores URLs, cookies, or image bytes.
class ReaderViewlogPropertyStore implements ReaderViewlogStore {
  static const int schemaVersion = 1;
  static const int maxEvents = 256;
  static const int maxEncodedBytes = 64 * 1024;

  /// Property keys are generated from an internal session id. Keep the key
  /// alphabet narrow so a corrupted id cannot address unrelated properties.
  static String keyForSession(String sessionId) {
    final normalized = sessionId.trim();
    if (normalized.isEmpty ||
        normalized.length > 128 ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(normalized)) {
      throw ArgumentError.value(sessionId, 'sessionId', 'invalid session id');
    }
    return 'reader_viewlog_v$schemaVersion:$normalized';
  }

  static String _validateKey(String key) {
    final normalized = key.trim();
    final prefix = 'reader_viewlog_v$schemaVersion:';
    if (!normalized.startsWith(prefix)) {
      throw ArgumentError.value(key, 'key', 'invalid reader view-log key');
    }
    final sessionId = normalized.substring(prefix.length);
    // Reuse the same allowlist as keyForSession and reject lookalike keys.
    if (keyForSession(sessionId) != normalized) {
      throw ArgumentError.value(key, 'key', 'invalid reader view-log key');
    }
    return normalized;
  }

  @override
  Future<List<Map<String, dynamic>>> read(String key) async {
    key = _validateKey(key);
    final raw = await methods.loadProperty(key);
    if (raw.trim().isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    if (utf8.encode(raw).length > maxEncodedBytes) {
      throw const FormatException('reader view-log journal is too large');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
      // A few old property bridges JSON-encode string values once more.
      if (decoded is String && decoded.trim().isNotEmpty) {
        decoded = jsonDecode(decoded);
      }
    } on FormatException catch (error) {
      throw FormatException('invalid reader view-log journal: $error');
    }
    if (decoded is! Map || decoded['version'] != schemaVersion) {
      throw const FormatException('unsupported reader view-log journal');
    }
    final rawEvents = decoded['events'];
    if (rawEvents is! List) {
      throw const FormatException('invalid reader view-log events');
    }
    final events = <Map<String, dynamic>>[];
    for (final rawEvent in rawEvents) {
      final normalized = _normalizeEvent(rawEvent);
      if (normalized != null) {
        events.add(normalized);
      }
    }
    if (events.length <= maxEvents) {
      return List.unmodifiable(events);
    }
    return List.unmodifiable(events.sublist(events.length - maxEvents));
  }

  @override
  Future<void> write(String key, List<Map<String, dynamic>> events) async {
    key = _validateKey(key);
    final bounded = events
        .map(_normalizeEvent)
        .whereType<Map<String, dynamic>>()
        .toList(growable: true);
    if (bounded.length > maxEvents) {
      bounded.removeRange(0, bounded.length - maxEvents);
    }

    var payload = _encode(bounded);
    // Keep the newest snapshots when unusually long mode/session fields would
    // otherwise exceed the property backend's bounded journal size.
    while (
        bounded.isNotEmpty && utf8.encode(payload).length > maxEncodedBytes) {
      bounded.removeAt(0);
      payload = _encode(bounded);
    }
    await methods.saveProperty(key, bounded.isEmpty ? '' : payload);
  }

  static String _encode(List<Map<String, dynamic>> events) => jsonEncode({
        'version': schemaVersion,
        'events': events,
      });

  static Map<String, dynamic>? _normalizeEvent(dynamic value) {
    if (value is! Map) {
      return null;
    }
    final event = <String, dynamic>{};
    value.forEach((key, rawValue) {
      if (key is String) {
        event[key] = rawValue;
      }
    });
    final page = event['page'];
    final sequence = event['client_sequence'];
    final sessionId = event['session_id'];
    if (page is! int ||
        page < 0 ||
        sequence is! int ||
        sequence <= 0 ||
        sessionId is! String ||
        sessionId.trim().isEmpty) {
      return null;
    }
    event['page'] = page;
    event['client_sequence'] = sequence;
    event['session_id'] = sessionId.trim();
    final offset = event['offset'];
    if (offset != null && (offset is! num || !offset.isFinite || offset < 0)) {
      event.remove('offset');
    }
    for (final key in const ['comic_id', 'chapter_id']) {
      final id = event[key];
      if (id != null && (id is! int || id <= 0)) {
        event.remove(key);
      }
    }
    final clientTime = event['client_time_ms'];
    if (clientTime != null && clientTime is! int) {
      event.remove('client_time_ms');
    }
    for (final key in const ['mode', 'direction']) {
      final text = event[key];
      if (text != null && text is! String) {
        event.remove(key);
      }
    }
    return Map.unmodifiable(event);
  }
}
