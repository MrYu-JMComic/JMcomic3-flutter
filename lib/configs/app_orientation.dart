import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'enum_property.dart';

enum AppOrientation {
  normal,
  landscape,
  portrait,
}

String appOrientationName(AppOrientation type, BuildContext context) {
  switch (type) {
    case AppOrientation.normal:
      return context.l10n.tr("正常", en: "Normal");
    case AppOrientation.landscape:
      return context.l10n.tr("横屏", en: "Landscape");
    case AppOrientation.portrait:
      return context.l10n.tr("竖屏", en: "Portrait");
  }
}

const _propertyName = "appOrientation";
late AppOrientation _appOrientation;

Future initAppOrientation() async {
  _appOrientation = _fromString(await methods.loadProperty(_propertyName));
  _set();
}

AppOrientation _fromString(String valueForm) {
  return parseEnumPropertyValue(
    valueForm,
    AppOrientation.values,
    AppOrientation.normal,
  );
}

AppOrientation get currentAppOrientation => _appOrientation;

Future chooseAppOrientation(BuildContext context) async {
  final Map<String, AppOrientation> map = {};
  for (var element in AppOrientation.values) {
    map[appOrientationName(element, context)] = element;
  }
  final newAppOrientation = await chooseMapDialog(
    context,
    title: context.l10n.tr("请选择APP方向", en: "Choose app orientation"),
    values: map,
  );
  if (newAppOrientation != null) {
    await methods.saveProperty(_propertyName, "$newAppOrientation");
    _appOrientation = newAppOrientation;
    _set();
  }
}

Widget appOrientationWidget() {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return const SizedBox.shrink();
  }
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text(context.l10n.tr("APP方向", en: "App orientation")),
        subtitle: Text(appOrientationName(_appOrientation, context)),
        onTap: () async {
          await chooseAppOrientation(context);
          setState(() {});
        },
      );
    },
  );
}

void _set() {
  if (Platform.isAndroid || Platform.isIOS) {
    switch (_appOrientation) {
      case AppOrientation.normal:
        SystemChrome.setPreferredOrientations([]);
        break;
      case AppOrientation.landscape:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
      case AppOrientation.portrait:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        break;
    }
  }
}
