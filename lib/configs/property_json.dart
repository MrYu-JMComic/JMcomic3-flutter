import 'dart:convert';

/// 本地配置值的轻量 JSON 识别与解码工具。
///
/// 配置项来自本地属性、WebDAV 快照和手工迁移时，经常只需要拆 JSON 字符串包装。
/// 先做形态判断可避免普通脏文本反复进入 `jsonDecode` 异常路径；真正的字段语义仍由
/// int/bool/string 等调用方决定。
Object? tryDecodeJsonPropertyValue(String raw) {
  final candidate = raw.trim();
  if (!looksLikeJsonPropertyValue(candidate)) {
    return null;
  }
  try {
    return jsonDecode(candidate);
  } on FormatException {
    return null;
  }
}

bool looksLikeJsonPropertyValue(String value) {
  if (value.isEmpty) {
    return false;
  }
  final first = value.codeUnitAt(0);
  return first == 0x22 || // "
      first == 0x5b || // [
      first == 0x7b || // {
      first == 0x2d || // -
      (first >= 0x30 && first <= 0x39); // 0-9
}

bool looksLikeJsonStringPropertyValue(String value) {
  final trimmed = value.trim();
  return trimmed.length >= 2 && trimmed.codeUnitAt(0) == 0x22;
}
