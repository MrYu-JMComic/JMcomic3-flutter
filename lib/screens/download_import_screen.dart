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

  Widget _fileImportButton() {
    return MaterialButton(
      height: 80,
      onPressed: () async {
        if (!hasProAccess) {
          defaultToast(
            context,
            context.l10n.tr(
              "发电才能使用哦~",
              en: "Pro is required for this feature",
            ),
          );
          return;
        }
        if (!await androidMangeStorageRequest()) {
          defaultToast(
            context,
            context.l10n.tr("申请权限被拒绝", en: "Permission denied"),
          );
          return;
        }
        String? path;
        if (Platform.isAndroid) {
          path = await FilesystemPicker.open(
            title: context.l10n.tr('选择文件', en: 'Select file'),
            context: context,
            rootDirectory: Directory("/storage/emulated/0"),
            fsType: FilesystemType.file,
            folderIconColor: Colors.teal,
            allowedExtensions: ['.zip', '.jmi'],
            fileTileSelectMode: FileTileSelectMode.wholeTile,
          );
        } else {
          var ls = await FilePicker.platform.pickFiles(
            dialogTitle:
                context.l10n.tr('选择要导入的文件', en: 'Choose file to import'),
            allowMultiple: false,
            type: FileType.custom,
            allowedExtensions: ['zip', 'jmi'],
            allowCompression: false,
          );
          path = ls != null && ls.count > 0 ? ls.paths[0] : null;
        }
        if (path == null) {
          return;
        }
        final lowerPath = path.toLowerCase();
        final isJmZip = lowerPath.endsWith(".jm.zip");
        final isJmi = lowerPath.endsWith(".jmi");
        if (!isJmZip && !isJmi) {
          defaultToast(
            context,
            context.l10n.tr(
              "Only .jm.zip and .jmi files are supported",
              en: "Only .jm.zip and .jmi files are supported",
            ),
          );
          return;
        }
        try {
          setState(() {
            _importing = true;
          });
          if (isJmZip) {
            await methods.import_jm_zip(path);
          } else {
            await methods.import_jm_jmi(path);
          }
          setState(() {
            _importMessage = context.l10n.tr("导入成功", en: "Import succeeded");
          });
        } catch (e) {
          setState(() {
            _importMessage = context.l10n.tr("导入失败", en: "Import failed") + " $e";
          });
        } finally {
          setState(() {
            _importing = false;
          });
        }
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
        if (!hasProAccess) {
          defaultToast(
            context,
            context.l10n.tr(
              "发电才能使用哦~",
              en: "Pro is required for this feature",
            ),
          );
          return;
        }
        if (!await androidMangeStorageRequest()) {
          throw Exception(context.l10n.tr("申请权限被拒绝", en: "Permission denied"));
        }
        late String? path;
        try {
          path = await chooseFolder(context);
        } catch (e) {
          defaultToast(context, "$e");
          return;
        }
        if (path != null) {
          try {
            setState(() {
              _importing = true;
            });
            await methods.import_jm_dir(path);
            setState(() {
              _importMessage = context.l10n.tr("导入成功", en: "Import succeeded");
            });
          } catch (e) {
            setState(() {
              _importMessage =
                  context.l10n.tr("导入失败", en: "Import failed") + " $e";
            });
          } finally {
            setState(() {
              _importing = false;
            });
          }
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
