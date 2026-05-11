/// 自动全屏

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/methods.dart';
import 'bool_property.dart';

const _propertyName = "usingRightClickPop";
bool _usingRightClickPop = false;

Future<void> initUsingRightClickPop() async {
  _usingRightClickPop = parseBoolPropertyValue(
    await methods.loadProperty(_propertyName),
    fallback: false,
  );
}

bool currentUsingRightClickPop() {
  return _usingRightClickPop;
}

Widget usingRightClickPopSetting() {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    return Container();
  }
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return SwitchListTile(
        value: _usingRightClickPop,
        onChanged: (value) async {
          await methods.saveProperty(_propertyName, "$value");
          _usingRightClickPop = value;
          setState(() {});
        },
        title: Text(
          context.l10n.tr(
            "鼠标右键返回上一页",
            en: "Right-click to go back",
          ),
        ),
      );
    },
  );
}
