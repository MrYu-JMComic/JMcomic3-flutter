import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

enum ReaderType {
  webtoon,
  gallery,
  webToonFreeZoom,
  twoPageGallery,
}

const _propertyName = "readerType";
late ReaderType _readerType;

Future initReaderType() async {
  _readerType = _fromString(await methods.loadProperty(_propertyName));
}

ReaderType _fromString(String valueForm) {
  for (var value in ReaderType.values) {
    if (value.toString() == valueForm) {
      return value;
    }
  }
  return ReaderType.values.first;
}

ReaderType get currentReaderType => _readerType;

String readerTypeName(ReaderType type, BuildContext context) {
  switch (type) {
    case ReaderType.webtoon:
      return "WebToon";
    case ReaderType.gallery:
      return context.l10n.tr("相册", en: "Gallery");
    case ReaderType.webToonFreeZoom:
      return context.l10n.tr(
        "自由缩放翻页",
        en: "Free zoom paging",
      );
    case ReaderType.twoPageGallery:
      return context.l10n.tr("双页相册", en: "Two-page gallery");
  }
}

Future chooseReaderType(BuildContext context) async {
  final Map<String, ReaderType> map = {};
  for (var element in ReaderType.values) {
    map[readerTypeName(element, context)] = element;
  }
  final newReaderType = await chooseMapDialog(
    context,
    title: context.l10n.tr("请选择阅读器类型", en: "Choose reader type"),
    values: map,
  );
  if (newReaderType != null) {
    await methods.saveProperty(_propertyName, "$newReaderType");
    _readerType = newReaderType;
  }
}
