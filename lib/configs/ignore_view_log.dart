/// 自动全屏

import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/methods.dart';
import 'bool_property.dart';

const _propertyName = "ignoreVewLog";
late bool _ignoreVewLog;

Future<void> initIgnoreVewLog() async {
  _ignoreVewLog = parseBoolPropertyValue(
    await methods.loadProperty(_propertyName),
    fallback: false,
  );
}

bool currentIgnoreVewLog() {
  return _ignoreVewLog;
}

Widget ignoreVewLogSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return SwitchListTile(
        value: _ignoreVewLog,
        onChanged: (value) async {
          await methods.saveProperty(_propertyName, "$value");
          _ignoreVewLog = value;
          setState(() {});
        },
        title: Text(
          context.l10n.tr(
            "详情页不记录浏览记录",
            en: "Do not record view history on detail page",
          ),
        ),
      );
    },
  );
}
