import 'dart:io';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../configs/export_path.dart';
import '../configs/export_rename.dart';
import '../configs/is_pro.dart';
import 'components/content_loading.dart';
import 'components/right_click_pop.dart';

class DownloadsExportingScreen extends StatefulWidget {
  final List<int> idList;

  const DownloadsExportingScreen({Key? key, required this.idList})
    : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadsExportingScreenState();
}

class _DownloadsExportingScreenState extends State<DownloadsExportingScreen> {
  bool exporting = false;
  bool exported = false;
  bool exportFail = false;
  dynamic e;
  String exportMessage = '';
  var deleteExport = false;

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
            l10n.tr('导出后删除下载的漫画', en: 'Delete downloads after export'),
          ),
          value: deleteExport,
          onChanged: (value) {
            setState(() {
              deleteExport = value;
            });
          },
        ),
        Container(height: 20),
        _buildButtonInner(
          _exportJmis,
          l10n.tr('分别导出JMI', en: 'Export JMI separately') + proSuffix,
        ),
        Container(height: 20),
        _buildButtonInner(
          _exportZips,
          l10n.tr('分别导出JM.ZIP', en: 'Export JM.ZIP separately') + proSuffix,
        ),
        Container(height: 20),
        _buildButtonInner(
          _exportJpegZips,
          l10n.tr('分别导出JPEGS.ZIP', en: 'Export JPEGS.ZIP separately') +
              proSuffix,
        ),
        Container(height: 20),
        _buildButtonInner(
          _exportCbzsZips,
          l10n.tr('分别导出CBZ', en: 'Export CBZ separately') + proSuffix,
        ),
        Container(height: 20),
        _buildButtonInner(
          _exportPdf,
          l10n.tr('分别导出PDF', en: 'Export PDF separately') + proSuffix,
        ),
        Container(height: 20),
        _buildButtonInner(
          _exportEpubs,
          l10n.tr('分别导出EPUB', en: 'Export EPUB separately') + proSuffix,
        ),
        Container(height: 20),
      ],
    );
  }

  Widget _buildButtonInner(VoidCallback? onPressed, String text) {
    return MaterialButton(
      onPressed: onPressed,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return Container(
            width: constraints.maxWidth,
            padding: const EdgeInsets.all(15),
            color:
                (Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black)
                    .withOpacity(.05),
            child: Text(text, textAlign: TextAlign.center),
          );
        },
      ),
    );
  }

  Future<void> _runSingleExport({
    required String confirmContent,
    required bool allowRename,
    required Future<void> Function(int id, String path, String? rename)
    exporter,
  }) async {
    if (!mounted) {
      return;
    }
    final l10n = context.l10n;
    if (!await ensureProAccess()) {
      if (!mounted) {
        return;
      }
      defaultToast(context, l10n.tr('请先发电鸭', en: 'Please activate Pro first'));
      return;
    }
    if (Platform.isMacOS) {
      await chooseEx(context);
      if (!mounted) {
        return;
      }
    }
    if (!await confirmDialog(
      context,
      l10n.tr('导出确认', en: 'Export confirmation'),
      confirmContent + showExportPath(context),
    )) {
      return;
    }
    if (!mounted) {
      return;
    }
    try {
      setState(() {
        exporting = true;
      });
      final path = await attachExportPath(context);
      if (!mounted) {
        return;
      }
      for (var value in widget.idList) {
        final ab = await methods.downloadById(value);
        if (!mounted) {
          return;
        }
        final albumName = ab?.album.name ?? '';
        setState(() {
          exportMessage = l10n.tr('正在导出', en: 'Exporting') + ' : $albumName';
        });
        String? rename;
        if (allowRename && currentExportRename()) {
          rename = await displayTextInputDialog(
            context,
            title: l10n.tr('导出重命名', en: 'Export rename'),
            src: albumName,
          );
          if (!mounted) {
            return;
          }
        }
        await exporter(value, path, rename);
        if (!mounted) {
          return;
        }
      }
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

  Future<void> _exportJmis() {
    return _runSingleExport(
      confirmContent: context.l10n.tr(
        '将您所选的漫画分别导出JMI',
        en: 'Export selected comics as JMI',
      ),
      allowRename: true,
      exporter: (id, path, rename) =>
          methods.export_jm_jmi_single(id, path, rename, deleteExport),
    );
  }

  Future<void> _exportPdf() {
    return _runSingleExport(
      confirmContent: context.l10n.tr(
        '将您所选的漫画分别导出PDF',
        en: 'Export selected comics as PDF',
      ),
      allowRename: false,
      exporter: (id, path, _) => methods.export_jm_pdf(id, path, deleteExport),
    );
  }

  Future<void> _exportCbzsZips() {
    return _runSingleExport(
      confirmContent: context.l10n.tr(
        '将您所选的漫画分别导出cbzs.zip',
        en: 'Export selected comics as cbzs.zip',
      ),
      allowRename: true,
      exporter: (id, path, rename) =>
          methods.export_cbzs_zip_single(id, path, rename, deleteExport),
    );
  }

  Future<void> _exportZips() {
    return _runSingleExport(
      confirmContent: context.l10n.tr(
        '将您所选的漫画分别导出ZIP',
        en: 'Export selected comics as ZIP',
      ),
      allowRename: true,
      exporter: (id, path, rename) =>
          methods.export_jm_zip_single(id, path, rename, deleteExport),
    );
  }

  Future<void> _exportJpegZips() {
    return _runSingleExport(
      confirmContent: context.l10n.tr(
        '将您所选的漫画分别导出JPEGS.ZIP',
        en: 'Export selected comics as JPEGS.ZIP',
      ),
      allowRename: true,
      exporter: (id, path, rename) =>
          methods.export_jm_jpegs_zip_single(id, path, rename, deleteExport),
    );
  }

  Future<void> _exportEpubs() {
    return _runSingleExport(
      confirmContent: context.l10n.tr(
        '将您所选的漫画分别导出EPUB',
        en: 'Export selected comics as EPUB',
      ),
      allowRename: true,
      exporter: (id, path, rename) =>
          methods.export_jm_epub_single(id, path, rename, deleteExport),
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
          title: Text(context.l10n.tr('批量导出', en: 'Batch export')),
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
