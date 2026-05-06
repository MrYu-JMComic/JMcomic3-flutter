/// 全屏操作

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

enum ReaderControllerType {
  touchOnce,
  controller,
  touchDouble,
  touchDoubleOnceNext,
  threeArea,
}

Map<String, ReaderControllerType> _readerControllerTypeMap(
  BuildContext context,
) {
  return {
    context.l10n.tr("点击屏幕一次全屏", en: "Single tap to toggle fullscreen"):
        ReaderControllerType.touchOnce,
    context.l10n.tr("使用控制器全屏", en: "Use controller for fullscreen"):
        ReaderControllerType.controller,
    context.l10n.tr("双击屏幕全屏", en: "Double tap to toggle fullscreen"):
        ReaderControllerType.touchDouble,
    context.l10n.tr(
      "双击屏幕全屏 + 单击屏幕下一页",
      en: "Double tap for fullscreen + single tap for next page",
    ): ReaderControllerType.touchDoubleOnceNext,
    context.l10n.tr(
      "将屏幕划分成三个区域 (上一页, 下一页, 全屏)",
      en: "Three areas (prev, next, fullscreen)",
    ): ReaderControllerType.threeArea,
  };
}

const _defaultController = ReaderControllerType.touchOnce;
const _propertyName = "reader_controller_type";
late ReaderControllerType _readerControllerType;

Future<void> initReaderControllerType() async {
  _readerControllerType =
      _readerControllerTypeFromString(await methods.loadProperty(
    _propertyName,
  ));
}

ReaderControllerType get currentReaderControllerType => _readerControllerType;

ReaderControllerType _readerControllerTypeFromString(String string) {
  for (var value in ReaderControllerType.values) {
    if (string == value.toString()) {
      return value;
    }
  }
  return _defaultController;
}

String currentReaderControllerTypeName(BuildContext context) {
  for (var e in _readerControllerTypeMap(context).entries) {
    if (e.value == _readerControllerType) {
      return e.key;
    }
  }
  return '';
}

Future<void> chooseReaderControllerType(BuildContext context) async {
  final map = _readerControllerTypeMap(context);
  ReaderControllerType? result = await chooseMapDialog<ReaderControllerType>(
    context,
    title: context.l10n.tr("选择操控方式", en: "Choose control mode"),
    values: map,
  );
  if (result != null) {
    await methods.saveProperty(_propertyName, result.toString());
    _readerControllerType = result;
  }
}
