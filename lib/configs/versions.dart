import 'dart:async' show Future;
import 'dart:convert';

import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/http_client.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';

import 'int_property.dart';
import 'ignore_upgrade_pop.dart';

const _repoOwner = "MrYu-JMComic";
const _repoName = "JMcomic3-flutter";
const _releaseLatestUrl =
    "https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest";
const _releaseLatestMirrorUrls = [
  "https://ghproxy.com/https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest",
  "https://ghproxy.net/https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest",
];
const _releaseLatestPageUrl =
    "https://github.com/$_repoOwner/$_repoName/releases/latest";
const _releaseLatestPageMirrorUrls = [
  "https://r.jina.ai/http://github.com/$_repoOwner/$_repoName/releases/latest",
];
const releasePageUrl = "https://github.com/$_repoOwner/$_repoName/releases/";
const _defaultDownloadUrl = releasePageUrl;

const _versionAssets = 'lib/assets/version.txt';
final RegExp _versionExp = RegExp(r"^v\d+\.\d+\.\d+(\+\d+)?$");

late String _version;
String? _latestVersion;
String? _latestVersionName;
String? _latestVersionInfo;
String _downloadUrl = _defaultDownloadUrl;

const _propertyName = "checkVersionPeriod";
const _latestNameCacheKey = "latestVersionNameCache";
const _latestInfoCacheKey = "latestVersionInfoCache";
const _latestRepoCacheKey = "latestVersionRepoCache";
const _repoToken = "$_repoOwner/$_repoName";
final _repoTokenLower =
    "${_repoOwner.toLowerCase()}/${_repoName.toLowerCase()}";
const _useBackendAppConfig = false;
late int _period = -1;

Future initVersion() async {
  try {
    _version = (await rootBundle.loadString(_versionAssets)).trim();
  } catch (e) {
    _version = "dirty";
  }
  _latestVersionName = await methods.loadProperty(_latestNameCacheKey);
  if (_latestVersionName == "") {
    _latestVersionName = null;
  }
  _latestVersionInfo = await methods.loadProperty(_latestInfoCacheKey);
  if (_latestVersionInfo == "") {
    _latestVersionInfo = null;
  }
  final latestRepoCache = await methods.loadProperty(_latestRepoCacheKey);
  if (latestRepoCache != _repoToken) {
    // Repo source changed: drop stale cached latest-version content.
    _latestVersionName = null;
    _latestVersionInfo = null;
    await methods.saveProperty(_latestNameCacheKey, "");
    await methods.saveProperty(_latestInfoCacheKey, "");
    await methods.saveProperty(_latestRepoCacheKey, _repoToken);
  }
  if (_latestVersionName == null && _versionExp.hasMatch(_version)) {
    _latestVersionName = _version;
  }
  final vStr = await methods.loadProperty(_propertyName);
  // 升级检查周期属于启动路径配置；旧缓存损坏时回退 0，避免版本页初始化直接抛异常。
  _period = parseBoundedIntPropertyValue(vStr, fallback: 0, min: 0);
  if (_period > 0) {
    if (DateTime.now().millisecondsSinceEpoch > _period) {
      await methods.saveProperty(_propertyName, "0");
      _period = 0;
    }
  }
}

var versionEvent = Event<EventArgs>();

String currentVersion() {
  return _version;
}

String? get latestVersion => _latestVersion;

String? get latestVersionName => _latestVersionName;

String? latestVersionInfo() {
  return _latestVersionInfo;
}

String latestDownloadUrl() {
  return _sanitizeDownloadUrl(_downloadUrl);
}

Future autoCheckNewVersion() {
  if (_period != 0) {
    return Future.value();
  }
  return _versionCheck();
}

Future manualCheckNewVersion(BuildContext context) async {
  try {
    defaultToast(context, "\u68c0\u67e5\u66f4\u65b0\u4e2d");
    await _versionCheck();
    defaultToast(context, "\u68c0\u67e5\u66f4\u65b0\u6210\u529f");
  } catch (e) {
    defaultToast(context, "\u68c0\u67e5\u66f4\u65b0\u5931\u8d25: $e");
  }
}

Future silentCheckNewVersion() async {
  await _versionCheck();
}

bool dirtyVersion() {
  return !_versionExp.hasMatch(_version);
}

