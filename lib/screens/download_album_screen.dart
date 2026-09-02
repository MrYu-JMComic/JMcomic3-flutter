import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/basic/reader_pages.dart';
import 'package:jmcomic3/configs/reader_feature_flags.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/comic_download_card.dart';
import 'package:jmcomic3/screens/components/item_builder.dart';
import 'package:jmcomic3/screens/components/my_flat_button.dart';

import 'comic_info_screen.dart';
import 'comic_reader_screen.dart';
import 'comic_search_screen.dart';
import 'components/right_click_pop.dart';

class DownloadAlbumScreen extends StatefulWidget {
  final DownloadAlbum album;

  const DownloadAlbumScreen(this.album, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadAlbumScreenState();
}

class _DownloadAlbumScreenState extends State<DownloadAlbumScreen> {
  static const _autoRefreshInterval = Duration(seconds: 2);

  late DownloadAlbum _album;
  late Future<DownloadCreate?> _future;
  late Future<ViewLog?> _viewFuture;
  Timer? _autoRefreshTimer;
  bool _loadingAlbum = false;
  bool _taskRemoved = false;

  @override
  void initState() {
    super.initState();
    _album = widget.album;
    _future = methods.downloadById(_album.id);
    _viewFuture = methods.findViewLog(_album.id);
    _syncAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAlbum() async {
    if (_loadingAlbum) {
      _syncAutoRefresh();
      return;
    }
    _loadingAlbum = true;
    try {
      final album = await methods.downloadAlbumById(_album.id);
      if (!mounted) {
        return;
      }
      if (album == null) {
        _taskRemoved = true;
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        _album = album;
      });
    } catch (_e) {
      // 下载状态刷新失败不打断详情页阅读入口
    } finally {
      _loadingAlbum = false;
      if (mounted && !_taskRemoved) {
        _syncAutoRefresh();
      }
    }
  }

  void _syncAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    if (_taskRemoved || !_album.shouldAutoRefreshStatus) {
      return;
    }
    _autoRefreshTimer = Timer(_autoRefreshInterval, () {
      _refreshAlbum();
    });
  }

