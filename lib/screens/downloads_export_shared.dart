import 'package:jmcomic3/basic/methods.dart';

typedef DownloadAlbumFilter = bool Function(DownloadAlbum album);

Future<List<DownloadAlbum>> loadDownloadAlbums(
    DownloadAlbumFilter filter) async {
  final all = await methods.allDownloads();
  return all.where(filter).toList(growable: false);
}

/// 批量导出页会在每个卡片构建时判断选中状态；Set 让包含判断和切换保持 O(1)。
void toggleSelectedDownloadId(Set<int> selected, int id) {
  if (!selected.add(id)) {
    selected.remove(id);
  }
}

/// 刷新下载列表后只保留仍可导出的项目，并沿用旧逻辑保留用户原本的选择顺序。
Set<int> restoreSelectedIdSet(
  Set<int> previousSelected,
  List<DownloadAlbum> latest,
) {
  final latestIds = latest.map((e) => e.id).toSet();
  return previousSelected.where(latestIds.contains).toSet();
}

List<int> restoreSelectedIds(
  List<int> previousSelected,
  List<DownloadAlbum> latest,
) {
  return restoreSelectedIdSet(previousSelected.toSet(), latest)
      .toList(growable: false);
}
