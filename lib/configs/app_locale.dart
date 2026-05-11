import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/string_property.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _propertyName = 'app_locale';
const _followSystem = 'system';

String _localeCode = _followSystem;
final _event = Event();

Event get appLocaleEvent => _event;

/// 归一化本地持久化的语言配置。
///
/// 语言值可能来自旧本地属性、WebDAV 快照或手工迁移脚本；允许最多两层 JSON
/// 字符串包装、大小写差异和常见 Locale tag，但只输出当前应用真正支持的语言码。
/// 未知值回退为跟随系统，避免启动阶段因为脏配置进入不可显示状态。
String normalizeAppLocaleCode(String raw) {
  final value = parseStringPropertyValue(raw, trim: true)
      .toLowerCase()
      .replaceAll('_', '-');
  if (value == _followSystem || value == 'follow-system') {
    return _followSystem;
  }
  if (value == 'zh' || value.startsWith('zh-')) {
    return 'zh';
  }
  if (value == 'en' || value.startsWith('en-')) {
    return 'en';
  }
  return _followSystem;
}

Locale? get currentAppLocale {
  if (_localeCode == _followSystem) {
    return null;
  }
  return Locale(_localeCode);
}

Future initAppLocale() async {
  final value = await methods.loadProperty(_propertyName);
  _localeCode = normalizeAppLocaleCode(value);
  _event.broadcast();
}

String _nameOfLocale(BuildContext context, String code) {
  final l10n = context.l10n;
  switch (code) {
    case 'zh':
      return l10n.simplifiedChinese;
    case 'en':
      return l10n.english;
    default:
      return l10n.followSystem;
  }
}

Future chooseAppLocale(BuildContext context) async {
  final l10n = context.l10n;
  final value = await chooseMapDialog<String>(
    context,
    title: l10n.language,
    values: {
      l10n.followSystem: _followSystem,
      l10n.simplifiedChinese: 'zh',
      l10n.english: 'en',
    },
  );
  if (value == null || value == _localeCode) {
    return;
  }
  _localeCode = value;
  await methods.saveProperty(_propertyName, value);
  _event.broadcast();
}

Widget appLocaleSetting(BuildContext context) {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text(context.l10n.language),
        subtitle: Text(_nameOfLocale(context, _localeCode)),
        onTap: () async {
          await chooseAppLocale(context);
          setState(() {});
        },
      );
    },
  );
}
