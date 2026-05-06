/// 代理设置

import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';

late String _currentProxy;

Future<String?> initProxy() async {
  _currentProxy = await methods.getProxy();
  return null;
}

String currentProxyName(BuildContext context) {
  return _currentProxy == ""
      ? context.l10n.tr("未设置", en: "Not set")
      : _currentProxy;
}

Future<dynamic> inputProxy(BuildContext context) async {
  String? input = await displayTextInputDialog(
    context,
    src: _currentProxy,
    title: context.l10n.tr('代理服务器', en: 'Proxy server'),
    hint: context.l10n.tr('请输入代理服务器', en: 'Enter proxy server'),
    desc: context.l10n.tr(
      " ( 例如 socks5://127.0.0.1:1080/ ) ",
      en: " ( e.g. socks5://127.0.0.1:1080/ ) ",
    ),
  );
  if (input != null) {
    await methods.setProxy(input);
    _currentProxy = input;
  }
}

Widget proxySetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text(context.l10n.tr("代理服务器", en: "Proxy server")),
        subtitle: Text(currentProxyName(context)),
        onTap: () async {
          await inputProxy(context);
          setState(() {});
        },
      );
    },
  );
}
