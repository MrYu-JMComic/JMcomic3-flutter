/// 代理设置

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'string_property.dart';

const String _propertyKey = "export_path";
late String _currentExportPath;

Future<String?> initExportPath() async {
  _currentExportPath = parseStringPropertyValue(
    await methods.loadProperty(_propertyKey),
    trim: true,
  );
  if (_currentExportPath.isEmpty) {
    if (Platform.isAndroid) {
      try {
        _currentExportPath = await methods.androidDefaultExportsDir();
      } catch (e) {
        _currentExportPath = "/sdcard/Download/jmtt2mic/exports";
      }
    } else if (Platform.isMacOS || Platform.isLinux) {
      _currentExportPath = await methods.getHomeDir();
      if (Platform.isMacOS) {
        _currentExportPath = _currentExportPath + "/Downloads";
      }
    } else if (Platform.isWindows) {
      _currentExportPath = "exports";
    }
  }
  return null;
}

String showExportPath(BuildContext context) {
  if (Platform.isIOS) {
    return context.l10n.tr(
      "\n\n随后可在文件管理中找到导出的内容",
      en: "\n\nThen you can find exported files in the Files app",
    );
  }
  return "\n\n$_currentExportPath";
}

Future _setExportPath(String folder) async {
  final value = parseStringPropertyValue(folder, trim: true);
  await methods.saveProperty(_propertyKey, value);
  _currentExportPath = value;
}

Widget displayExportPathInfo() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      final l10n = context.l10n;
      if (Platform.isIOS) {
        return Container(
          margin: const EdgeInsets.all(15),
          padding: const EdgeInsets.all(15),
          color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black)
              .withOpacity(.01),
          child: Text(
            l10n.tr(
              "您正在使用iOS设备:\n导出到文件的内容请打开系统自带文件管理进行浏览",
              en: "You are using iOS:\nOpen the system Files app to browse exported files",
            ),
          ),
        );
      }
      return Column(children: [
        if (!Platform.isMacOS)
          ListTile(
            onTap: () async {
              await chooseEx(context);
              setState(() {});
            },
            title:
                Text(l10n.tr("导出路径 (点击可修改)", en: "Export path (tap to edit)")),
            subtitle: Text(_currentExportPath),
          ),
        ...Platform.isAndroid
            ? [
                Container(height: 15),
                Container(
                  margin: const EdgeInsets.all(15),
                  padding: const EdgeInsets.all(15),
                  color: (Theme.of(context).textTheme.bodyMedium?.color ??
                          Colors.black)
                      .withOpacity(.01),
                  child: Text(
                    l10n.tr(
                      "您正在使用安卓设备:\n如果不能成功导出并且提示权限不足, 可以尝试在Download或Document下建立子目录进行导出",
                      en: "You are using Android:\nIf export fails due to insufficient permissions, try creating a subfolder under Download or Document",
                    ),
                  ),
                ),
              ]
            : [],
      ]);
    },
  );
}

Future<String> attachExportPath(BuildContext context) async {
  late String path;
  if (Platform.isIOS) {
    path = await methods.iosGetDocumentDir();
  } else {
    if (!await androidMangeStorageRequest()) {
      throw Exception(context.l10n.tr("申请权限被拒绝", en: "Permission denied"));
    }
    path = _currentExportPath;
  }
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await methods.mkdirs(path);
  } else if (Platform.isAndroid) {
    await methods.androidMkdirs(path);
  }
  return path;
}

Future chooseEx(BuildContext context) async {
  String? choose = await chooseFolder(context);
  if (choose != null) {
    await _setExportPath(choose);
  }
}
