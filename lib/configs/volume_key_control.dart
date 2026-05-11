/// 自动全屏

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'bool_property.dart';

const _propertyName = "volumeKeyControl";
late bool _volumeKeyControl;

Future<void> initVolumeKeyControl() async {
  _volumeKeyControl = parseBoolPropertyValue(
    await methods.loadProperty(_propertyName),
    fallback: false,
  );
}

bool currentVolumeKeyControl() {
  return _volumeKeyControl;
}

Future<void> _chooseVolumeKeyControl(BuildContext context) async {
  final l10n = context.l10n;
  String? result = await chooseListDialog<String>(context,
      title: l10n.tr("音量键翻页", en: "Volume keys for page turn"),
      values: [l10n.yes, l10n.no]);
  if (result != null) {
    var target = result == l10n.yes;
    await methods.saveProperty(_propertyName, "$target");
    _volumeKeyControl = target;
  }
}

Widget volumeKeyControlSetting() {
  if (!(Platform.isAndroid)) {
    return Container();
  }
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text(context.l10n.tr("音量键翻页", en: "Volume keys for page turn")),
        subtitle: Text(context.l10n.boolLabel(_volumeKeyControl)),
        onTap: () async {
          await _chooseVolumeKeyControl(context);
          setState(() {});
        },
      );
    },
  );
}
