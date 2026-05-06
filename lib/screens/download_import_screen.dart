import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import '../configs/import_notice.dart';
import '../configs/is_pro.dart';
import 'components/content_loading.dart';
import 'components/right_click_pop.dart';
import 'download_import_shared.dart';

// 导入
class DownloadImportScreen extends StatefulWidget {
  const DownloadImportScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadImportScreenState();
}

class _DownloadImportScreenState extends State<DownloadImportScreen> {
  bool _importing = false;
  String _importMessage = "";

  @override
  void initState() {
    // registerEvent(_onMessageChange, "EXPORT");
    super.initState();
  }

  @override
  void dispose() {
    // unregisterEvent(_onMessageChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(
      child: buildScreen(context),
      context: context,
      canPop: !_importing,
    );
  }

  Widget buildScreen(BuildContext context) {
    if (_importing) {
      return Scaffold(
        body: ContentLoading(label: _importMessage),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.tr('导入', en: 'Import')),
      ),
      body: ListView(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            child: Text(_importMessage),
          ),
          Container(height: 20),
          importNotice(context),
          Container(height: 20),
          _fileImportButton(),
          Container(height: 20),
          _importDirFilesZipButton(),
          Container(height: 20),
          Container(height: 20),
        ],
      ),
    );
  }

  Future<bool> _ensureImportAllowed() async {
    if (!hasProAccess) {
      defaultToast(
        context,
        context.l10n.tr(
          "发电才能使用哦~",
          en: "Pro is required for this feature",
        ),
      );
      return false;
    }
    final permissionDeniedMessage =
        context.l10n.tr("申请权限被拒绝", en: "Permission denied");
    if (!await androidMangeStorageRequest()) {
      if (!mounted) {
        return false;
      }
      defaultToast(context, permissionDeniedMessage);
      return false;
    }
    return true;
  }

  void _setImportState({bool? importing, String? message}) {
    if (!mounted) {
      return;
    }
    setState(() {
      if (importing != null) {
        _importing = importing;
      }
      if (message != null) {
        _importMessage = message;
      }
    });
  }

  /// 导入会跨文件选择器和 Rust 后端执行；用户在等待时可能返回上一页。
  /// 所有状态更新集中到这里并检查 mounted，避免异步回调更新已销毁的页面。
  Future<void> _runImport(Future<void> Function() importTask) async {
    final successMessage = context.l10n.tr("导入成功", en: "Import succeeded");
    final failedPrefix = context.l10n.tr("导入失败", en: "Import failed");

    _setImportState(importing: true);
    try {
      await importTask();
      _setImportState(message: successMessage);
    } catch (e) {
      _setImportState(message: "$failedPrefix $e");
    } finally {
      _setImportState(importing: false);
    }
  }

  Future<String?> _chooseImportFilePath() async {
    if (Platform.isAndroid) {
      return FilesystemPicker.open(
        title: context.l10n.tr('选择文件', en: 'Select file'),
        context: context,
        rootDirectory: Directory("/storage/emulated/0"),
        fsType: FilesystemType.file,
        folderIconColor: Colors.teal,
        allowedExtensions: ['.zip', '.jmi'],
        fileTileSelectMode: FileTileSelectMode.wholeTile,
      );
    }

    final files = await FilePicker.platform.pickFiles(
      dialogTitle: context.l10n.tr('选择要导入的文件', en: 'Choose file to import'),
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['zip', 'jmi'],
      allowCompression: false,
    );
    return files != null && files.count > 0 ? files.paths[0] : null;
  }

  Widget _fileImportButton() {
    return MaterialButton(
      height: 80,
      onPressed: () async {
        if (!await _ensureImportAllowed()) {
          return;
        }
        if (!mounted) {
          return;
        }
        final path = await _chooseImportFilePath();
        if (!mounted) {
          return;
        }
        if (path == null) {
          return;
        }
        final kind = detectDownloadImportArchiveKind(path);
        if (kind == null) {
          defaultToast(
            context,
            context.l10n.tr(
              "Only .jm.zip and .jmi files are supported",
              en: "Only .jm.zip and .jmi files are supported",
            ),
          );
          return;
        }
        await _runImport(() async {
          if (kind == DownloadImportArchiveKind.jmZip) {
            await methods.import_jm_zip(path);
          } else {
            await methods.import_jm_jmi(path);
          }
        });
      },
      child: Text(
        context.l10n.tr(
              '选择 .jm.zip 文件进行导入\n选择 jmi 文件进行导入',
              en: 'Import a .jm.zip file\nImport a .jmi file',
            ) +
            (!hasProAccess
                ? "\n${context.l10n.tr("(发电后使用)", en: "(Pro required)")}"
                : ""),
        style: TextStyle(
          color: !hasProAccess ? Colors.grey : null,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _importDirFilesZipButton() {
    return MaterialButton(
      height: 80,
      onPressed: () async {
        if (!await _ensureImportAllowed()) {
          return;
        }
        if (!mounted) {
          return;
        }
        late String? path;
        try {
          path = await chooseFolder(context);
        } catch (e) {
          if (!mounted) {
            return;
          }
          defaultToast(context, "$e");
          return;
        }
        if (!mounted) {
          return;
        }
        if (path != null) {
          final importPath = path;
          await _runImport(() async {
            await methods.import_jm_dir(importPath);
          });
        }
      },
      child: Text(
        context.l10n.tr(
              '选择文件夹\n(导入里面所有的 zip/jmi)',
              en: 'Choose a folder\n(Import all zip/jmi files inside)',
            ) +
            (!hasProAccess
                ? "\n${context.l10n.tr("(发电后使用)", en: "(Pro required)")}"
                : ""),
        style: TextStyle(
          color: !hasProAccess ? Colors.grey : null,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
