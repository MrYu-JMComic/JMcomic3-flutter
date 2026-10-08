import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/basic/navigator.dart';
import 'package:jmcomic3/configs/ignore_view_log.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'comic_download_screen.dart';
import 'comic_reader_screen.dart';
import 'comic_search_screen.dart';
import 'components/comic_comments_list.dart';
import 'components/comic_detail_chapters.dart';
import 'components/comic_detail_header.dart';
import 'components/comic_list.dart';
import 'components/right_click_pop.dart';

ComicBasic? effectiveComicInfoSimple(ComicBasic? simple, int comicId) {
  if (simple == null || simple.name.trim().isEmpty) return null;
  final normalized =
      simple.name.trim().toUpperCase().replaceAll(RegExp(r'[\s#]+'), '');
  // A local ID-only history entry must not hide the album's real metadata.
  if (normalized == comicId.toString() || normalized == 'JM$comicId') {
    return null;
  }
  return simple;
}

({int chapterId, int page, bool continuing}) comicDetailReadingTarget(
    AlbumResponse album, ViewLog? viewLog) {
  final canResume = viewLog != null &&
      viewLog.id == album.id &&
      viewLog.lastViewChapterId > 0 &&
      (album.series.isEmpty
          ? viewLog.lastViewChapterId == album.id
          : album.series
              .any((chapter) => chapter.id == viewLog.lastViewChapterId));
  if (canResume) {
    return (
      chapterId: viewLog.lastViewChapterId,
      page: viewLog.lastViewPage < 0 ? 0 : viewLog.lastViewPage,
      continuing: true,
    );
  }
  return (
    chapterId: album.initialReadableChapterId,
    page: 0,
    continuing: false
  );
}

class ComicInfoScreen extends StatefulWidget {
  final int comicId;
  final ComicBasic? simple;

  const ComicInfoScreen(this.comicId, this.simple, {super.key});

  @override
  State<ComicInfoScreen> createState() => _ComicInfoScreenState();
}

class _ComicInfoScreenState extends State<ComicInfoScreen> with RouteAware {
  static const _contentWidth = 800.0;
  bool _favouriteLoading = false;
  int _tabIndex = 0;
  final Set<int> _visitedTabs = {0};
  ModalRoute<void>? _route;
  late Future<AlbumResponse> _albumFuture = _loadAlbum();
  late Future<ViewLog?> _viewFuture = methods.findViewLog(widget.comicId);

  Future<AlbumResponse> _loadAlbum() => methods.album(
        widget.comicId,
        ignoreViewLog: currentIgnoreVewLog(),
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      routeObserver.unsubscribe(this);
      _route = route;
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(covariant ComicInfoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comicId != widget.comicId) {
      _albumFuture = _loadAlbum();
      _viewFuture = methods.findViewLog(widget.comicId);
      _tabIndex = 0;
      _visitedTabs
        ..clear()
        ..add(0);
    }
  }

