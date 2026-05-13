import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/configs/network_host.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _defaultApiHost = "www.cdngwc.club";
const _fallbackApiHosts = <String>[
  "www.cdngwc.club",
  "www.cdnbea.net",
  "www.cdnhth.net",
  "www.cdngwc.cc",
  "www.cdnhth.club",
];
String _apiHost = _defaultApiHost;

List<String> _apiList = [];

Future<void> initApiHost() async {
  _apiList = [];
  _mergeApiList(_fallbackApiHosts);
  try {
    _mergeApiList(await methods.loadApiHostList());
  } catch (e) {
    debugPrient("initApiHost loadApiHostList failed: $e");
    // Keep local fallback list when backend list is unavailable.
  }
  final rawLoaded = await methods.loadApiHost();
  final loaded =
      normalizeApiHostCandidate(rawLoaded, fallback: _defaultApiHost);
  _apiHost = loaded;
  _mergeApiList([_apiHost]);
  if (rawLoaded.trim() != _apiHost) {
    await methods.saveApiHost(_apiHost);
  }
}

String get currentApiHostName => (_apiHost);

/// API 分流地址只接受 host[:port] 形态，设置页和旧缓存可能传入完整 URL。
///
/// 前端先做一次归一化，可避免手动输入 `https://host/path` 后当前会话显示/测速
/// 仍使用完整 URL；后端保存路径会再次清洗，形成双层防护。
String normalizeApiHostCandidate(
  Object? raw, {
  String fallback = "",
}) {
  return normalizeNetworkHostCandidate(raw, fallback: fallback);
}

void _mergeApiList(Iterable<String> items) {
  final merged = <String, String>{};
  for (final raw in _apiList) {
    for (final value in normalizeNetworkHostCandidateList(raw)) {
      merged.putIfAbsent(value.toLowerCase(), () => value);
    }
  }
  for (final raw in items) {
    for (final value in normalizeNetworkHostCandidateList(raw)) {
      // 域名大小写不敏感；保留首次出现的展示文本，后续大小写差异只参与去重。
      merged.putIfAbsent(value.toLowerCase(), () => value);
    }
  }
  _apiList = List<String>.unmodifiable(merged.values);
}

Future<T?> chooseApiDialog<T>(BuildContext buildContext) async {
  return await showDialog<T>(
    context: buildContext,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder:
            (BuildContext context, void Function(void Function()) setState) {
          return SimpleDialog(
            title: Text(context.l10n.tr("API分流", en: "API routing")),
            children: [
              ..._apiList.map(
                (e) => SimpleDialogOption(
                  child: ApiOptionRow(
                    e,
                    key: Key("API:$e"),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop(e);
                  },
                ),
              ),
              SimpleDialogOption(
                child: Text(context.l10n.tr("手动拉取", en: "Refresh list")),
                onPressed: () async {
                  try {
                    final latest = await methods.refreshApiHostList();
                    _mergeApiList(_fallbackApiHosts);
                    _mergeApiList(latest);
                    _mergeApiList([_apiHost]);
                    if (!context.mounted) {
                      return;
                    }
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n
                            .tr("分流列表已更新", en: "Routing list updated")),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  } catch (e) {
                    debugPrient("refreshApiHostList failed: $e");
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text(context.l10n.tr("拉取失败", en: "Refresh failed")),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              SimpleDialogOption(
                child: Text(context.l10n.tr("手动输入", en: "Manual input")),
                onPressed: () async {
                  Navigator.of(context).pop(await _manualInputApiHost(context));
                },
              ),
              SimpleDialogOption(
                child: Text(context.l10n.tr("取消", en: "Cancel")),
                onPressed: () {
                  Navigator.of(context).pop(null);
                },
              ),
            ],
          );
        },
      );
    },
  );
}

final TextEditingController _controller = TextEditingController();

Future<String> _manualInputApiHost(BuildContext context) async {
  _controller.text = _apiHost;
  return await showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(
            context.l10n.tr("手动输入API地址", en: "Enter API address manually")),
        content: TextField(
          controller: _controller,
          decoration: const InputDecoration(
            hintText: "www.example.com",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(context.l10n.tr("取消", en: "Cancel")),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop(_controller.text);
            },
            child: Text(context.l10n.confirm),
          ),
        ],
      );
    },
  );
}

class ApiOptionRow extends StatefulWidget {
  final String value;

  const ApiOptionRow(this.value, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ApiOptionRowState();
}

class _ApiOptionRowState extends State<ApiOptionRow> {
  late Future<int> _feature;

  @override
  void initState() {
    super.initState();
    _feature = methods.ping(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(widget.value),
        Expanded(child: Container()),
        FutureBuilder(
          future: _feature,
          builder: (
            BuildContext context,
            AsyncSnapshot<int> snapshot,
          ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return PingStatus(
                context.l10n.tr("测速中", en: "Testing"),
                Colors.blue,
              );
            }
            if (snapshot.hasError) {
              return PingStatus(
                context.l10n.tr("失败", en: "Failed"),
                Colors.red,
              );
            }
            int ping = snapshot.requireData;
            if (ping <= 200) {
              return PingStatus(
                "${ping}ms",
                Colors.green,
              );
            }
            if (ping <= 500) {
              return PingStatus(
                "${ping}ms",
                Colors.yellow,
              );
            }
            return PingStatus(
              "${ping}ms",
              Colors.orange,
            );
          },
        ),
      ],
    );
  }
}

class PingStatus extends StatelessWidget {
  final String title;
  final Color color;

  const PingStatus(this.title, this.color, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '\u2022',
          style: TextStyle(
            color: color,
          ),
        ),
        Text(" $title"),
      ],
    );
  }
}

Future chooseApiHost(BuildContext context) async {
  final choose = await chooseApiDialog(context);
  if (choose != null) {
    _apiHost = normalizeApiHostCandidate(choose, fallback: _defaultApiHost);
    await methods.saveApiHost(_apiHost);
    _mergeApiList([_apiHost]);
  }
}

Widget apiHostSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        onTap: () async {
          await chooseApiHost(context);
          setState(() {});
        },
        title: Text(context.l10n.tr("API分流", en: "API routing")),
        subtitle: Text(_apiHost.isEmpty ? _defaultApiHost : _apiHost),
      );
    },
  );
}
