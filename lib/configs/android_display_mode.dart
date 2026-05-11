/// 显示模式, 仅安卓有效

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/android_version.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import 'string_property.dart';

const _propertyName = "androidDisplayMode";
List<String> _modes = [];
String _androidDisplayMode = "";

Future initAndroidDisplayMode() async {
  if (Platform.isAndroid) {
    _modes = await methods.loadAndroidModes();
    _androidDisplayMode = normalizeAndroidDisplayModeValue(
      await methods.loadProperty(_propertyName),
      _modes,
    );
    await _changeMode();
  }
}

String normalizeAndroidDisplayModeValue(String raw, Iterable<String> modes) {
  final value = parseStringPropertyValue(raw, trim: true);
  if (value.isEmpty) {
    return "";
  }
  // 刷新率配置最终会传给平台层；只接受当前设备枚举出的模式，旧缓存/手工迁移的脏值回退默认模式。
  return modes.contains(value) ? value : "";
}

Future _changeMode() async {
  await methods.setAndroidMode(_androidDisplayMode);
}

Future<void> _chooseAndroidDisplayMode(BuildContext context) async {
  if (Platform.isAndroid) {
    List<String> list = [""];
    list.addAll(_modes);
    String? result = await chooseListDialog<String>(
      context,
      title: context.l10n.tr("安卓屏幕刷新率", en: "Android refresh rate"),
      values: list,
    );
    if (result != null) {
      final value = normalizeAndroidDisplayModeValue(result, _modes);
      await methods.saveProperty(_propertyName, value);
      _androidDisplayMode = value;
      await _changeMode();
    }
  }
}

Widget androidDisplayModeSetting() {
  if (Platform.isAndroid && androidVersion >= 23) {
    return StatefulBuilder(
      builder: (BuildContext context, void Function(void Function()) setState) {
        return ListTile(
          title: Text(
            context.l10n.tr("屏幕刷新率(安卓)", en: "Refresh rate (Android)"),
          ),
          subtitle: Text(_androidDisplayMode),
          onTap: () async {
            await _chooseAndroidDisplayMode(context);
            setState(() {});
          },
        );
      },
    );
  }
  return Container();
}
