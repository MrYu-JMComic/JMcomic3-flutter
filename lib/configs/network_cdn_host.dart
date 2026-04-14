import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _defaultCdnHost = "cdn-msp3.jmapiproxy1.cc";
String _cdnHost = _defaultCdnHost;

String _truncateLabel(String value, {int max = 21}) {
  if (value.length <= max) return value;
  return value.substring(0, max) + "...";
}

String get currentCdnHostName => _cdnHost;

const _base64List = [
  "Y2RuLW1zcDMuam1kYW5qb25wcm94eS52aXA=",
  "Y2RuLW1zcDMuam1hcGlub2RldWR6bi5uZXQ=",
  "Y2RuLW1zcC5qbWFwaXByb3h5My5uZXQ=",
  "Y2RuLW1zcDIuam1hcGlub2RldWR6bi5uZXQ=",
  "Y2RuLW1zcDIuam1hcGlwcm94eTEuY2M=",
  "Y2RuLW1zcDIuam1hcGlwcm94eTIuY2M=",
  "Y2RuLW1zcC5qbWFwaW5vZGV1ZHpuLm5ldA==",
  "Y2RuLW1zcC5qbWFwaXByb3h5MS5jYw==",
  "Y2RuLW1zcC5qbWFwaXByb3h5Mi5jYw==",
];

List<String> _cdnList = [];

Future<void> initCdnHost() async {
  _cdnList = [];
  final merged = <String>{_defaultCdnHost};
  for (var i = 0; i < _base64List.length; i++) {
    final host = utf8.decode(base64.decode(_base64List[i])).trim();
    if (host.isNotEmpty) {
      merged.add(host);
    }
  }
  _cdnList = merged.toList();
  final loaded = (await methods.loadCdnHost()).trim();
  _cdnHost = loaded.isNotEmpty ? loaded : _defaultCdnHost;
  if (!_cdnList.contains(_cdnHost)) {
    _cdnList.insert(0, _cdnHost);
  }
  if (loaded != _cdnHost) {
    await methods.saveCdnHost(_cdnHost);
  }
}

Future chooseCdnHost(BuildContext context) async {
  final choose = await chooseCdnDialog(context);
  if (choose != null) {
    final value = "$choose".trim();
    _cdnHost = value.isNotEmpty ? value : _defaultCdnHost;
    await methods.saveCdnHost(_cdnHost);
    if (!_cdnList.contains(_cdnHost)) {
      _cdnList.insert(0, _cdnHost);
    }
  }
}

Widget cdnHostSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        onTap: () async {
          await chooseCdnHost(context);
          setState(() {});
        },
        title: Text(context.l10n.tr("图片分流", en: "Image routing")),
        subtitle: Text(_cdnHost.isEmpty ? _defaultCdnHost : _cdnHost),
      );
    },
  );
}

Future<T?> chooseCdnDialog<T>(BuildContext buildContext) async {
  return await showDialog<T>(
    context: buildContext,
    builder: (BuildContext context) {
      final dialogWidth = MediaQuery.of(context).size.width * 0.86;
      return SimpleDialog(
        title: Text(context.l10n.tr("图片分流", en: "Image routing")),
        children: [
          ..._cdnList.map(
            (e) => SimpleDialogOption(
              child: SizedBox(
                width: dialogWidth,
                child: CdnOptionRow(
                  e,
                  key: Key("CDN:$e"),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop(e);
              },
            ),
          ),
          SimpleDialogOption(
            child: SizedBox(
              width: dialogWidth,
              child: Text(context.l10n.tr("手动输入", en: "Manual input")),
            ),
            onPressed: () async {
              Navigator.of(context).pop(await _manualInputApiHost(context));
            },
          ),
          SimpleDialogOption(
            child: SizedBox(
              width: dialogWidth,
              child: Text(context.l10n.tr("取消", en: "Cancel")),
            ),
            onPressed: () {
              Navigator.of(context).pop(null);
            },
          ),
        ],
      );
    },
  );
}

final TextEditingController _controller = TextEditingController();

Future<String> _manualInputApiHost(BuildContext context) async {
  _controller.text = _cdnHost;
  return await showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(
            context.l10n.tr("手动输入CDN地址", en: "Enter CDN address manually")),
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

class CdnOptionRow extends StatefulWidget {
  final String value;

  const CdnOptionRow(this.value, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CdnOptionRowState();
}

class _CdnOptionRowState extends State<CdnOptionRow> {
  late Future<int> _feature;

  @override
  void initState() {
    super.initState();
    _feature = methods.pingCdn(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _truncateLabel(widget.value),
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
            ),
          ),
          const SizedBox(width: 8),
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
      ),
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
