import 'string_property.dart';

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
