import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _propertyKey = "pager_view_mode";
late PagerViewMode _value;
final Event currentPagerViewModeEvent = Event();

PagerViewMode get currentPagerViewMode => _value;

enum PagerViewMode {
  cover,
  info,
  titleInCover,
  titleAndCover,
}

Map<PagerViewMode, String> _nameMap(BuildContext context) {
  return {
    PagerViewMode.cover: context.l10n.tr("封面", en: "Cover"),
    PagerViewMode.info: context.l10n.tr("详情", en: "Info"),
    PagerViewMode.titleInCover: context.l10n.tr("图文1", en: "Title+Cover 1"),
    PagerViewMode.titleAndCover: context.l10n.tr("图文2", en: "Title+Cover 2"),
  };
}

String currentPagerViewModeName(BuildContext context) =>
    _nameMap(context)[_value]!;

Future choosePagerViewMode(BuildContext context) async {
  final nameMap = _nameMap(context);
  final target = await chooseMapDialog(context,
      title: context.l10n.tr("请选择展现形式", en: "Choose display mode"),
      values: nameMap.map((key, value) => MapEntry(value, key)));
  if (target != null && target != _value) {
    await methods.saveProperty(_propertyKey, "$target");
    _value = target;
    currentPagerViewModeEvent.broadcast();
  }
}

PagerViewMode _parse(String string) {
  for (var value in PagerViewMode.values) {
    if ("$value" == string) {
      return value;
    }
  }
  return PagerViewMode.cover;
}

Future initPagerViewMode() async {
  _value = _parse(await methods.loadProperty(_propertyKey));
}
