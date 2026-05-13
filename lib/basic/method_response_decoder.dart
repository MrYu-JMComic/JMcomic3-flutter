import 'dart:collection';
import 'dart:convert';

const int _maxBridgePayloadStringUnwrapDepth = 2;
const int _maxListPayloadMapUnwrapDepth = 3;
const List<String> _listPayloadKeys = <String>[
  'data',
  'items',
  'list',
  'results',
  'hosts',
  'server',
  'Server',
];

final Object _missingListPayload = Object();

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

bool _looksLikeJsonValue(String input) {
  if (input.isEmpty) {
    return false;
  }
  switch (input.codeUnitAt(0)) {
    case 0x7B: // {
    case 0x5B: // [
    case 0x22: // "
    case 0x2D: // -
    case >= 0x30 && <= 0x39: // 0-9
    case 0x74: // t
    case 0x66: // f
    case 0x6E: // n
      return true;
  }
  return false;
}

dynamic _decodeBridgePayload(String rsp) {
  dynamic decoded = jsonDecode(rsp);
  for (var depth = 0;
      decoded is String && depth < _maxBridgePayloadStringUnwrapDepth;
      depth++) {
    final nested = decoded.trim();
    if (!_looksLikeJsonValue(nested)) {
      return decoded;
    }
    try {
      // Rust/MethodChannel 历史上出现过 response_data 被重复 JSON 编码的载荷。
      // 只在内容本身像 JSON 值时按深度上限拆包，普通字符串仍按协议结构校验并报错。
      decoded = jsonDecode(nested);
    } on FormatException {
      return decoded;
    }
  }
  return decoded;
}

dynamic _decodeNestedPayloadString(String payload) {
  final nested = payload.trim();
  if (_looksLikeJsonValue(nested)) {
    try {
      return _decodeBridgePayload(nested);
    } on FormatException {
      // 像 JSON 但损坏的字符串仍交给外层按原始标量处理，方便调用方决定是否允许单值。
    }
  }
  return payload;
}

dynamic _extractListPayloadFromMap(
  Map<dynamic, dynamic> source, {
  int depth = 0,
}) {
  for (final key in _listPayloadKeys) {
    if (!source.containsKey(key)) {
      continue;
    }
    var payload = source[key];
    if (payload is String) {
      payload = _decodeNestedPayloadString(payload);
    }
    if (payload is Map && depth < _maxListPayloadMapUnwrapDepth) {
      final nested = _extractListPayloadFromMap(payload, depth: depth + 1);
      if (!identical(nested, _missingListPayload)) {
        return nested;
      }
    }
    return payload;
  }
  return _missingListPayload;
}

dynamic _unwrapListPayload(dynamic decoded) {
  if (decoded is Map) {
    // 后端、MethodChannel 或手工迁移脚本可能给列表加 data/items/hosts 等对象壳。
    // 递归只拆约定字段且有层数上限，未知对象仍会在调用点按结构异常暴露。
    final payload = _extractListPayloadFromMap(decoded);
    if (!identical(payload, _missingListPayload)) {
      return payload;
    }
  }
  return decoded;
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
  // 只读视图可维持“不允许外部增删改列表结构”的语义，同时避免再拷贝一份结果列表。
  return UnmodifiableListView<T>(result);
}

/// 下载/历史等接口跨版本可能返回 `null` 表示空列表。
/// 这里只兜底可恢复的空值，结构异常继续抛出，避免协议变更被静默吞掉。
List<dynamic> decodeListResponse(String rsp, String method) {
  var decoded = _unwrapListPayload(_decodeBridgePayload(rsp));
  if (decoded == null) {
    return const <dynamic>[];
  }
  if (decoded is List<dynamic>) {
    // jsonDecode 常见直接产出 List；复用原列表可避免下载列表等热路径的整表拷贝。
    return decoded;
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
  final decoded = _decodeBridgePayload(rsp);
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

/// 单对象接口常见“对象响应 + 直接转实体”模式。
/// 这里集中做结构校验，避免调用方遗漏 `null`/非对象边界判断。
T decodeEntityResponse<T>(
  String rsp,
  String method,
  T Function(Map<String, dynamic>) mapper, {
  bool immutableItem = false,
  bool nullAsEmpty = false,
}) {
  final map = decodeMapResponse(
    rsp,
    method,
    nullAsEmpty: nullAsEmpty,
  );
  if (immutableItem) {
    return mapper(Map<String, dynamic>.unmodifiable(map));
  }
  return mapper(map);
}

/// MethodChannel/JSON 解码后常见 Map<dynamic, dynamic>，这里统一转成实体层需要的键类型。
/// `null` 仅表示后端明确返回空对象，例如 `download_by_id` 未命中。
Map<String, dynamic>? decodeNullableMapResponse(String rsp, String method) {
  final decoded = _decodeBridgePayload(rsp);
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

/// 单对象接口常见“可空对象 + 直接转实体”模式。
/// 这里统一处理 null 与结构校验，避免调用方重复判空和 Map 中间变量。
T? decodeNullableEntityResponse<T>(
  String rsp,
  String method,
  T Function(Map<String, dynamic>) mapper, {
  bool immutableItem = false,
}) {
  final map = decodeNullableMapResponse(rsp, method);
  if (map == null) {
    return null;
  }
  if (immutableItem) {
    return mapper(Map<String, dynamic>.unmodifiable(map));
  }
  return mapper(map);
}

/// 某些后端列表接口历史上混入过 `null`、空白或重复值。
/// 这里统一做最小归一化，避免 UI 层出现空项或重复项；默认保持原顺序。
List<String> decodeStringListResponse(
  String rsp,
  String method, {
  bool dedupe = false,
}) {
  final decoded = _unwrapListPayload(_decodeBridgePayload(rsp));
  final Iterable<dynamic> list;
  if (decoded == null) {
    list = const <dynamic>[];
  } else if (decoded is List<dynamic>) {
    list = decoded;
  } else if (decoded is Iterable && decoded is! String) {
    list = decoded;
  } else if (decoded is Map) {
    throw FormatException(
      "Unexpected $method response shape: ${decoded.runtimeType}",
    );
  } else {
    // 字符串列表接口兼容对象壳中的单值（例如 {"hosts":"api.example.com"}），
    // 但普通列表解码仍保持严格，避免实体列表把标量误当合法结构。
    list = <dynamic>[decoded];
  }
  final result = <String>[];
  final seen = dedupe ? <String>{} : null;
  for (final item in list) {
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
  return UnmodifiableListView<String>(result);
}

/// 对象响应统一转成字符串键值，常用于 `config_links` 这类展示配置。
/// value 为 null 时降级为空串，避免 UI 层展示 `null` 字面量。
Map<String, String> decodeStringMapResponse(String rsp, String method) {
  final map = decodeMapResponse(rsp, method, nullAsEmpty: true);
  final result = <String, String>{};
  map.forEach((key, value) {
    result[key] = value == null ? "" : "$value";
  });
  // 配置映射在 UI 层只读消费；只读视图比二次拷贝更省内存，且仍能阻止误写。
  return UnmodifiableMapView<String, String>(result);
}