  void _reloadViewLog() {
    if (!mounted) {
      return;
    }
    setState(() {
      _viewFuture = methods.findViewLog(_album.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_album.name),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (BuildContext context) {
                    return ComicInfoScreen(_album.id, null);
                  },
                ),
              );
            },
            icon: const Icon(Icons.settings_ethernet_outlined),
          ),
        ],
      ),
      body: ListView(
        children: [
          ComicDownloadCard(_album),
          _buildTags(_album.tagList),
          ..._album.description == ""
              ? []
              : [
                  const Divider(),
                  Container(
                    padding: const EdgeInsets.all(10),
                    child: SelectableText(_album.description),
                  ),
                ],
          ItemBuilder(
            future: _future,
            onRefresh: () async {
              setState(() {
                _future = methods.downloadById(_album.id);
              });
            },
            successBuilder:
                (
                  BuildContext context,
                  AsyncSnapshot<DownloadCreate?> snapshot,
                ) {
                  var data = snapshot.data;
                  if (data == null) {
                    return MyFlatButton(
                      title: context.l10n.tr(
                        "下载任务不存在",
                        en: "Download task not found",
                      ),
                      onPressed: () {
                        setState(() {
                          _future = methods.downloadById(_album.id);
                        });
                        _refreshAlbum();
                      },
                    );
                  }
                  return Column(
                    children: [_buildContinueButton(data), _buildSeries(data)],
                  );
                },
          ),
        ],
      ),
    );
  }

  Widget _buildTags(List<String> tags) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Container(
          width: constraints.maxWidth,
          padding: const EdgeInsets.all(10),
          child: Wrap(
            children: tags.map((e) {
              return InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (BuildContext context) {
                        return ComicSearchScreen(initKeywords: e);
                      },
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.only(
                    left: 10,
                    right: 10,
                    top: 3,
                    bottom: 3,
                  ),
                  margin: const EdgeInsets.only(
                    left: 5,
                    right: 5,
                    top: 3,
                    bottom: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.pink.shade100,
                    border: Border.all(
                      style: BorderStyle.solid,
                      color: Colors.pink.shade400,
                    ),
                    borderRadius: const BorderRadius.all(Radius.circular(30)),
                  ),
                  child: Text(
                    e,
                    style: TextStyle(color: Colors.pink.shade500, height: 1.4),
                    strutStyle: const StrutStyle(height: 1.4),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildContinueButton(DownloadCreate create) {
    if (!create.hasChapters) {
      return const SizedBox.shrink();
    }
    return FutureBuilder(
      future: _viewFuture,
      builder: (BuildContext context, AsyncSnapshot<ViewLog?> snapshot) {
        if (snapshot.hasError) {
          return MyFlatButton(
            title: context.l10n.tr("出错了, 点击重试", en: "Error, tap to retry"),
            onPressed: _reloadViewLog,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return MyFlatButton(title: context.l10n.loading, onPressed: null);
        }
        var log = snapshot.data;
        if (log != null && create.containsChapterId(log.lastViewChapterId)) {
          return MyFlatButton(
            title: context.l10n.tr("继续阅读", en: "Continue reading"),
            onPressed: () {
              _push(create, log.lastViewChapterId, log.lastViewPage);
            },
          );
        }
        return MyFlatButton(
          title: context.l10n.tr("从头开始", en: "Start from beginning"),
          onPressed: () {
            _push(create, create.initialChapterId, 0);
          },
        );
      },
    );
  }

  Widget _buildSeries(DownloadCreate create) {
    if (create.chapters.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.l10n.tr(
            "暂无可阅读章节，下载任务可能尚未同步完成",
            en: "No readable chapters are available yet.",
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    var list = Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.spaceAround,
      children: create.chapters.map((e) {
        return MaterialButton(
          onPressed: () {
            _push(create, e.id, 0);
          },
          color: Colors.white,
          child: Text(
            e.sort + (e.name == "" ? "" : (" - ${e.name}")),
            style: const TextStyle(color: Colors.black),
          ),
        );
      }).toList(),
    );
    return Container(padding: const EdgeInsets.all(10), child: list);
  }

  void _push(DownloadCreate create, int seriesId, int initRank) {
    if (!create.hasChapters || !create.containsChapterId(seriesId)) {
      // Never use an album id as a chapter id when an imported task has no
      // chapters or a stale view-log points outside this task.
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ComicReaderScreen(
          comic: ComicBasic(
            id: create.album.id,
            author: create.album.author.join(" / "),
            description: create.album.description,
            name: create.album.name,
            image: "",
          ),
          series: create.readerSeries,
          chapterId: seriesId,
          initRank: initRank,
          loadChapter: (int seriesId) {
            return _loadChapter(create, seriesId);
          },
        ),
      ),
    );
  }

  Future<ChapterResponse> _loadChapter(
    DownloadCreate create,
    int seriesId,
  ) async {
    if (!create.containsChapterId(seriesId)) {
      throw StateError('download chapter is unavailable');
    }
    final images = ReaderPageRepository.orderOfflineImages(
      await methods.dlImageByChapterId(seriesId, albumId: create.album.id),
    );
    final chapter = create.chapterById(seriesId);
    if (chapter == null) {
      throw StateError('download chapter metadata is missing');
    }
    var resolvedImages = images;
    if (readerOfflineOwnerV1) {
      // Availability is an explicit backend contract.  An empty/error
      // response is treated as metadata-only; no path is guessed from the
      // persisted image name or dl_status.
      final available = await methods.dlImageLocalAvailability(
        seriesId,
        albumId: create.album.id,
      );
      if (available.isNotEmpty) {
        resolvedImages = ReaderPageRepository.mergeLocalAvailability(
          images,
          available
              .where(
                (item) =>
                    item.chapterId == seriesId &&
                    item.albumId == create.album.id,
              )
              .toList(),
        );
      }
    }
    return ChapterResponse(
      id: seriesId,
      series: create.readerSeries,
      tags: create.album.tags.join(" / "),
      name: chapter.name,
      images: resolvedImages.map((e) => e.name).toList(growable: false),
      seriesId: create.album.id,
      isFavorite: false,
      liked: false,
      offlineImages: resolvedImages,
    );
  }
}
