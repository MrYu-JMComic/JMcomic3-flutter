import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';

late String _currentWebDavUrl;
const _propertyName = "WebDavUrl";

Future<String?> initWebDavUrl() async {
  _currentWebDavUrl = await methods.loadProperty(_propertyName);
  if (_currentWebDavUrl == "") {
    _currentWebDavUrl = "http://server/.jmtt2mic.history";
  }
  return null;
}

String currentWebDavUrlName(BuildContext context) {
  return _currentWebDavUrl == ""
      ? context.l10n.tr("未设置", en: "Not set")
      : _currentWebDavUrl;
}

String get currentWebDavUrl => _currentWebDavUrl;

Future<dynamic> inputWebDavUrl(BuildContext context) async {
  String? input = await displayTextInputDialog(
    context,
    src: _currentWebDavUrl,
    title: context.l10n.tr('WebDAV文件URL', en: 'WebDAV file URL'),
    hint: context.l10n.tr('请输入WebDAV文件URL', en: 'Enter WebDAV file URL'),
    desc: context.l10n.tr(
      " ( 例如 http://server/folder/.jmtt2mic.history ) ",
      en: " ( e.g. http://server/folder/.jmtt2mic.history ) ",
    ),
  );
  if (input != null) {
    await methods.saveProperty(_propertyName, input);
    _currentWebDavUrl = input;
  }
}

Widget webDavUrlSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text(context.l10n.tr("WebDAV文件URL", en: "WebDAV file URL")),
        subtitle: Text(currentWebDavUrlName(context)),
        onTap: () async {
          await inputWebDavUrl(context);
          setState(() {});
        },
      );
    },
  );
}
