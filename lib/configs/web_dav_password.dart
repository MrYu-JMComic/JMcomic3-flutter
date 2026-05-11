import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'string_property.dart';

late String _currentWebDavPassword;
const _propertyName = "WebDavPassword";

String get currentWebDavPassword => _currentWebDavPassword;

Future<String?> initWebDavPassword() async {
  _currentWebDavPassword = parseStringPropertyValue(
    await methods.loadProperty(_propertyName),
  );
  return null;
}

String currentWebDavPasswordName(BuildContext context) {
  return _currentWebDavPassword == ""
      ? context.l10n.tr("未设置", en: "Not set")
      : _currentWebDavPassword;
}

Future<dynamic> inputWebDavPassword(BuildContext context) async {
  String? input = await displayTextInputDialog(
    context,
    src: _currentWebDavPassword,
    title: context.l10n.tr('WebDAV密码', en: 'WebDAV password'),
    hint: context.l10n.tr('请输入WebDAV密码', en: 'Enter WebDAV password'),
  );
  if (input != null) {
    final value = parseStringPropertyValue(input);
    await methods.saveProperty(_propertyName, value);
    _currentWebDavPassword = value;
  }
}

Widget webDavPasswordSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text(context.l10n.tr("WebDAV密码", en: "WebDAV password")),
        subtitle: Text(currentWebDavPasswordName(context)),
        onTap: () async {
          await inputWebDavPassword(context);
          setState(() {});
        },
      );
    },
  );
}
