import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/images.dart';

const _propertyName = 'auto_clean';
const _lastCleanPropertyName = 'auto_clean_last_clean_ts';
const _defaultAutoCleanSeconds = 3600 * 24 * 7;
const _disabledValue = '0';

late String autoClean;

final Map<String, String> _nameMap = <String, String>{
  _disabledValue: 'off',
  (3600 * 12).toString(): '12h',
  (3600 * 24).toString(): '1d',
  (3600 * 24 * 3).toString(): '3d',
  (3600 * 24 * 7).toString(): '1w',
  (3600 * 24 * 30).toString(): '1m',
  (3600 * 24 * 30 * 12).toString(): '1y',
};

bool _cleaning = false;

class CacheCleanResult {
  final bool success;
  final Duration duration;
  final Object? error;

  const CacheCleanResult({
    required this.success,
    required this.duration,
    this.error,
  });
}

bool get cacheCleaningInProgress => _cleaning;

Future<void> initAutoClean() async {
  autoClean = await methods.loadProperty(_propertyName);
  if (!_nameMap.containsKey(autoClean)) {
    autoClean = _defaultAutoCleanSeconds.toString();
    await methods.saveProperty(_propertyName, autoClean);
  }
  final lastCleanTs = await _loadLastCleanTs();
  if (lastCleanTs <= 0) {
    await _saveLastCleanTs(_nowSeconds());
  }
}

String autoCleanName() {
  return _nameMap[autoClean] ?? '${_autoCleanSeconds()}s';
}

String autoCleanNameOf(BuildContext context) {
  final raw = _nameMap[autoClean];
  if (raw == null) {
    final seconds = _autoCleanSeconds();
    return context.l10n.tr('${seconds}秒', en: '${seconds}s');
  }
  return _autoCleanLabel(context, raw);
}

String _autoCleanLabel(BuildContext context, String raw) {
  switch (raw) {
    case 'off':
      return context.l10n.tr('关闭', en: 'Off');
    case '12h':
      return context.l10n.tr('12小时', en: '12 hours');
    case '1d':
      return context.l10n.tr('1天', en: '1 day');
    case '3d':
      return context.l10n.tr('3天', en: '3 days');
    case '1w':
      return context.l10n.tr('1周', en: '1 week');
    case '1m':
      return context.l10n.tr('1月', en: '1 month');
    case '1y':
      return context.l10n.tr('1年', en: '1 year');
    default:
      return context.l10n.tr(raw);
  }
}

Future<void> chooseAutoClean(BuildContext context) async {
  final values = _nameMap.map(
    (key, value) => MapEntry(_autoCleanLabel(context, value), key),
  );
  final choose = await chooseMapDialog<String>(
    context,
    title: context.l10n.tr('选择自动清理时间', en: 'Choose auto-clean interval'),
    values: values,
  );
  if (choose == null || choose == autoClean) {
    return;
  }
  final beforeEnabled = _autoCleanSeconds() > 0;
  autoClean = choose;
  await methods.saveProperty(_propertyName, choose);

  final nowEnabled = _autoCleanSeconds() > 0;
  if (!beforeEnabled && nowEnabled) {
    await _saveLastCleanTs(_nowSeconds());
  }
  if (nowEnabled) {
    defaultToast(
      context,
      context.l10n.tr(
        '自动清理: ${autoCleanNameOf(context)}',
        en: 'Auto clean: ${autoCleanNameOf(context)}',
      ),
    );
  } else {
    defaultToast(
        context, context.l10n.tr('已关闭自动清理', en: 'Auto clean disabled'));
  }
}

Future<void> runAutoCleanIfNeeded() async {
  if (_cleaning) {
    return;
  }
  final seconds = _autoCleanSeconds();
  if (seconds <= 0) {
    return;
  }

  final now = _nowSeconds();
  final lastCleanTs = await _loadLastCleanTs();
  if (lastCleanTs <= 0) {
    await _saveLastCleanTs(now);
    return;
  }

  if (now - lastCleanTs < seconds) {
    return;
  }

  final result = await cleanCache();
  if (!result.success) {
    debugPrient('auto clean failed: ${result.error}');
  }
}

Future<CacheCleanResult> cleanCache() async {
  if (_cleaning) {
    return CacheCleanResult(
      success: false,
      duration: Duration.zero,
      error: StateError('Cache clean already in progress'),
    );
  }

  _cleaning = true;
  final sw = Stopwatch()..start();
  try {
    await methods.cleanAllCache();
    clearAllImageMemoryCaches();
    await _saveLastCleanTs(_nowSeconds());
    return CacheCleanResult(success: true, duration: sw.elapsed);
  } catch (e, st) {
    debugPrient('$e\n$st');
    return CacheCleanResult(success: false, duration: sw.elapsed, error: e);
  } finally {
    sw.stop();
    _cleaning = false;
  }
}

int _autoCleanSeconds() {
  return _parseInt(autoClean, fallback: _defaultAutoCleanSeconds);
}

int _nowSeconds() {
  return DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

Future<int> _loadLastCleanTs() async {
  final raw = await methods.loadProperty(_lastCleanPropertyName);
  return _parseInt(raw, fallback: 0);
}

Future<void> _saveLastCleanTs(int value) async {
  await methods.saveProperty(_lastCleanPropertyName, '$value');
}

int _parseInt(String value, {required int fallback}) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0) {
    return fallback;
  }
  return parsed;
}
