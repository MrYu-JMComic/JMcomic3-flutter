import 'string_property.dart';

/// 解析本地持久化的枚举配置值。
///
/// 旧版本通常保存 `EnumType.value`，手工迁移或脚本可能只写 `value` 并夹带空白；
/// WebDAV 快照/旧桥接也可能把值再 JSON 编码一到两层。初始化配置时统一兼容这些形式，
/// 避免单个脏配置阻断启动流程。未知文本仍回退默认值，不自动猜测相近拼写。
T parseEnumPropertyValue<T extends Enum>(
  String raw,
  List<T> values,
  T fallback,
) {
  final normalized = parseStringPropertyValue(raw, trim: true);
  if (normalized.isEmpty) {
    return fallback;
  }
  final normalizedLower = normalized.toLowerCase();
  for (final value in values) {
    if (normalizedLower == value.toString().toLowerCase() ||
        normalizedLower == value.name.toLowerCase()) {
      return value;
    }
  }
  return fallback;
}
