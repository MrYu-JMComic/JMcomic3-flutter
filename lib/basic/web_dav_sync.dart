import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/web_dav_url.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../configs/is_pro.dart';
import '../configs/web_dav_password.dart';
import '../configs/web_dav_sync_switch.dart';
import '../configs/web_dav_username.dart';
import 'commons.dart';

Future webDavSync(BuildContext context) async {
  try {
    await methods.webDavSync({
      "url": currentWebDavUrl,
      "username": currentWebUserName,
      "password": currentWebDavPassword,
      "direction": "Merge",
    });
    if (!context.mounted) return;
    defaultToast(
      context,
      context.l10n.tr("WebDav 同步成功", en: "WebDav sync succeeded"),
    );
  } catch (e, s) {
    debugPrient("$e\n$s");
    if (!context.mounted) return;
    defaultToast(
      context,
      context.l10n.tr("WebDav 同步失败", en: "WebDav sync failed") + ": $e",
    );
  }
}

Future webDavSyncUpload(BuildContext context) async {
  try {
    await methods.webDavSync({
      "url": currentWebDavUrl,
      "username": currentWebUserName,
      "password": currentWebDavPassword,
      "direction": "Upload",
    });
    if (!context.mounted) return;
    defaultToast(
      context,
      context.l10n.tr("WebDav 覆盖上传成功", en: "WebDav overwrite upload succeeded"),
    );
  } catch (e, s) {
    debugPrient("$e\n$s");
    if (!context.mounted) return;
    defaultToast(
      context,
      context.l10n.tr("WebDav 覆盖上传失败", en: "WebDav overwrite upload failed") +
          ": $e",
    );
  }
}

Future webDavSyncDownload(BuildContext context) async {
  try {
    await methods.webDavSync({
      "url": currentWebDavUrl,
      "username": currentWebUserName,
      "password": currentWebDavPassword,
      "direction": "Download",
    });
    if (!context.mounted) return;
    defaultToast(
      context,
      context.l10n.tr(
        "WebDav 覆盖下载成功",
        en: "WebDav overwrite download succeeded",
      ),
    );
  } catch (e, s) {
    debugPrient("$e\n$s");
    if (!context.mounted) return;
    defaultToast(
      context,
      context.l10n.tr("WebDav 覆盖下载失败", en: "WebDav overwrite download failed") +
          ": $e",
    );
  }
}

Future webDavSyncAuto(BuildContext context) async {
  if (currentWebDavSyncSwitch() && hasProAccess) {
    await webDavSync(context);
  }
}

var syncing = false;

Widget webDavSyncClick(BuildContext context) {
  return ListTile(
    title: Text(context.l10n.tr("立即同步", en: "Sync now")),
    onTap: () async {
      if (syncing) return;
      syncing = true;
      try {
        await webDavSync(context);
      } finally {
        syncing = false;
      }
    },
  );
}

Widget webDavSyncUploadClick(BuildContext context) {
  return ListTile(
    title: Text(context.l10n.tr("单向覆盖上传", en: "One-way overwrite upload")),
    onTap: () async {
      if (syncing) return;
      syncing = true;
      try {
        await webDavSyncUpload(context);
      } finally {
        syncing = false;
      }
    },
  );
}

Widget webDavSyncDownloadClick(BuildContext context) {
  return ListTile(
    title: Text(context.l10n.tr("单向覆盖下载", en: "One-way overwrite download")),
    onTap: () async {
      if (syncing) return;
      syncing = true;
      try {
        await webDavSyncDownload(context);
      } finally {
        syncing = false;
      }
    },
  );
}
