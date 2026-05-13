import 'string_property.dart';

final RegExp _networkHostCandidateStart = RegExp(
  r'^(?:(?:https?:)?//|\[[0-9A-Fa-f:.]+\](?::\d+)?|localhost(?::\d+)?(?:[/?#]|$)|(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?(?:[/?#]|$)|[A-Za-z0-9.-]+\.[A-Za-z])',
  caseSensitive: false,
);
final RegExp _networkHostHardSeparator = RegExp(r'[\r\n;]+');

/// 将 API/CDN 分流输入归一化为后端实际需要的 `host[:port]`。
///
/// 设置页、旧缓存和手工脚本可能保存完整 URL、协议相对 URL 或带 userinfo 的
/// 地址。这里只保留 authority 中真正用于连接的主机与端口，path/query/fragment
/// 由后端具体接口重新拼接，避免测速、保存和展示使用三套不同语义。
String normalizeNetworkHostCandidate(
  Object? raw, {
  String fallback = "",
}) {
  // WebDAV/旧桥接可能把 host 配置再 JSON 编码一到两层；先拆字符串壳，
  // 再进入 URL authority 清洗，避免设置页展示带引号的脏 host。
  var value = parseStringPropertyValue("${raw ?? ""}", trim: true);
  if (value.isEmpty) {
    return fallback;
  }
  final schemeIndex = value.indexOf("://");
  if (schemeIndex >= 0) {
    value = value.substring(schemeIndex + 3);
  } else if (value.startsWith("//")) {
    value = value.substring(2);
  }
  final delimiterIndex = value.indexOf(RegExp(r"[/?#]"));
  if (delimiterIndex >= 0) {
    value = value.substring(0, delimiterIndex);
  }
  final userInfoIndex = value.lastIndexOf("@");
  if (userInfoIndex >= 0) {
    value = value.substring(userInfoIndex + 1);
  }
  value = value.trim();
  return value.isEmpty ? fallback : value;
}

/// 将源站/缓存里的“候选 host 文本”收敛为可展示和测速的 host 列表。
///
/// 手工迁移或远端配置偶尔会把多条 API/CDN 分流地址拼在一个字符串里；这里只按
/// 换行、分号和“后面明显还是 URL/域名/IP/localhost”的逗号拆分；逗号若落在
/// query/fragment 内部则保守保留，避免把参数值误当成新的测速 host。返回值保留
/// 首次出现的大小写展示文本，并按 host 小写去重。
List<String> normalizeNetworkHostCandidateList(Object? raw) {
  final value = parseStringPropertyValue("${raw ?? ""}", trim: true);
  if (value.isEmpty) {
    return const <String>[];
  }
  final result = <String>[];
  final seen = <String>{};
  for (final part in _networkHostCandidateParts(value)) {
    final normalized = normalizeNetworkHostCandidate(part);
    if (normalized.isEmpty) {
      continue;
    }
    if (seen.add(normalized.toLowerCase())) {
      result.add(normalized);
    }
  }
  return List<String>.unmodifiable(result);
}

Iterable<String> _networkHostCandidateParts(String value) sync* {
  for (final chunk in value.split(_networkHostHardSeparator)) {
    var start = 0;
    for (var index = 0; index < chunk.length; index++) {
      if (chunk.codeUnitAt(index) != 0x2c) {
        continue;
      }
      final current = chunk.substring(start, index);
      final rest = chunk.substring(index + 1);
      if (!_shouldSplitNetworkHostComma(current, rest)) {
        continue;
      }
      yield current;
      start = index + 1;
    }
    yield chunk.substring(start);
  }
}

bool _shouldSplitNetworkHostComma(String current, String rest) {
  final next = rest.trimLeft();
  if (current.trim().isEmpty ||
      next.isEmpty ||
      !_networkHostCandidateStart.hasMatch(next)) {
    return false;
  }
  if (!current.contains('?') && !current.contains('#')) {
    return true;
  }
  // query/fragment 里的逗号常见于远端跳转或镜像参数；只有用户明显输入
  // `...?x=1, https://next.example.com` 这种带空白的完整 URL 列表时才拆。
  final lowerNext = next.toLowerCase();
  return _startsWithWhitespace(rest) &&
      (lowerNext.startsWith('http://') ||
          lowerNext.startsWith('https://') ||
          lowerNext.startsWith('//'));
}

bool _startsWithWhitespace(String value) {
  return value.isNotEmpty && value.codeUnitAt(0) <= 0x20;
}
