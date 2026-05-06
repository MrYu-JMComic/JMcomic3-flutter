import 'package:jmcomic3/basic/entities.dart';

enum DownloadChapterVisualState {
  tasked,
  selected,
  idle,
}

/// 单本漫画没有 series 时，下载页仍要提供一个可选章节，和旧页面行为保持一致。
List<Series> downloadSeriesForAlbum(AlbumResponse album) {
  if (album.series.isNotEmpty) {
    return album.series;
  }
  return [
    Series(
      id: album.id,
      name: album.name,
      sort: "1",
    ),
  ];
}

/// 下载章节页会在每个按钮渲染、全选和提交时频繁判断章节 ID。
/// 使用 Set 保存已下载/已选 ID，保证大量章节下 contains/toggle 不退化成线性扫描。
Set<int> selectableDownloadChapterIds(
  Iterable<Series> series,
  Set<int> taskedChapterIds,
) {
  final result = <int>{};
  for (final chapter in series) {
    if (!taskedChapterIds.contains(chapter.id)) {
      result.add(chapter.id);
    }
  }
  return result;
}

/// 点击已下载章节必须是空操作；可选章节则在 Set 中切换，保留调用方的插入顺序。
void toggleSelectedDownloadChapterId(
  Set<int> selectedChapterIds,
  Set<int> taskedChapterIds,
  int chapterId,
) {
  if (taskedChapterIds.contains(chapterId)) {
    return;
  }
  if (!selectedChapterIds.remove(chapterId)) {
    selectedChapterIds.add(chapterId);
  }
}

/// 下载章节按钮有三种展示状态：已下载、已选中、未选中。
/// 页面层会在一次构建里复用这个状态，避免同一按钮重复判断多个 Set。
DownloadChapterVisualState downloadChapterVisualState(
  Set<int> taskedChapterIds,
  Set<int> selectedChapterIds,
  int chapterId,
) {
  if (taskedChapterIds.contains(chapterId)) {
    return DownloadChapterVisualState.tasked;
  }
  if (selectedChapterIds.contains(chapterId)) {
    return DownloadChapterVisualState.selected;
  }
  return DownloadChapterVisualState.idle;
}

/// 提交给后端时按页面章节顺序组装，避免用户点击顺序影响下载任务的阅读顺序。
List<DownloadCreateChapter> selectedDownloadChapters(
  Iterable<Series> series,
  Set<int> selectedChapterIds,
) {
  final chapters = <DownloadCreateChapter>[];
  for (final chapter in series) {
    if (selectedChapterIds.contains(chapter.id)) {
      chapters.add(DownloadCreateChapter(
        id: chapter.id,
        name: chapter.name,
        sort: chapter.sort,
      ));
    }
  }
  return chapters;
}
