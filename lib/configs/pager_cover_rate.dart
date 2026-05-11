import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/enum_property.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

enum PagerCoverRate {
  rate3x4,
  rateSquare,
}

const _propertyName = "pager_cover_rate";
late PagerCoverRate _pagerCoverRate;

final pagerCoverRateEvent = Event();
PagerCoverRate get currentPagerCoverRate => _pagerCoverRate;

Future initPagerCoverRate() async {
  _pagerCoverRate = _fromString(await methods.loadProperty(_propertyName));
}

PagerCoverRate _fromString(String valueForm) {
  return parseEnumPropertyValue(
    valueForm,
    PagerCoverRate.values,
    PagerCoverRate.rate3x4,
  );
}

String pagerCoverRateName(PagerCoverRate type, BuildContext context) {
  switch (type) {
    case PagerCoverRate.rate3x4:
      return "3X4";
    case PagerCoverRate.rateSquare:
      return "1X1";
  }
}

Future choosePagerCoverRate(BuildContext context) async {
  final Map<String, PagerCoverRate> map = {};
  for (var element in PagerCoverRate.values) {
    map[pagerCoverRateName(element, context)] = element;
  }
  final newPagerCoverRate = await chooseMapDialog(
    context,
    title: context.l10n.tr("请选择封面比例", en: "Choose cover ratio"),
    values: map,
  );
  if (newPagerCoverRate != null) {
    await methods.saveProperty(_propertyName, "$newPagerCoverRate");
    _pagerCoverRate = newPagerCoverRate;
    pagerCoverRateEvent.broadcast();
  }
}
