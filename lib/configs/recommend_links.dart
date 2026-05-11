import 'dart:collection';

import 'package:event/event.dart';

import '../basic/methods.dart';

final recommendLinksEvent = Event();
Map<String, String> _recommendLinks = const <String, String>{};
const _followChannelLink = "https://qm.qq.com/q/h3p372R200";

Map<String, String> currentRecommendLinks() => _recommendLinks;

Future<void> initRecommendLinks() async {
  try {
    _recommendLinks =
        normalizeRecommendLinksForDisplay(await methods.configLinks());
  } catch (_) {
    _recommendLinks = const <String, String>{};
  }
  recommendLinksEvent.broadcast();
}

Map<String, String> normalizeRecommendLinksForDisplay(
  Map<String, String> src,
) {
  final result = <String, String>{};
  src.forEach((key, value) {
    final label = key.trim();
    final url = value.trim();
    if (label.isEmpty || url.isEmpty) {
      return;
    }
    // 后端 config_links 来自持久化/远端配置，展示前统一收敛空白和旧频道入口，
    // 并返回只读 Map，避免推荐面板或测试代码误改全局配置状态。
    result[label] =
        label.contains("关注频道") || label == "频道" ? _followChannelLink : url;
  });
  return UnmodifiableMapView<String, String>(result);
}
