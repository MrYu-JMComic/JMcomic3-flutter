/// 自动全屏

import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'bool_property.dart';

const _propertyName = "noAnimation";
late bool _noAnimation;

Future<void> initNoAnimation() async {
  _noAnimation = parseBoolPropertyValue(
    await methods.loadProperty(_propertyName),
    fallback: false,
  );
}

bool currentNoAnimation() {
  return _noAnimation;
}

Future<void> _chooseNoAnimation(BuildContext context) async {
  final l10n = context.l10n;
  String? result = await chooseListDialog<String>(context,
      title: l10n.tr(
        "取消键盘或音量翻页动画",
        en: "Disable keyboard/volume page-turn animation",
      ),
      values: [l10n.yes, l10n.no]);
  if (result != null) {
    var target = result == l10n.yes;
    await methods.saveProperty(_propertyName, "$target");
    _noAnimation = target;
  }
}

Widget noAnimationSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text(
          context.l10n.tr(
            "取消键盘或音量翻页动画",
            en: "Disable keyboard/volume page-turn animation",
          ),
        ),
        subtitle: Text(context.l10n.boolLabel(_noAnimation)),
        onTap: () async {
          await _chooseNoAnimation(context);
          setState(() {});
        },
      );
    },
  );
}
