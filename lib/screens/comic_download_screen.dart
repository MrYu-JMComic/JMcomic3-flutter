import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/item_builder.dart';

import 'components/comic_info_card.dart';
import 'components/right_click_pop.dart';
import 'comic_download_shared.dart';

class ComicDownloadScreen extends StatefulWidget {
  final AlbumResponse album;

  const ComicDownloadScreen(this.album, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ComicDownloadScreenState();
}

class _ComicDownloadScreenState extends State<ComicDownloadScreen> {
  late Future _innerDownloadFuture;
  // 章节按钮会反复查询下载/选中状态；Set 能避免大量章节时的线性 contains 扫描。
  final Set<int> _taskedEps = {}; // 已经下载的EP
  final Set<int> _selectedEps = {}; // 选中的EP

  Future _init() async {
    var task = await methods.downloadById(widget.album.id);
    if (task != null) {
      _taskedEps.addAll(task.chapters.map((e) => e.id));
    }
  }

  @override
  void initState() {
    _innerDownloadFuture = _init();
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
          "${context.l10n.tr("下载", en: "Download")} - ${widget.album.name}",
        ),
      ),
      body: ListView(
        children: [
          ComicInfoCard(albumToSimple(widget.album), link: true),
          ItemBuilder(
            future: _innerDownloadFuture,
            onRefresh: () async {},
            successBuilder: (
              BuildContext context,
              AsyncSnapshot snapshot,
            ) {
              final series = downloadSeriesForAlbum(widget.album);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildButtons(widget.album, series),
                  Wrap(
                    alignment: WrapAlignment.spaceAround,
                    runSpacing: 10,
                    spacing: 10,
                    children: series.map(_buildSeries).toList(),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(AlbumResponse albumResponse, List<Series> series) {
    var theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
          ),
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.spaceAround,
        children: [
          MaterialButton(
            color: theme.colorScheme.secondary,
            textColor: Colors.white,
            onPressed: () {
              setState(() {
                _selectedEps
                  ..clear()
                  ..addAll(selectableDownloadChapterIds(series, _taskedEps));
              });
            },
            child: Text(context.l10n.tr('全选', en: 'Select all')),
          ),
          MaterialButton(
            color: theme.colorScheme.secondary,
            textColor: Colors.white,
            onPressed: () async {
              final chapters = selectedDownloadChapters(series, _selectedEps);
              if (chapters.isEmpty) {
                return;
              }
              final carte = DownloadCreate(
                album: DownloadCreateAlbum(
                  id: albumResponse.id,
                  name: albumResponse.name,
                  author: albumResponse.author,
                  tags: albumResponse.tags,
                  works: albumResponse.works,
                  description: albumResponse.description,
                ),
                chapters: chapters,
              );
              await methods.createDownload(carte);
              if (!mounted) {
                return;
              }
              Navigator.pop(context);
            },
            child: Text(context.l10n.tr('确定下载', en: 'Download selected')),
          ),
        ],
      ),
    );
  }

  Widget _buildSeries(Series e) {
    final isLight =
        Theme.of(context).colorScheme.brightness == Brightness.light;
    final state = downloadChapterVisualState(_taskedEps, _selectedEps, e.id);
    return Container(
      padding: const EdgeInsets.all(5),
      child: MaterialButton(
        elevation: isLight ? 1 : 0,
        focusElevation: 0,
        onPressed: () {
          _clickOfEp(e.id);
        },
        color: _colorOfEp(state, isLight),
        child: Text.rich(TextSpan(children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _iconOfEp(state, isLight),
          ),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(width: 10),
          ),
          TextSpan(
            text: e.name == "" ? e.sort : "${e.sort} - ${e.name}",
            style: TextStyle(color: _textColorOfEp(state, isLight)),
          ),
        ])),
      ),
    );
  }

  void _clickOfEp(int id) {
    if (_taskedEps.contains(id)) {
      return;
    }
    setState(() {
      toggleSelectedDownloadChapterId(_selectedEps, _taskedEps, id);
    });
  }

  Color _colorOfEp(DownloadChapterVisualState state, bool isLight) {
    switch (state) {
      case DownloadChapterVisualState.tasked:
        return Colors.grey.shade300;
      case DownloadChapterVisualState.selected:
        return Colors.blueGrey.shade300;
      case DownloadChapterVisualState.idle:
        return isLight
            ? Colors.white
            : Theme.of(context).textTheme.bodyMedium!.color!.withOpacity(.17);
    }
  }

  Icon _iconOfEp(DownloadChapterVisualState state, bool isLight) {
    switch (state) {
      case DownloadChapterVisualState.tasked:
        return const Icon(Icons.download_rounded, color: Colors.black);
      case DownloadChapterVisualState.selected:
        return const Icon(Icons.check_box, color: Colors.black);
      case DownloadChapterVisualState.idle:
        return isLight
            ? const Icon(Icons.check_box_outline_blank, color: Colors.black)
            : const Icon(Icons.check_box_outline_blank, color: Colors.white);
    }
  }

  Color _textColorOfEp(DownloadChapterVisualState state, bool isLight) {
    switch (state) {
      case DownloadChapterVisualState.tasked:
        return Colors.black;
      case DownloadChapterVisualState.selected:
        return Colors.black;
      case DownloadChapterVisualState.idle:
        return isLight ? Colors.black : Colors.white;
    }
  }
}
