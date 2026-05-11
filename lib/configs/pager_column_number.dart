import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'int_property.dart';

const _propertyName = "pager_column_number";
const int _defaultPagerColumnNumber = 4;
const int _pagerColumnMin = 1;
const int _pagerColumnMax = 10;
late int _pagerColumnNumber;

int get pagerColumnNumber => _pagerColumnNumber;
final pageColumnEvent = Event();

Future initPagerColumnCount() async {
  final raw = await methods.loadProperty(_propertyName);
  _pagerColumnNumber = _parsePagerColumnNumber(raw);
}

int _parsePagerColumnNumber(String raw) {
  // 分页列数是启动期配置；旧缓存损坏时回退默认值，不阻断首页初始化。
  return parseBoundedIntPropertyValue(
    raw,
    fallback: _defaultPagerColumnNumber,
    min: _pagerColumnMin,
    max: _pagerColumnMax,
  );
}

Future choosePagerColumnCount(BuildContext context) async {
  final choose = await chooseListDialog(
    context,
    title: context.l10n.tr("分页每行漫画数", en: "Comics per row"),
    values: List<int>.generate(10, (i) => i + 1),
  );
  if (choose != null) {
    await methods.saveProperty(_propertyName, choose.toString());
    _pagerColumnNumber = choose;
    pageColumnEvent.broadcast();
  }
}
