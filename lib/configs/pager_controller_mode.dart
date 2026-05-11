import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/enum_property.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _propertyKey = "pager_controller_mode";
late PagerControllerMode _value;
final currentPagerControllerModeEvent = Event();

PagerControllerMode get currentPagerControllerMode => _value;

enum PagerControllerMode {
  stream,
  pager,
}

Map<PagerControllerMode, String> _nameMap(BuildContext context) {
  return {
    PagerControllerMode.stream: context.l10n.tr("流式", en: "Stream"),
    PagerControllerMode.pager: context.l10n.tr("分页器", en: "Pager"),
  };
}

String currentPagerControllerModeName(BuildContext context) =>
    _nameMap(context)[_value]!;

Future choosePagerControllerMode(BuildContext context) async {
  final nameMap = _nameMap(context);
  final target = await chooseMapDialog(context,
      title: context.l10n.tr("请选择分页模式", en: "Choose pagination mode"),
      values: nameMap.map((key, value) => MapEntry(value, key)));
  if (target != null && target != _value) {
    await methods.saveProperty(_propertyKey, "$target");
    _value = target;
    currentPagerControllerModeEvent.broadcast();
  }
}

PagerControllerMode _parse(String string) {
  return parseEnumPropertyValue(
    string,
    PagerControllerMode.values,
    PagerControllerMode.stream,
  );
}

Future initPagerControllerMode() async {
  _value = _parse(await methods.loadProperty(_propertyKey));
}
