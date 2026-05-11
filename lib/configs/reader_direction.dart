import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/enum_property.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

enum ReaderDirection {
  topToBottom,
  leftToRight,
  rightToLeft,
}

const _propertyName = "readerDirection";
late ReaderDirection _readerDirection;

Future initReaderDirection() async {
  _readerDirection = _fromString(await methods.loadProperty(_propertyName));
}

ReaderDirection _fromString(String valueForm) {
  return parseEnumPropertyValue(
    valueForm,
    ReaderDirection.values,
    ReaderDirection.topToBottom,
  );
}

ReaderDirection get currentReaderDirection => _readerDirection;

String readerDirectionName(ReaderDirection direction, BuildContext context) {
  switch (direction) {
    case ReaderDirection.topToBottom:
      return context.l10n.tr("从上到下", en: "Top to bottom");
    case ReaderDirection.leftToRight:
      return context.l10n.tr("从左到右", en: "Left to right");
    case ReaderDirection.rightToLeft:
      return context.l10n.tr("从右到左", en: "Right to left");
  }
}

Future chooseReaderDirection(BuildContext context) async {
  final Map<String, ReaderDirection> map = {};
  for (var element in ReaderDirection.values) {
    map[readerDirectionName(element, context)] = element;
  }
  final newReaderDirection = await chooseMapDialog(
    context,
    title: context.l10n.tr("请选择阅读器方向", en: "Choose reader direction"),
    values: map,
  );
  if (newReaderDirection != null) {
    await methods.saveProperty(_propertyName, "$newReaderDirection");
    _readerDirection = newReaderDirection;
  }
}