  @override
  void didPopNext() {
    setState(() {
      _viewFuture = methods.findViewLog(widget.comicId);
    });
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_favouriteLoading) return;
    final future = _loadAlbum();
    setState(() {
      _albumFuture = future;
      _viewFuture = methods.findViewLog(widget.comicId);
    });
    try {
      await future;
    } catch (_) {
      // The album FutureBuilder owns the retry state.
    }
  }

  void _search(String keyword) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ComicSearchScreen(initKeywords: keyword),
      ));

  void _download(AlbumResponse album) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ComicDownloadScreen(album)),
      );

  void _read(AlbumResponse album, int chapterId, int page) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ComicReaderScreen(
        comic: albumToSimple(album),
        series: album.series,
        chapterId: chapterId,
        initRank: page,
        loadChapter: methods.chapter,
      ),
    ));
  }

  Future<void> _changeFavourite(AlbumResponse album) async {
    if (_favouriteLoading) return;
    if (!await ensureJwtAccess(context,
            feature: context.l10n.tr('收藏', en: 'Favorites')) ||
        !mounted ||
        _favouriteLoading) {
      return;
    }
    setState(() => _favouriteLoading = true);
    try {
      final response = await methods.setFavorite(album.id);
      if (!mounted) return;
      if (const {'0', 'false', 'error', 'fail', 'failed'}
          .contains(response.status.trim().toLowerCase())) {
        throw StateError(response.msg.isEmpty
            ? context.l10n.tr('收藏操作失败', en: 'Could not update favorites')
            : response.msg);
      }
      setState(() {
        album.isFavorite = switch (response.type.toLowerCase()) {
          'add' => true,
          'remove' => false,
          _ => !album.isFavorite,
        };
      });
      defaultToast(
          context,
          album.isFavorite
              ? context.l10n.tr('收藏成功', en: 'Favorited')
              : context.l10n.tr('已取消收藏', en: 'Removed from favorites'));
      if (album.isFavorite && favData.isNotEmpty) {
        final folder = await chooseMapDialog<int>(context,
            title: context.l10n.tr('移动到资料夹', en: 'Move to folder'),
            values: {
              for (final item in favData) item.name: item.fid,
              context.l10n.tr('默认 / 不移动', en: 'Default / Keep'): 0,
            });
        if (!mounted) return;
        if (folder != null && folder != 0) {
          await methods.comicFavoriteFolderMove(album.id, folder);
          if (mounted) {
            defaultToast(
                context, context.l10n.tr('移动成功', en: 'Moved successfully'));
          }
        }
      }
    } catch (error) {
      if (mounted) defaultToast(context, '$error');
    } finally {
      if (mounted) setState(() => _favouriteLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.brightness == Brightness.dark
        ? const Color(0xFF0D0D0F)
        : theme.colorScheme.surface;
    return rightClickPop(
      context: context,
      child: FutureBuilder<AlbumResponse>(
        future: _albumFuture,
        builder: (context, snapshot) {
          final album = snapshot.connectionState == ConnectionState.done &&
                  !snapshot.hasError
              ? snapshot.data
              : null;
          return Scaffold(
            backgroundColor: background,
            appBar: AppBar(
              backgroundColor: background,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: _navButton(
                  Icons.chevron_left,
                  () => Navigator.maybePop(context),
                  context.l10n.tr('返回', en: 'Back')),
              actions: [
                if (album != null) ...[
                  _navButton(
                      Icons.file_download_outlined,
                      () => _download(album),
                      context.l10n.tr('下载', en: 'Download')),
                  _navButton(
                      album.isFavorite ? Icons.bookmark : Icons.bookmark_border,
                      _favouriteLoading ? null : () => _changeFavourite(album),
                      context.l10n.tr('收藏', en: 'Favorites')),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            body: album != null
                ? _body(album)
                : _loadingOrError(snapshot.hasError),
            bottomNavigationBar:
                album != null ? _bottomBar(album, background) : null,
          );
        },
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback? onPressed, String tooltip) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .05),
        ),
        child: Padding(
            padding: const EdgeInsets.all(8), child: Icon(icon, size: 20)),
      ),
    );
  }

  Widget _loadingOrError(bool error) {
    return Center(
      child: error
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_outlined, size: 32),
              const SizedBox(height: 12),
              Text(context.l10n.tr('漫画详情加载失败', en: 'Could not load comic')),
              TextButton.icon(
                key: const ValueKey('comic-detail-retry'),
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.tr('重试', en: 'Retry')),
              ),
            ])
          : const CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Widget _body(AlbumResponse album) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        key: const ValueKey('comic-detail-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentWidth),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ComicDetailHeader(
                    key: ValueKey(album.id),
                    album: album,
                    simple:
                        effectiveComicInfoSimple(widget.simple, widget.comicId),
                    onSearch: _search,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: _tabs(album),
                  ),
                  Divider(
                    key: const ValueKey('comic-detail-directory-divider'),
                    height: 24,
                    thickness: .8,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Offstage(
                            key: const ValueKey('comic-detail-panel-chapters'),
                            offstage: _tabIndex != 0,
                            child: ComicDetailChapters(
                              album: album,
                              viewFuture: _viewFuture,
                              onRead: (chapter, page) =>
                                  _read(album, chapter, page),
                            ),
                          ),
                          if (_visitedTabs.contains(1))
                            Offstage(
                              key:
                                  const ValueKey('comic-detail-panel-comments'),
                              offstage: _tabIndex != 1,
                              child: ComicCommentsList(
                                  mode: 'manhua', aid: album.id),
                            ),
                          if (_visitedTabs.contains(2))
                            Offstage(
                              key: const ValueKey('comic-detail-panel-related'),
                              offstage: _tabIndex != 2,
                              child: album.relatedList.isEmpty
                                  ? _emptyPanel(context.l10n
                                      .tr('暂无推荐', en: 'No recommendations'))
                                  : ComicList(
                                      data: album.relatedList, inScroll: true),
                            ),
                        ]),
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _tabs(AlbumResponse album) {
    final scheme = Theme.of(context).colorScheme;
    final labels = [
      '${context.l10n.tr('章节', en: 'Chapters')} ${album.series.length}',
      '${context.l10n.tr('评论', en: 'Comments')} ${album.commentTotal}',
      '${context.l10n.tr('推荐', en: 'Recommended')} ${album.relatedList.length}',
    ];
    return Material(
      color: scheme.onSurface.withValues(alpha: .05),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, constraints) {
        final widths = labels.map((label) {
          final painter = TextPainter(
            text: TextSpan(
                text: label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontSize: 13)),
            textScaler: MediaQuery.textScalerOf(context),
            textDirection: Directionality.of(context),
          )..layout();
          final width = painter.width + 24;
          painter.dispose();
          return width;
        }).toList();
        final scrollable =
            widths.any((width) => width > constraints.maxWidth / 3);
        Widget tab(int index) => Semantics(
              selected: index == _tabIndex,
              button: true,
              child: InkWell(
                key: ValueKey('comic-detail-tab-$index'),
                onTap: () => setState(() {
                  _tabIndex = index;
                  _visitedTabs.add(index);
                }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
                  child: Column(children: [
                    Text(labels[index],
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: index == _tabIndex
                                ? FontWeight.w500
                                : FontWeight.w400,
                            color: index == _tabIndex
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    const Spacer(),
                    Container(
                        height: 2,
                        width: 32,
                        decoration: BoxDecoration(
                          color: index == _tabIndex
                              ? const Color(0xFF22CDE0)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        )),
                  ]),
                ),
              ),
            );
        final row = IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var index = 0; index < labels.length; index++)
              scrollable
                  ? SizedBox(width: widths[index], child: tab(index))
                  : Expanded(child: tab(index)),
          ]),
        );
        return scrollable
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal, child: row)
            : row;
      }),
    );
  }

  Widget _emptyPanel(String label) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12)),
      );

  Widget _bottomBar(AlbumResponse album, Color background) {
    return Container(
      decoration: BoxDecoration(
          gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [background.withValues(alpha: 0), background, background],
        stops: const [0, .3, 1],
      )),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _contentWidth - 32),
              child: Row(children: [
                _action(
                    'comic-detail-download',
                    Icons.file_download_outlined,
                    context.l10n.tr('下载', en: 'Download'),
                    () => _download(album)),
                const SizedBox(width: 4),
                _action(
                    'comic-detail-favorite',
                    _favouriteLoading
                        ? Icons.sync
                        : album.isFavorite
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                    context.l10n.tr('收藏', en: 'Favorites'),
                    _favouriteLoading ? null : () => _changeFavourite(album)),
                const SizedBox(width: 12),
                Expanded(
                    child: FutureBuilder<ViewLog?>(
                  future: _viewFuture,
                  builder: (context, snapshot) {
                    final ready =
                        snapshot.connectionState == ConnectionState.done;
                    final target =
                        comicDetailReadingTarget(album, snapshot.data);
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: ready
                            ? const LinearGradient(
                                colors: [Color(0xFF19CADE), Color(0xFF347FF5)])
                            : null,
                      ),
                      child: FilledButton(
                        key: const ValueKey('comic-detail-read'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          shape: const StadiumBorder(),
                          textStyle: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                  fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        onPressed: ready
                            ? () => _read(album, target.chapterId, target.page)
                            : null,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                              !ready
                                  ? context.l10n.loading
                                  : target.continuing
                                      ? context.l10n
                                          .tr('继续阅读', en: 'Continue reading')
                                      : context.l10n
                                          .tr('开始阅读', en: 'Start reading'),
                              textAlign: TextAlign.center),
                          if (ready && target.continuing)
                            Text('P${target.page + 1}',
                                style: const TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.w400)),
                        ]),
                      ),
                    );
                  },
                )),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(String key, IconData icon, String label, VoidCallback? onTap) {
    return SizedBox(
      width: 54,
      child: TextButton(
        key: ValueKey(key),
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20),
          const SizedBox(height: 3),
          Text(label,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 10, fontWeight: FontWeight.w400)),
        ]),
      ),
    );
  }
}
