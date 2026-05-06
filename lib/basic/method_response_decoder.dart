import 'dart:convert';

Map<String, dynamic> _normalizeMapEntries(Map<dynamic, dynamic> source) {
  if (source is Map<String, dynamic>) {
    return source;
  }
  final result = <String, dynamic>{};
  source.forEach((key, value) {
    // MethodChannel/JSON 混用场景里 key 可能是 int/null；统一字符串化，
    // 保持与历史 "$key" 映射兼容，避免旧缓存字段被直接丢弃。
    result['$key'] = value;
  });
  return result;
}

List<T> _decodeMappedMapListResponse<T>(
  String rsp,
  String method, {
  required T Function(Map<String, dynamic>) mapper,
  bool immutableItems = true,
}) {
  final list = decodeListResponse(rsp, method);
  final result = <T>[];
  for (var index = 0; index < list.length; index++) {
    final item = list[index];
    if (item is! Map) {
      throw FormatException(
        "Unexpected $method response[$index] shape: ${item.runtimeType}",
      );
    }
    final normalized = _normalizeMapEntries(item);
    if (immutableItems) {
      result.add(mapper(Map<String, dynamic>.unmodifiable(normalized)));
      continue;
    }
    result.add(mapper(normalized));
  }
  return List<T>.unmodifiable(result);
}

/// 下载/历史等接口跨版本可能返回 `null` 表示空列表。
/// 这里只兜底可恢复的空值，结构异常继续抛出，避免协议变更被静默吞掉。
List<dynamic> decodeListResponse(String rsp, String method) {
  final decoded = jsonDecode(rsp);
  if (decoded == null) {
    return const <dynamic>[];
  }
  if (decoded is Iterable) {
    return List<dynamic>.from(decoded);
  }
  throw FormatException(
    "Unexpected $method response shape: ${decoded.runtimeType}",
  );
}

/// 读取对象接口时，按需允许 `null` 退化为空对象。
/// 该函数会把动态 key 统一转成字符串，兼容旧导入数据里的非字符串键。
Map<String, dynamic> decodeMapResponse(
  String rsp,
  String method, {
  bool nullAsEmpty = false,
}) {
  final decoded = jsonDecode(rsp);
  if (decoded == null) {
    if (nullAsEmpty) {
      return <String, dynamic>{};
    }
    throw FormatException("Unexpected $method response shape: null");
  }
  if (decoded is Map) {
    return _normalizeMapEntries(decoded);
  }
  throw FormatException(
    "Unexpected $method response shape: ${decoded.runtimeType}",
  );
}

/// MethodChannel/JSON 解码后常见 Map<dynamic, dynamic>，这里统一转成实体层需要的键类型。
/// `null` 仅表示后端明确返回空对象，例如 `download_by_id` 未命中。
Map<String, dynamic>? decodeNullableMapResponse(String rsp, String method) {
  final decoded = jsonDecode(rsp);
  if (decoded == null) {
    return null;
  }
  if (decoded is Map) {
    return _normalizeMapEntries(decoded);
  }
  throw FormatException(
    "Unexpected $method response shape: ${decoded.runtimeType}",
  );
}

/// 列表接口里每一项都应该是对象；这里额外校验元素类型并给出索引，便于快速定位脏数据来源。
/// 返回的每一项都包装成只读 Map，避免调用方误改桥接响应并污染后续实体解析逻辑。
List<Map<String, dynamic>> decodeMapListResponse(
  String rsp,
  String method, {
  bool immutableItems = true,
}) {
  return _decodeMappedMapListResponse(
    rsp,
    method,
    immutableItems: immutableItems,
    mapper: (item) => item,
  );
}

/// 列表接口常见“解码后立刻转实体”模式，这里一次遍历完成解码+映射，
/// 避免先构建 `List<Map<...>>` 再 map 的二次遍历和临时对象开销。
List<T> decodeEntityListResponse<T>(
  String rsp,
  String method,
  T Function(Map<String, dynamic>) mapper, {
  bool immutableItems = false,
}) {
  return _decodeMappedMapListResponse(
    rsp,
    method,
    mapper: mapper,
    immutableItems: immutableItems,
  );
}

/// 某些后端列表接口历史上混入过 `null`、空白或重复值。
/// 这里统一做最小归一化，避免 UI 层出现空项或重复项；默认保持原顺序。
List<String> decodeStringListResponse(
  String rsp,
  String method, {
  bool dedupe = false,
}) {
  final list = decodeListResponse(rsp, method);
  final result = <String>[];
  final seen = dedupe ? <String>{} : null;
  for (var index = 0; index < list.length; index++) {
    final item = list[index];
    if (item == null) {
      continue;
    }
    final normalized = (item is String ? item : "$item").trim();
    if (normalized.isEmpty) {
      continue;
    }
    if (seen != null && !seen.add(normalized)) {
      continue;
    }
    result.add(normalized);
  }
  return List<String>.unmodifiable(result);
}

/// 对象响应统一转成字符串键值，常用于 `config_links` 这类展示配置。
/// value 为 null 时降级为空串，避免 UI 层展示 `null` 字面量。
Map<String, String> decodeStringMapResponse(String rsp, String method) {
  final map = decodeMapResponse(rsp, method, nullAsEmpty: true);
  final result = <String, String>{};
  map.forEach((key, value) {
    result[key] = value == null ? "" : "$value";
  });
  return result;
}
