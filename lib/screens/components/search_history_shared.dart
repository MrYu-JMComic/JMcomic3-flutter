import 'package:jmcomic3/basic/entities.dart';

const int searchHistoryPanelLimit = 200;

/// 用户输入、历史标签点击和旧缓存恢复都可能带首尾空白；提交前先归一化，
/// 空白查询返回 null，避免搜索页和后端历史记录产生不可点击的空搜索。
String? normalizeSearchPanelQuery(String value) {
  final query = value.trim();
  if (query.isEmpty) {
    return null;
  }
  return query;
}

/// 搜索历史会来自 Rust 分片、WebDAV 快照和旧备份导入；这里统一清理空查询、
/// 合并重复词并保留最新时间，避免搜索面板出现空标签或被重复记录撑大。
List<SearchHistory> normalizeSearchHistoriesForPanel(
  Iterable<SearchHistory> values, {
  int limit = searchHistoryPanelLimit,
}) {
  if (limit <= 0) {
    return const <SearchHistory>[];
  }

  final latestByQuery = <String, SearchHistory>{};
  for (final history in values) {
    final query = normalizeSearchPanelQuery(history.searchQuery);
    if (query == null) {
      continue;
    }
    final current = latestByQuery[query];
    if (current == null || history.lastSearchTime > current.lastSearchTime) {
      latestByQuery[query] = SearchHistory(
        searchQuery: query,
        lastSearchTime: history.lastSearchTime,
      );
    }
  }

  final normalized = latestByQuery.values.toList()
    ..sort((a, b) {
      final byTime = b.lastSearchTime.compareTo(a.lastSearchTime);
      if (byTime != 0) {
        return byTime;
      }
      return a.searchQuery.compareTo(b.searchQuery);
    });
  if (normalized.length <= limit) {
    return List<SearchHistory>.unmodifiable(normalized);
  }
  return List<SearchHistory>.unmodifiable(normalized.take(limit));
}
