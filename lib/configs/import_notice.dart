import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

Widget importNotice(BuildContext context) {
  if (Platform.isAndroid) {
    return Container(
      margin: const EdgeInsets.all(15),
      padding: const EdgeInsets.all(15),
      color: (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black)
          .withOpacity(.01),
      child: Text(
        context.l10n.tr(
          "您正在使用安卓设备？\n如果不能导入导出并且提示权限不足，可以尝试在 Download 或 Document 下建立子目录进行导入。",
          en: "You are using Android:\nIf import/export fails due to insufficient permissions, try creating a subfolder under Download or Document for import",
        ),
      ),
    );
  }
  return Container();
}
