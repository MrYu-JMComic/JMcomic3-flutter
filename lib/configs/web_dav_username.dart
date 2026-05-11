import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'string_property.dart';

late String _currentWebDavUserName;
const _propertyName = "WebDavUserName";

String get currentWebUserName => _currentWebDavUserName;

Future<String?> initWebDavUserName() async {
  _currentWebDavUserName = parseStringPropertyValue(
    await methods.loadProperty(_propertyName),
    trim: true,
  );
  return null;
}

String currentWebDavUserNameName(BuildContext context) {
  return _currentWebDavUserName == ""
      ? context.l10n.tr("未设置", en: "Not set")
      : _currentWebDavUserName;
}

Future<dynamic> inputWebDavUserName(BuildContext context) async {
  String? input = await displayTextInputDialog(
    context,
    src: _currentWebDavUserName,
    title: context.l10n.tr('WebDAV用户名', en: 'WebDAV username'),
    hint: context.l10n.tr('请输入WebDAV用户名', en: 'Enter WebDAV username'),
  );
  if (input != null) {
    final value = parseStringPropertyValue(input, trim: true);
    await methods.saveProperty(_propertyName, value);
    _currentWebDavUserName = value;
  }
}

Widget webDavUserNameSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text(context.l10n.tr("WebDAV用户名", en: "WebDAV username")),
        subtitle: Text(currentWebDavUserNameName(context)),
        onTap: () async {
          await inputWebDavUserName(context);
          setState(() {});
        },
      );
    },
  );
}
