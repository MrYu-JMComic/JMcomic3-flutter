import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/content_builder.dart';
import '../basic/commons.dart';
import 'components/comic_download_card.dart';
import 'components/right_click_pop.dart';
import 'downloads_exporting_screen.dart';
import 'downloads_export_shared.dart';

class DownloadsExportScreen extends StatefulWidget {
  const DownloadsExportScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadsExportScreenState();
}

class _DownloadsExportScreenState extends State<DownloadsExportScreen> {
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
        title: Text(context.l10n.tr("批量导出", en: "Batch export")),
        actions: [
          FutureBuilder(
            future: _downloadsFuture,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<List<DownloadAlbum>> snapshot,
                ) {
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
        successBuilder:
            (
              BuildContext context,
              AsyncSnapshot<List<DownloadAlbum>> snapshot,
            ) {
              return ListView(
                children: snapshot.requireData
                    .map(
                      (e) => GestureDetector(
                        onTap: () {
                          toggleSelectedDownloadId(selected, e.id);
                          setState(() {});
                        },
                        child: Stack(
                          children: [
                            ComicDownloadCard(e),
                            Row(
                              children: [
                                Expanded(child: Container()),
                                Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: Icon(
                                    selected.contains(e.id)
                                        ? Icons.check_circle_sharp
                                        : Icons.circle_outlined,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );
            },
      ),
    );
  }

  Set<int> selected = <int>{};

  Future<List<DownloadAlbum>> _loadDownloads() {
    return loadDownloadAlbums((album) => album.isDownloaded);
  }

  Widget _selectAllButton(List<int> exportableIds) {
    return IconButton(
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
      icon: const Icon(Icons.select_all),
    );
  }

  Widget _goToExport() {
    return IconButton(
      onPressed: () async {
        if (selected.isEmpty) {
          defaultToast(
            context,
            context.l10n.tr("请选择导出的内容", en: "Please select content to export"),
          );
          return;
        }
        if (!await androidMangeStorageRequest()) {
          if (!mounted) return;
          throw Exception(context.l10n.tr("申请权限被拒绝", en: "Permission denied"));
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DownloadsExportingScreen(
              idList: selected.toList(growable: false),
            ),
          ),
        );
        if (!mounted) return;
        _downloadsFuture = _loadDownloads();
        final pre = Set<int>.from(selected);
        setState(() {
          selected = <int>{};
        });
        final result = await _downloadsFuture;
        if (!mounted) return;
        selected = restoreSelectedIdSet(pre, result);
        setState(() {});
      },
      icon: const Icon(Icons.check),
    );
  }
}
