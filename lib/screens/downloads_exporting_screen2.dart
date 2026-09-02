import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../configs/export_path.dart';
import '../configs/is_pro.dart';
import 'components/content_loading.dart';
import 'components/right_click_pop.dart';

class DownloadsExportingScreen2 extends StatefulWidget {
  final List<int> idList;

  const DownloadsExportingScreen2({Key? key, required this.idList})
    : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadsExportingScreen2State();
}

class _DownloadsExportingScreen2State extends State<DownloadsExportingScreen2> {
  bool exporting = false;
  bool exported = false;
  bool exportFail = false;
  dynamic e;
  String exportMessage = '';
  bool deleteExport = false;

  Widget _body() {
    final l10n = context.l10n;
    final proSuffix = !hasProAccess
        ? '\n${l10n.tr('(发电后使用)', en: '(Pro required)')}'
        : '';
    if (exporting) {
      return ContentLoading(
        label: exportMessage.isEmpty
            ? l10n.tr('正在导出', en: 'Exporting')
            : l10n.tr(exportMessage),
      );
    }
    if (exportFail) {
      return Center(
        child: Text(
          '${l10n.tr('导出失败', en: 'Export failed')}\n$e\n($exportMessage)',
        ),
      );
    }
    if (exported) {
      return Center(child: Text(l10n.tr('导出成功', en: 'Export succeeded')));
    }
    return ListView(
      children: [
        // Container(height: 20),
        // MaterialButton(
        //   onPressed: _exportPkz,
        //   child: const Text('导出PKZ'),
        // ),
        Container(height: 20),
        displayExportPathInfo(),
        Container(height: 20),
        SwitchListTile(
          title: Text(
            l10n.tr('导出后删除原文件', en: 'Delete source files after export'),
          ),
          value: deleteExport,
          onChanged: (value) {
            setState(() {
              deleteExport = value;
            });
          },
        ),
        Container(height: 20),
        MaterialButton(
          onPressed: _exportJpegs,
          child: Text(
            l10n.tr('导出成文件夹', en: 'Export as folders') + proSuffix,
            style: TextStyle(color: !hasProAccess ? Colors.grey : null),
            textAlign: TextAlign.center,
          ),
        ),
        Container(height: 20),
        MaterialButton(
          onPressed: _exportPdf2,
          child: Text(
            l10n.tr('导出成PDF', en: 'Export as PDF') + proSuffix,
            style: TextStyle(color: !hasProAccess ? Colors.grey : null),
            textAlign: TextAlign.center,
          ),
        ),
        Container(height: 20),
        MaterialButton(
          onPressed: _exportEpub,
          child: Text(
            l10n.tr('导出成EPUB', en: 'Export as EPUB') + proSuffix,
            style: TextStyle(color: !hasProAccess ? Colors.grey : null),
            textAlign: TextAlign.center,
          ),
        ),
        Container(height: 20),
      ],
    );
  }

  Future<String?> _pickPath() async {
    try {
      return Platform.isIOS
          ? await methods.iosGetDocumentDir()
          : await chooseFolder(context);
    } catch (e) {
      if (mounted) {
        defaultToast(context, '$e');
      }
      return null;
    }
  }

  Future<void> _runBatchExport({
    required Future<void> Function(String path) exporter,
  }) async {
    if (!mounted) {
      return;
    }
    if (!await ensureProAccess()) {
      if (!mounted) {
        return;
      }
      defaultToast(
        context,
        context.l10n.tr('请先发电鸭', en: 'Please activate Pro first'),
      );
      return;
    }
    final path = await _pickPath();
    if (!mounted) {
      return;
    }
    debugPrient('path $path');
    if (path == null) {
      return;
    }
    try {
      setState(() {
        exporting = true;
      });
      await exporter(path);
      if (!mounted) {
        return;
      }
      setState(() {
        exported = true;
      });
    } catch (err) {
      if (mounted) {
        setState(() {
          e = err;
          exportFail = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          exporting = false;
        });
      }
    }
  }

  Future<void> _exportJpegs() {
    return _runBatchExport(
      exporter: (path) =>
          methods.export_jm_jpegs(widget.idList, path, deleteExport),
    );
  }

  Future<void> _exportPdf2() {
    return _runBatchExport(
      exporter: (path) async {
        for (var id in widget.idList) {
          await methods.export_jm_pdf2(id, path, deleteExport);
        }
      },
    );
  }

  Future<void> _exportEpub() {
    return _runBatchExport(
      exporter: (path) =>
          methods.export_jm_epub(widget.idList, path, deleteExport),
    );
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(
      child: buildScreen(context),
      context: context,
      canPop: !exporting,
    );
  }

  Widget buildScreen(BuildContext context) {
    return WillPopScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            context.l10n.tr(
              '批量导出(即使没有下载完)',
              en: 'Batch export (including unfinished downloads)',
            ),
          ),
        ),
        body: _body(),
      ),
      onWillPop: () async {
        if (exporting) {
          defaultToast(
            context,
            context.l10n.tr('导出中, 请稍后', en: 'Exporting, please wait'),
          );
          return false;
        }
        return true;
      },
    );
  }
}
