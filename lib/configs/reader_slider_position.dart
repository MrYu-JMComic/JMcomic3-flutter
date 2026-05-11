import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/enum_property.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

enum ReaderSliderPosition {
  bottom,
  right,
  left,
}

const _propertyName = "reader_slider_position";
late ReaderSliderPosition _readerSliderPosition;

Future initReaderSliderPosition() async {
  _readerSliderPosition = _readerSliderPositionFromString(
    await methods.loadProperty(_propertyName),
  );
}

ReaderSliderPosition _readerSliderPositionFromString(String str) {
  return parseEnumPropertyValue(
    str,
    ReaderSliderPosition.values,
    ReaderSliderPosition.bottom,
  );
}

ReaderSliderPosition get currentReaderSliderPosition => _readerSliderPosition;

String _positionName(ReaderSliderPosition position, BuildContext context) {
  switch (position) {
    case ReaderSliderPosition.bottom:
      return context.l10n.tr('下方', en: 'Bottom');
    case ReaderSliderPosition.right:
      return context.l10n.tr('右侧', en: 'Right');
    case ReaderSliderPosition.left:
      return context.l10n.tr('左侧', en: 'Left');
  }
}

String currentReaderSliderPositionName(BuildContext context) =>
    _positionName(_readerSliderPosition, context);

Future<void> chooseReaderSliderPosition(BuildContext context) async {
  Map<String, ReaderSliderPosition> map = {};
  for (var value in ReaderSliderPosition.values) {
    map[_positionName(value, context)] = value;
  }
  ReaderSliderPosition? result = await chooseMapDialog<ReaderSliderPosition>(
    context,
    title: context.l10n.tr("选择滑动条位置", en: "Choose slider position"),
    values: map,
  );
  if (result != null) {
    await methods.saveProperty(_propertyName, result.toString());
    _readerSliderPosition = result;
  }
}