Future _versionCheck() async {
  if (_versionExp.hasMatch(_version)) {
    _downloadUrl = _defaultDownloadUrl;
    var loadedByAppConfig = false;
    if (_useBackendAppConfig) {
      try {
        loadedByAppConfig = await _applyRemoteAppConfig();
      } catch (_) {
        // fall through to github release API
      }
    }
    if (!loadedByAppConfig) {
      try {
        final json = await _fetchLatestReleaseJson();
        final latestTag = json["tag_name"]?.toString().trim() ?? "";
        final latestName = json["name"]?.toString().trim() ?? "";
        final latestVersion = _pickLatestVersion(latestTag, latestName);
        if (latestVersion.isNotEmpty) {
          final body = json["body"]?.toString() ?? "";
          _latestVersionName = latestVersion;
          _latestVersionInfo = body;
          _latestVersion = latestVersion != _version ? latestVersion : null;
          await methods.saveProperty(_latestNameCacheKey, latestVersion);
          await methods.saveProperty(_latestInfoCacheKey, body);
        } else {
          _latestVersion = null;
          _latestVersionName = null;
          _latestVersionInfo = null;
        }
      } catch (e) {
        // keep cached values when network fetch fails
      }
      if ((_latestVersionInfo ?? "").trim().isEmpty) {
        final pageInfo = await _fetchLatestReleaseInfoFromPage();
        if (pageInfo != null && pageInfo.trim().isNotEmpty) {
          _latestVersionInfo = pageInfo;
          await methods.saveProperty(_latestInfoCacheKey, pageInfo);
        }
      }
    }
  }
  versionEvent.broadcast();
  debugPrient("$_latestVersion");
}

Future<bool> _applyRemoteAppConfig() async {
  final config = await methods.appConfig();
  if (config.isEmpty) {
    return false;
  }
  final remoteDownloadUrl = config["downloadUrl"]?.toString();
  final remoteDownloadUrlTrimmed = remoteDownloadUrl?.trim() ?? "";
  final safeDownloadUrl = _sanitizeDownloadUrl(remoteDownloadUrlTrimmed);
  if (remoteDownloadUrlTrimmed.isNotEmpty &&
      safeDownloadUrl == _defaultDownloadUrl &&
      remoteDownloadUrlTrimmed != _defaultDownloadUrl) {
    // Ignore remote config if it points to a non-owned repository.
    _downloadUrl = _defaultDownloadUrl;
    debugPrient(
        "ignore untrusted remote downloadUrl: $remoteDownloadUrlTrimmed");
    return false;
  }
  _downloadUrl = safeDownloadUrl;

  final latestTag = config["latestVersion"]?.toString().trim() ?? "";
  final latestName = config["latestVersionName"]?.toString().trim() ?? "";
  final latestVersion = _pickLatestVersion(latestTag, latestName);
  if (latestVersion.isEmpty) {
    return false;
  }

  final body = config["changeLog"]?.toString() ?? "";
  _latestVersionName = latestVersion;
  _latestVersionInfo = body;
  _latestVersion = latestVersion != _version ? latestVersion : null;
  await methods.saveProperty(_latestNameCacheKey, latestVersion);
  await methods.saveProperty(_latestInfoCacheKey, body);
  return true;
}

String _sanitizeDownloadUrl(String? candidate) {
  final text = (candidate ?? "").trim();
  if (text.isEmpty) {
    return _defaultDownloadUrl;
  }
  Uri uri;
  try {
    uri = Uri.parse(text);
  } catch (_) {
    return _defaultDownloadUrl;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != "http" && scheme != "https") {
    return _defaultDownloadUrl;
  }
  final lower = text.toLowerCase();
  if (!lower.contains(_repoTokenLower)) {
    return _defaultDownloadUrl;
  }
  return text;
}

String _pickLatestVersion(String tagName, String releaseName) {
  if (_versionExp.hasMatch(tagName)) {
    return tagName;
  }
  if (_versionExp.hasMatch(releaseName)) {
    return releaseName;
  }
  if (tagName.isNotEmpty) {
    return tagName;
  }
  return releaseName;
}

