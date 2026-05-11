import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/enum_property.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

enum TwoPageDirection {
  leftToRight,
  rightToLeft,
}

const _propertyName = "twoPageDirection";
late TwoPageDirection _twoPageDirection;

Future initTwoPageDirection() async {
  _twoPageDirection = _fromString(await methods.loadProperty(_propertyName));
}

TwoPageDirection _fromString(String valueForm) {
  return parseEnumPropertyValue(
    valueForm,
    TwoPageDirection.values,
    TwoPageDirection.leftToRight,
  );
}

TwoPageDirection get currentTwoPageDirection => _twoPageDirection;

String twoPageDirectionName(TwoPageDirection direction, BuildContext context) {
  switch (direction) {
    case TwoPageDirection.leftToRight:
      return context.l10n.tr("从左到右", en: "Left to right");
    case TwoPageDirection.rightToLeft:
      return context.l10n.tr("从右到左", en: "Right to left");
  }
}

Future chooseTwoPageDirection(BuildContext context) async {
  final Map<String, TwoPageDirection> map = {};
  for (var element in TwoPageDirection.values) {
    map[twoPageDirectionName(element, context)] = element;
  }
  final newTwoPageDirection = await chooseMapDialog(
    context,
    title: context.l10n.tr("请选择阅读器方向", en: "Choose reader direction"),
    values: map,
  );
  if (newTwoPageDirection != null) {
    await methods.saveProperty(_propertyName, "$newTwoPageDirection");
    _twoPageDirection = newTwoPageDirection;
  }
}

Widget twoGalleryDirectionSetting(BuildContext context) {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        onTap: () async {
          await chooseTwoPageDirection(context);
          setState(() {});
        },
        title: Text(
          context.l10n.tr("双页阅读器方向", en: "Two-page reader direction"),
        ),
        subtitle: Text(twoPageDirectionName(_twoPageDirection, context)),
      );
    },
  );
}
