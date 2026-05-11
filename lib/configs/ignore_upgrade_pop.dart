import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/methods.dart';
import 'bool_property.dart';
import 'is_pro.dart';

const _propertyName = "ignoreUpgradePop";
late bool _ignoreUpgradePop;

Future<void> initIgnoreUpgradePop() async {
  _ignoreUpgradePop = parseBoolPropertyValue(
    await methods.loadProperty(_propertyName),
    fallback: false,
  );
  if (!hasProAccess) {
    _ignoreUpgradePop = false;
  }
}

bool currentIgnoreUpgradePop() {
  return _ignoreUpgradePop;
}

Widget ignoreUpgradePopSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return SwitchListTile(
        title: Text(
          context.l10n.tr("是否忽略升级弹窗", en: "Ignore upgrade prompts"),
          style: TextStyle(
            color: !hasProAccess ? Colors.grey : null,
          ),
        ),
        subtitle: Text(
          context.l10n.boolLabel(_ignoreUpgradePop),
          style: TextStyle(
            color: !hasProAccess ? Colors.grey : null,
          ),
        ),
        value: _ignoreUpgradePop,
        onChanged: (value) async {
          if (!hasProAccess) {
            return;
          }
          await methods.saveProperty(_propertyName, "$value");
          _ignoreUpgradePop = value;
          setState(() {});
        },
      );
    },
  );
}
