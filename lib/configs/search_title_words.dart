/// 自动全屏

import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'bool_property.dart';

const _propertyName = "searchTitleWords";
late bool _searchTitleWords;

Future<void> initSearchTitleWords() async {
  _searchTitleWords = parseBoolPropertyValue(
    await methods.loadProperty(_propertyName),
    fallback: false,
  );
}

bool currentSearchTitleWords() {
  return _searchTitleWords;
}

Future<void> _chooseSearchTitleWords(BuildContext context) async {
  final l10n = context.l10n;
  String? result = await chooseListDialog<String>(context,
      title: l10n.tr("标题中的关键字点击搜索", en: "Tap title keywords to search"),
      values: [l10n.yes, l10n.no]);
  if (result != null) {
    var target = result == l10n.yes;
    await methods.saveProperty(_propertyName, "$target");
    _searchTitleWords = target;
  }
}

Widget searchTitleWordsSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text(
            context.l10n.tr("标题中的关键字点击搜索", en: "Tap title keywords to search")),
        subtitle: Text(context.l10n.boolLabel(_searchTitleWords)),
        onTap: () async {
          await _chooseSearchTitleWords(context);
          setState(() {});
        },
      );
    },
  );
}
