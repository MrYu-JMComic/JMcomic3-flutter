import 'property_json.dart';

/// 解析本地持久化的字符串配置值。
///
/// WebDAV、代理和导出路径这类配置可能来自旧属性、WebDAV 快照或手工迁移。
/// 历史数据偶发会把字符串再 JSON 编码一到两层；这里只拆明确的 JSON 字符串，
/// 普通文本保持原样。调用方可按字段语义决定是否裁剪空白，例如密码不应裁剪。
String parseStringPropertyValue(
  String raw, {
  String fallback = '',
  bool trim = false,
  int maxJsonStringUnwrapDepth = 2,
}) {
  var value = raw;
  for (var depth = 0; depth < maxJsonStringUnwrapDepth; depth++) {
    final candidate = value.trim();
    if (!looksLikeJsonStringPropertyValue(candidate)) {
      break;
    }
    final decoded = tryDecodeJsonPropertyValue(candidate);
    if (decoded is! String) {
      break;
    }
    value = decoded;
  }

  final normalized = trim ? value.trim() : value;
  return normalized.isEmpty ? fallback : normalized;
}