Future<Map<String, dynamic>> _fetchLatestReleaseJson() async {
  final urls = [_releaseLatestUrl, ..._releaseLatestMirrorUrls];
  Object? lastError;
  for (final url in urls) {
    try {
      try {
        final text = await methods.httpGet(url);
        final decoded = jsonDecode(text);
        if (decoded is Map && _isRateLimitError(decoded)) {
          throw StateError("rate_limit");
        }
        return decoded;
      } catch (_) {
        final text = await _httpGetViaDart(url);
        final decoded = jsonDecode(text);
        if (decoded is Map && _isRateLimitError(decoded)) {
          throw StateError("rate_limit");
        }
        return decoded;
      }
    } catch (e) {
      lastError = e;
    }
  }
  if (lastError != null) {
    // ignore: only_throw_errors
    throw lastError;
  }
  return <String, dynamic>{};
}

Future<String> _httpGetViaDart(String url) async {
  return AppHttpClient.getText(
    url,
    headers: const {
      "User-Agent": "Mozilla/5.0",
      "Accept": "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    },
    requestTimeout: const Duration(seconds: 12),
    retries: 1,
  );
}

Future<String?> _fetchLatestReleaseInfoFromPage() async {
  final urls = [_releaseLatestPageUrl, ..._releaseLatestPageMirrorUrls];
  for (final url in urls) {
    try {
      final text = await _httpGetViaDart(url);
      final parsed = _extractReleaseBodyFromPage(text);
      if (parsed != null && parsed.trim().isNotEmpty) {
        return parsed.trim();
      }
    } catch (_) {}
  }
  return null;
}

String? _extractReleaseBodyFromPage(String text) {
  var body = text;
  final repoToken = "$_repoOwner/$_repoName";
  final hasRepoHint =
      body.contains(repoToken) || body.contains("$_repoName/releases");
  if (!hasRepoHint) {
    return null;
  }
  final marker = "Markdown Content:";
  final markerIndex = body.indexOf(marker);
  if (markerIndex >= 0) {
    body = body.substring(markerIndex + marker.length);
  } else if (body.contains("<meta") || body.contains("<html")) {
    final ogUrl = RegExp(r'property="og:url" content="([^"]*)"', dotAll: true)
            .firstMatch(body)
            ?.group(1) ??
        "";
    final ogDesc =
        RegExp(r'property="og:description" content="([^"]*)"', dotAll: true)
                .firstMatch(body)
                ?.group(1) ??
            "";
    final ogLooksLikeRelease = ogUrl.contains(repoToken) &&
        (ogUrl.contains("/releases/tag/") ||
            ogUrl.contains("/releases/latest"));
    if (ogLooksLikeRelease && ogDesc.trim().isNotEmpty) {
      final desc = _decodeHtmlEntities(ogDesc);
      if (desc.trim().isNotEmpty) {
        return desc.trim();
      }
    }
    final md = RegExp(
      r'<div[^>]*class="[^"]*markdown-body[^"]*"[^>]*>([\s\S]*?)</div>',
      caseSensitive: false,
    ).firstMatch(body);
    if (md != null) {
      body = md.group(1) ?? "";
      body = body
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), "\n")
          .replaceAll(RegExp(r'</p>', caseSensitive: false), "\n")
          .replaceAll(RegExp(r'</li>', caseSensitive: false), "\n");
      body = body.replaceAll(RegExp(r'<[^>]+>'), "");
      body = _decodeHtmlEntities(body).trim();
    }
  }
  body = body.trim();
  if (body.isEmpty) return null;
  final assetsIndex = body.indexOf("## Assets");
  if (assetsIndex > 0) {
    body = body.substring(0, assetsIndex).trim();
  }
  final lines = body.split("\n");
  if (lines.isNotEmpty && lines.first.startsWith("#")) {
    body = lines.skip(1).join("\n").trim();
  }
  return body.isEmpty ? null : body;
}

bool _isRateLimitError(Map<dynamic, dynamic> json) {
  final message = json["message"];
  if (message is! String) return false;
  return message.toLowerCase().contains("rate limit");
}

String _decodeHtmlEntities(String input) {
  return input
      .replaceAll("&amp;", "&")
      .replaceAll("&lt;", "<")
      .replaceAll("&gt;", ">")
      .replaceAll("&quot;", "\"")
      .replaceAll("&#39;", "'");
}

