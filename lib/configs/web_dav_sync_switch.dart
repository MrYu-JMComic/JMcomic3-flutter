import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'bool_property.dart';
import 'is_pro.dart';

const _propertyName = "webDavSyncSwitch";
late bool _webDavSyncSwitch;

Future<void> initWebDavSyncSwitch() async {
  _webDavSyncSwitch = parseBoolPropertyValue(
    await methods.loadProperty(_propertyName),
    fallback: false,
  );
}

bool currentWebDavSyncSwitch() {
  return _webDavSyncSwitch;
}

Future<void> _chooseWebDavSyncSwitch(BuildContext context) async {
  final l10n = context.l10n;
  String? result = await chooseListDialog<String>(context,
      title: l10n.tr("开启时自动同步历史记录到 WebDAV",
          en: "Auto-sync history to WebDAV on launch"),
      values: [l10n.yes, l10n.no]);
  if (result != null) {
    var target = result == l10n.yes;
    await methods.saveProperty(_propertyName, "$target");
    _webDavSyncSwitch = target;
  }
}

Widget webDavSyncSwitchSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text(
          context.l10n.tr("开启时自动同步历史记录到 WebDAV",
              en: "Auto-sync history to WebDAV on launch"),
          style: TextStyle(
            color: !hasProAccess ? Colors.grey : null,
          ),
        ),
        subtitle: Text(
          context.l10n.boolLabel(_webDavSyncSwitch),
          style: TextStyle(
            color: !hasProAccess ? Colors.grey : null,
          ),
        ),
        onTap: () async {
          if (!hasProAccess) {
            return;
          }
          await _chooseWebDavSyncSwitch(context);
          setState(() {});
        },
      );
    },
  );
}
