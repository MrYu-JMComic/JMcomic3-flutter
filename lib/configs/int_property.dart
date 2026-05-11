import 'property_json.dart';

const _maxJsonStringUnwrapDepth = 2;

/// 解析本地持久化的整数配置。
///
/// 配置值可能来自旧版本属性、WebDAV 同步或手工迁移，历史上出现过 `3.0`
/// 和双层 JSON 字符串（如 `"3"`）。这里只接受“无小数部分”的有限数值，
/// 真正的小数或非法文本仍按调用方给定 fallback 处理，避免静默截断配置。
int parseBoundedIntPropertyValue(
  String raw, {
  required int fallback,
  int? min,
  int? max,
}) {
  var value = _parseIntLikePropertyText(raw) ?? fallback;
  if (min != null && value < min) {
    value = min;
  }
  if (max != null && value > max) {
    value = max;
  }
  return value;
}

int? _parseIntLikePropertyText(String raw) {
  return _parseIntLikePropertyTextInner(raw, 0);
}

int? _parseIntLikePropertyTextInner(String raw, int depth) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final direct = _parseIntLikeValue(trimmed);
  if (direct != null) {
    return direct;
  }
  if (depth >= _maxJsonStringUnwrapDepth) {
    return null;
  }
  final decoded = tryDecodeJsonPropertyValue(trimmed);
  if (decoded is String) {
    // 旧桥接/WebDAV 可能把属性值包装为 "\"3.0\""；只递归拆字符串层。
    return _parseIntLikePropertyTextInner(decoded, depth + 1);
  }
  if (decoded is num) {
    return _finiteIntegralNumToInt(decoded);
  }
  return null;
}

int? _parseIntLikeValue(String value) {
  final parsed = int.tryParse(value);
  if (parsed != null) {
    return parsed;
  }
  final numeric = num.tryParse(value);
  return numeric == null ? null : _finiteIntegralNumToInt(numeric);
}

int? _finiteIntegralNumToInt(num value) {
  if (!value.isFinite || value != value.truncateToDouble()) {
    return null;
  }
  return value.toInt();
}
