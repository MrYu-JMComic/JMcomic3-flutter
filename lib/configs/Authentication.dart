import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'DesktopAuthenticationScreen.dart';
import 'android_version.dart';
import 'bool_property.dart';

const _propertyName = "authentication";
late bool _authentication;

Future<void> initAuthentication() async {
  if (Platform.isIOS || androidVersion >= 29) {
    _authentication = parseBoolPropertyValue(
      await methods.loadProperty(_propertyName),
      fallback: false,
    );
  } else if (Platform.isAndroid) {
    _authentication = false;
  } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    _authentication = await needDesktopAuthentication();
  } else {
    _authentication = false;
  }
}

bool currentAuthentication() {
  return _authentication;
}

Future<bool> verifyAuthentication(BuildContext context) async {
  if (Platform.isIOS || androidVersion >= 29) {
    return await methods.verifyAuthentication();
  }
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return await Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const VerifyPassword())) ==
        true;
  }
  return false;
}

Widget authenticationSetting() {
  if (Platform.isIOS || androidVersion >= 29) {
    return StatefulBuilder(
      builder: (BuildContext context, void Function(void Function()) setState) {
        final l10n = context.l10n;
        return ListTile(
          title: Text(l10n.tr(
            "进入APP时验证身份？如果系统已经录入密码或指纹",
            en: "Verify identity when entering app? (if system credential exists)",
          )),
          subtitle: Text(l10n.boolLabel(_authentication)),
          onTap: () async {
            await _chooseAuthentication(context);
            setState(() {});
          },
        );
      },
    );
  }
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return StatefulBuilder(builder: (
      BuildContext context,
      void Function(void Function()) setState,
    ) {
      final l10n = context.l10n;
      return ListTile(
        title: Text(l10n.tr("设置应用程序密码", en: "Set application password")),
        onTap: () async {
          Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const SetPassword()));
        },
      );
    });
  }
  return Container();
}

Future<void> _chooseAuthentication(BuildContext context) async {
  if (await methods.verifyAuthentication()) {
    final l10n = context.l10n;
    String? result = await chooseListDialog<String>(
      context,
      title: l10n.tr("进入APP时验证身份？", en: "Verify identity when entering app?"),
      values: [l10n.yes, l10n.no],
    );
    if (result != null) {
      var target = result == l10n.yes;
      await methods.saveProperty(_propertyName, "$target");
      _authentication = target;
    }
  }
}
