import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/content_builder.dart';
import 'package:jmcomic3/screens/downloads_exporting_screen2.dart';
import '../basic/commons.dart';
import 'components/comic_download_card.dart';
import 'components/right_click_pop.dart';
import 'downloads_export_shared.dart';

class DownloadsExportScreen2 extends StatefulWidget {
  const DownloadsExportScreen2({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadsExportScreen2State();
}

class _DownloadsExportScreen2State extends State<DownloadsExportScreen2> {
  late Future<List<DownloadAlbum>> _downloadsFuture;

  @override
  void initState() {
    _downloadsFuture = _loadDownloads();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.tr("批量导出(即使没有下载完)",
              en: "Batch export (including unfinished downloads)"),
        ),
        actions: [
          FutureBuilder(
            future: _downloadsFuture,
            builder: (BuildContext context,
                AsyncSnapshot<List<DownloadAlbum>> snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Container();
              }
              List<int> exportableIds = [];
              for (var value in snapshot.requireData) {
                exportableIds.add(value.id);
              }
              return _selectAllButton(exportableIds);
            },
          ),
          _goToExport(),
        ],
      ),
      body: ContentBuilder(
        key: null,
        future: _downloadsFuture,
        onRefresh: () async {
          setState(() {
            _downloadsFuture = _loadDownloads();
          });
        },
        successBuilder: (
          BuildContext context,
          AsyncSnapshot<List<DownloadAlbum>> snapshot,
        ) {
          return ListView(
            children: snapshot.requireData
                .map((e) => GestureDetector(
                      onTap: () {
                        toggleSelectedDownloadId(selected, e.id);
                        setState(() {});
                      },
                      child: Stack(children: [
                        ComicDownloadCard(e),
                        Row(children: [
                          Expanded(child: Container()),
                          Padding(
                            padding: const EdgeInsets.all(5),
                            child: Icon(
                              selected.contains(e.id)
                                  ? Icons.check_circle_sharp
                                  : Icons.circle_outlined,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ]),
                      ]),
                    ))
                .toList(),
          );
        },
      ),
    );
  }

  Set<int> selected = <int>{};

  Future<List<DownloadAlbum>> _loadDownloads() {
    return loadDownloadAlbums((album) => !album.isDeleting);
  }

  Widget _selectAllButton(List<int> exportableIds) {
    return MaterialButton(
        minWidth: 0,
        onPressed: () async {
          setState(() {
            if (selected.length >= exportableIds.length) {
              selected.clear();
            } else {
              selected.clear();
              selected.addAll(exportableIds);
            }
          });
        },
        child: Column(
          children: [
            Expanded(child: Container()),
            const Icon(
              Icons.select_all,
              size: 18,
              color: Colors.white,
            ),
            Text(
              context.l10n.tr('全选', en: 'Select all'),
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
            Expanded(child: Container()),
          ],
        ));
  }

  Widget _goToExport() {
    return MaterialButton(
        minWidth: 0,
        onPressed: () async {
          if (selected.isEmpty) {
            defaultToast(context, context.l10n.pleaseSelectExportContent);
            return;
          }
          if (!await androidMangeStorageRequest()) {
            throw Exception(
                context.l10n.tr("申请权限被拒绝", en: "Permission denied"));
          }
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DownloadsExportingScreen2(
                idList: selected.toList(growable: false),
              ),
            ),
          );
          _downloadsFuture = _loadDownloads();
          final pre = Set<int>.from(selected);
          setState(() {
            selected = <int>{};
          });
          final result = await _downloadsFuture;
          selected = restoreSelectedIdSet(pre, result);
          setState(() {});
        },
        child: Column(
          children: [
            Expanded(child: Container()),
            const Icon(
              Icons.check,
              size: 18,
              color: Colors.white,
            ),
            Text(
              context.l10n.confirm,
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
            Expanded(child: Container()),
          ],
        ));
  }
}
