import 'property_json.dart';

const _maxJsonStringUnwrapDepth = 2;

/// 解析本地持久化的布尔配置值。
///
/// 配置值可能来自旧版本属性、WebDAV 同步或手工迁移，历史上可能出现
/// `TRUE`、`"false"`、`1`/`0` 这类松散形态。这里只接受明确的布尔语义，
/// 非法文本按调用方 fallback 处理，避免把损坏配置误判为开启。
bool parseBoolPropertyValue(
  String raw, {
  required bool fallback,
}) {
  return _parseBoolLikePropertyText(raw) ?? fallback;
}

bool? _parseBoolLikePropertyText(String raw) {
  return _parseBoolLikePropertyTextInner(raw, 0);
}

bool? _parseBoolLikePropertyTextInner(String raw, int depth) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final direct = _parseBoolToken(trimmed);
  if (direct != null) {
    return direct;
  }
  if (depth >= _maxJsonStringUnwrapDepth) {
    return null;
  }
  final decoded = tryDecodeJsonPropertyValue(trimmed);
  if (decoded is bool) {
    return decoded;
  }
  if (decoded is String) {
    // 配置同步中只允许拆有限层字符串包装，避免异常缓存造成无界递归。
    return _parseBoolLikePropertyTextInner(decoded, depth + 1);
  }
  if (decoded is num) {
    return _finiteBinaryNumberToBool(decoded);
  }
  return null;
}

bool? _parseBoolToken(String value) {
  switch (value.toLowerCase()) {
    case 'true':
    case 'yes':
    case 'on':
    case '1':
      return true;
    case 'false':
    case 'no':
    case 'off':
    case '0':
      return false;
  }
  final numeric = num.tryParse(value);
  return numeric == null ? null : _finiteBinaryNumberToBool(numeric);
}

bool? _finiteBinaryNumberToBool(num value) {
  if (!value.isFinite || value != value.truncateToDouble()) {
    return null;
  }
  if (value == 1) {
    return true;
  }
  if (value == 0) {
    return false;
  }
  return null;
}
