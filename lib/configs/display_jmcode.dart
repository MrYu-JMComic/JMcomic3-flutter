/// 自动全屏

import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'bool_property.dart';

const _propertyName = "displayJmcode";
late bool _displayJmcode;

Future<void> initDisplayJmcode() async {
  _displayJmcode = parseBoolPropertyValue(
    await methods.loadProperty(_propertyName),
    fallback: true,
  );
}

bool currentDisplayJmcode() {
  return _displayJmcode;
}

Future<void> _chooseDisplayJmcode(BuildContext context) async {
  final l10n = context.l10n;
  String? result = await chooseListDialog<String>(context,
      title: l10n.tr("显示漫画代码", en: "Show comic code"),
      values: [l10n.yes, l10n.no]);
  if (result != null) {
    var target = result == l10n.yes;
    await methods.saveProperty(_propertyName, "$target");
    _displayJmcode = target;
  }
}

Widget displayJmcodeSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text(context.l10n.tr("显示漫画代码", en: "Show comic code")),
        subtitle: Text(context.l10n.boolLabel(_displayJmcode)),
        onTap: () async {
          await _chooseDisplayJmcode(context);
          setState(() {});
        },
      );
    },
  );
}