String _periodText() {
  if (_period < 0) {
    return "\u81ea\u52a8\u68c0\u67e5\u66f4\u65b0\u5df2\u5173\u95ed";
  }
  if (_period == 0) {
    return "\u81ea\u52a8\u68c0\u67e5\u66f4\u65b0\u5df2\u5f00\u542f";
  }
  return "\u4e0b\u6b21\u68c0\u67e5\u65f6\u95f4: " +
      formatDateTimeToDateTime(
        DateTime.fromMillisecondsSinceEpoch(_period),
      );
}

Future _choosePeriod(BuildContext context) async {
  var result = await chooseListDialog(
    context,
    title: "\u81ea\u52a8\u68c0\u67e5\u66f4\u65b0",
    values: [
      "\u5f00\u542f",
      "\u4e00\u5468\u540e",
      "\u4e00\u4e2a\u6708\u540e",
      "\u4e00\u5e74\u540e",
      "\u5173\u95ed"
    ],
    tips: "\u91cd\u542f\u540e\u7ea2\u70b9\u4f1a\u6d88\u5931",
  );
  switch (result) {
    case "\u5f00\u542f":
      await methods.saveProperty(_propertyName, "0");
      _period = 0;
      break;
    case "\u4e00\u5468\u540e":
      var time = DateTime.now().millisecondsSinceEpoch + (1000 * 3600 * 24 * 7);
      await methods.saveProperty(_propertyName, "$time");
      _period = time;
      break;
    case "\u4e00\u4e2a\u6708\u540e":
      var time =
          DateTime.now().millisecondsSinceEpoch + (1000 * 3600 * 24 * 30);
      await methods.saveProperty(_propertyName, "$time");
      _period = time;
      break;
    case "\u4e00\u5e74\u540e":
      var time =
          DateTime.now().millisecondsSinceEpoch + (1000 * 3600 * 24 * 365);
      await methods.saveProperty(_propertyName, "$time");
      _period = time;
      break;
    case "\u5173\u95ed":
      await methods.saveProperty(_propertyName, "-1");
      _period = -1;
      break;
  }
}

Widget autoUpdateCheckSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: const Text("\u81ea\u52a8\u68c0\u67e5\u66f4\u65b0"),
        subtitle: Text(_periodText()),
        onTap: () async {
          await _choosePeriod(context);
          setState(() {});
        },
      );
    },
  );
}

String formatDateTimeToDateTime(DateTime c) {
  try {
    return "${add0(c.year, 4)}-${add0(c.month, 2)}-${add0(c.day, 2)} ${add0(c.hour, 2)}:${add0(c.minute, 2)}";
  } catch (e) {
    return "-";
  }
}

var _display = true;

void versionPop(BuildContext context) {
  if (latestVersion != null && _display && !currentIgnoreUpgradePop()) {
    _display = false;
    TopConfirm.topConfirm(
      context,
      "\u53d1\u73b0\u65b0\u7248\u672c",
      "\u53d1\u73b0\u65b0\u7248\u672c $latestVersion\uff0c\u8bf7\u5230\u5173\u4e8e\u9875\u9762\u66f4\u65b0",
    );
  }
}

class TopConfirm {
  static topConfirm(BuildContext context, String title, String message,
      {Function()? afterIKnown}) {
    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(builder: (BuildContext context) {
      return LayoutBuilder(
        builder: (
          BuildContext context,
          BoxConstraints constraints,
        ) {
          var mq = MediaQuery.of(context).size.width - 30;
          return Material(
            color: Colors.transparent,
            child: Container(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.35),
              ),
              child: Column(
                children: [
                  Expanded(child: Container()),
                  SizedBox(
                    width: mq,
                    child: Card(
                      child: Column(
                        children: [
                          Container(height: 30),
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 28,
                            ),
                          ),
                          Container(height: 15),
                          Text(
                            message,
                            style: const TextStyle(
                              fontSize: 16,
                            ),
                          ),
                          Container(height: 25),
                          MaterialButton(
                            elevation: 0,
                            color: Colors.grey.shade700.withOpacity(.1),
                            onPressed: () {
                              overlayEntry.remove();
                            },
                            child: const Text("\u77e5\u9053\u4e86"),
                          ),
                          Container(height: 30),
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: Container()),
                ],
              ),
            ),
          );
        },
      );
    });
    final overlay = Overlay.of(context);
    overlay.insert(overlayEntry);
  }
}
