/// Wire request for the versioned page-image batch endpoint.
class JmPageImageRequest {
  final int id;
  final String imageName;

  const JmPageImageRequest(this.id, this.imageName);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'image_name': imageName,
      };
}

/// One item in a batch response. A failed item is represented by [error] and
/// never by a fake or partially written path.
class JmPageImageBatchItem {
  final int id;
  final String? path;
  final int? width;
  final int? height;
  final String? error;

  const JmPageImageBatchItem({
    required this.id,
    this.path,
    this.width,
    this.height,
    this.error,
  });

  bool get succeeded => path != null && error == null;

  /// Convert transport/backend failures to a low-cardinality code.  Backend
  /// messages may contain a signed URL or a local path, so they must never be
  /// copied into UI logs or persisted event payloads.
  static String safeErrorCode(Object? raw) {
    if (raw is FormatException) return 'invalid_response';
    if (raw is StateError) return 'backend_error';
    final type = raw?.runtimeType.toString().toLowerCase() ?? '';
    if (type.contains('timeout')) return 'timeout';
    if (type.contains('platform')) return 'platform_error';
    final message = raw?.toString().toLowerCase() ?? '';
    if (message.contains('timeout')) return 'timeout';
    if (message.contains('429') || message.contains('rate limit')) {
      return 'rate_limited';
    }
    if (message.contains('403') || message.contains('forbidden')) {
      return 'forbidden';
    }
    if (message.contains('404') || message.contains('not found')) {
      return 'not_found';
    }
    return 'request_failed';
  }

  factory JmPageImageBatchItem.fromJson(dynamic raw) {
    if (raw is! Map) {
      throw const FormatException('batch item is not an object');
    }
    final idValue = raw['id'];
    if (!_isPositiveInteger(idValue)) {
      throw const FormatException('batch item has invalid id');
    }
    final pathValue = raw['path'];
    final errorValue = raw['error'];
    if (pathValue != null && pathValue is! String) {
      throw const FormatException('batch item has invalid path');
    }
    if (errorValue != null && errorValue is! String) {
      throw const FormatException('batch item has invalid error');
    }
    final path = pathValue is String && pathValue.trim().isNotEmpty
        ? pathValue.trim()
        : null;
    final error = errorValue is String && errorValue.trim().isNotEmpty
        ? safeErrorCode(errorValue)
        : null;
    if (path == null && error == null) {
      throw const FormatException('batch item has neither path nor error');
    }
    if (path != null && error != null) {
      throw const FormatException('batch item has both path and error');
    }
    int? positiveInt(dynamic value, String field) {
      if (value == null) return null;
      if (!_isPositiveInteger(value)) {
        throw FormatException('batch item has invalid $field');
      }
      return (value as num).toInt();
    }

    return JmPageImageBatchItem(
      id: (idValue as num).toInt(),
      path: path,
      width: positiveInt(raw['width'], 'width'),
      height: positiveInt(raw['height'], 'height'),
      error: error,
    );
  }

  static bool _isPositiveInteger(dynamic value) {
    if (value is! num || !value.isFinite || value <= 0) return false;
    return value == value.toInt();
  }
}
