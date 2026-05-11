import 'dart:convert';

import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/content_error.dart';

import '../basic/methods.dart';
import 'property_json.dart';

List<int> _categoriesSort = const <int>[];

sortCategories(List<Categories> categories) {
  _sortCategoriesByOrder(categories, _categoriesSort);
}

List<int> getCategoriesSort() {
  return _categoriesSort;
}

const _propertyName = "categoriesSort";

Future initCategoriesSort() async {
  final raw = await methods.loadProperty(_propertyName);
  _categoriesSort = _decodeCategoriesSort(raw);
}

get categoriesSort => _categoriesSort;
var categoriesSortEvent = Event();

Future<dynamic> saveCategoriesSort(List<int> categories) async {
  // 排序配置会被写入本地属性和 WebDAV 快照；保存前统一去重/过滤，避免脏值长期传播。
  final normalized = _normalizeCategoriesSortValues(categories);
  _categoriesSort = List<int>.unmodifiable(normalized);
  await methods.saveProperty(_propertyName, jsonEncode(normalized));
  categoriesSortEvent.broadcast();
}

List<int> _decodeCategoriesSort(String raw) {
  var candidate = raw;
  for (var depth = 0; depth <= 2; depth++) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty || !looksLikeJsonPropertyValue(trimmed)) {
      return const <int>[];
    }
    final decoded = tryDecodeJsonPropertyValue(trimmed);
    if (decoded is Iterable) {
      // 旧版本或手工编辑的排序配置可能包含重复、空值、字符串数字或非法项；
      // 初始化时只保留有效正整数 ID，避免首页分类排序因本地脏数据失败。
      return List<int>.unmodifiable(_normalizeCategoriesSortValues(decoded));
    }
    if (decoded is String && depth < 2) {
      // WebDAV/脚本迁移可能把排序数组再 JSON 编码；最多拆两层字符串包装，
      // 与其他配置项保持一致，同时避免损坏值导致无界递归。
      candidate = decoded;
      continue;
    }
    return const <int>[];
  }
  return const <int>[];
}

List<int> _normalizeCategoriesSortValues(
  Iterable<dynamic> values, {
  Set<int>? allowedIds,
}) {
  final result = <int>[];
  final seen = <int>{};
  for (final item in values) {
    final id = _parsePositiveCategoryId(item);
    if (id == null || !seen.add(id)) {
      continue;
    }
    if (allowedIds != null && !allowedIds.contains(id)) {
      continue;
    }
    result.add(id);
  }
  return result;
}

/// 分类排序面板只应带入当前仍存在的分类 ID。
/// 旧缓存或远端同步过来的排序可能包含已下线分类；进入编辑页时过滤它们，保存后自然收敛。
List<int> restoreCategoriesSortSelection(
  List<int> savedSort,
  Iterable<Categories> categories,
) {
  final liveIds = categories.map((category) => category.id).toSet();
  return _normalizeCategoriesSortValues(savedSort, allowedIds: liveIds);
}

int? _parsePositiveCategoryId(dynamic raw) {
  int? parsed;
  if (raw is int) {
    parsed = raw;
  } else if (raw is num && raw.isFinite && raw == raw.truncateToDouble()) {
    parsed = raw.toInt();
  } else if (raw is String) {
    final trimmed = raw.trim();
    parsed = int.tryParse(trimmed);
    if (parsed == null) {
      final numeric = num.tryParse(trimmed);
      if (numeric != null &&
          numeric.isFinite &&
          numeric == numeric.truncateToDouble()) {
        parsed = numeric.toInt();
      }
    }
  }
  return parsed != null && parsed > 0 ? parsed : null;
}

void _sortCategoriesByOrder(List<Categories> categories, List<int> sort) {
  final originalIndex = <int, int>{};
  for (var index = 0; index < categories.length; index++) {
    originalIndex.putIfAbsent(categories[index].id, () => index);
  }
  final sortIndex = <int, int>{};
  for (var index = 0; index < sort.length; index++) {
    sortIndex.putIfAbsent(sort[index], () => index);
  }

  categories.sort((a, b) {
    final aIndex = sortIndex[a.id];
    final bIndex = sortIndex[b.id];
    if (aIndex == null && bIndex == null) {
      return (originalIndex[a.id] ?? 0).compareTo(originalIndex[b.id] ?? 0);
    }
    if (aIndex == null) {
      return 1;
    }
    if (bIndex == null) {
      return -1;
    }
    return aIndex.compareTo(bIndex);
  });
}

Widget categoriesSortSetting(BuildContext context) {
  return ListTile(
    onTap: () {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (BuildContext context) {
          return const CategoriesSortScreen();
        },
      ));
    },
    title: Text(
      context.l10n.tr("首页分类排序", en: "Homepage category order"),
    ),
  );
}

class CategoriesSortScreen extends StatefulWidget {
  const CategoriesSortScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CategoriesSortScreenState();
}

class _CategoriesSortScreenState extends State<CategoriesSortScreen> {
  Future<CategoriesResponse> _categoriesFuture = methods.categories();
  Key _key = UniqueKey();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        key: _key,
        future: _categoriesFuture,
        builder:
            (BuildContext context, AsyncSnapshot<CategoriesResponse> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              appBar: AppBar(
                title: Text(context.l10n.tr("分类排序", en: "Category order")),
              ),
              body: const Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(
                title: Text(context.l10n.tr("分类排序", en: "Category order")),
              ),
              body: ContentError(
                error: snapshot.error,
                stackTrace: snapshot.stackTrace,
                onRefresh: () async {
                  setState(() {
                    _categoriesFuture = methods.categories();
                    _key = UniqueKey();
                  });
                },
              ),
            );
          }
          var categories = snapshot.requireData.categories;
          return CategoriesSortPanel(categories);
        });
  }
}

class CategoriesSortPanel extends StatefulWidget {
  final List<Categories> categories;

  const CategoriesSortPanel(this.categories, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CategoriesSortPanelState();
}

class _CategoriesSortPanelState extends State<CategoriesSortPanel> {
  late final List<int> _categoriesSort;

  @override
  void initState() {
    super.initState();
    _categoriesSort =
        restoreCategoriesSortSelection(getCategoriesSort(), widget.categories);
  }

  _switch(int value) {
    if (_categoriesSort.contains(value)) {
      _categoriesSort.remove(value);
    } else {
      _categoriesSort.add(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    //
    late double blockSize;
    late double imageSize;
    late double imageRs;
    var size = MediaQuery.of(context).size;
    var min = size.width < size.height ? size.width : size.height;
    blockSize = (min ~/ 3).floorToDouble();
    imageSize = blockSize - 15;
    imageRs = imageSize / 10;
    _sortCategoriesByOrder(widget.categories, getCategoriesSort());
    List<Widget> wrapItems = _wrapItems(blockSize, imageRs, imageSize);
    //
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.tr('分类排序', en: 'Category order')),
        actions: [
          _saveIcon(),
        ],
      ),
      body: ListView(
        children: [
          Container(height: 20),
          Wrap(
            runSpacing: 20,
            alignment: WrapAlignment.spaceAround,
            children: wrapItems,
          ),
          Container(height: 20),
        ],
      ),
    );
  }

  List<Widget> _wrapItems(
    double blockSize,
    double imageRs,
    double imageSize,
  ) {
    List<Widget> list = [];
    final selectedIndexById = <int, int>{};
    for (var index = 0; index < _categoriesSort.length; index++) {
      selectedIndexById.putIfAbsent(_categoriesSort[index], () => index);
    }

    append(
      Widget widget,
      int id,
      String title,
      int? selectedIndex,
      Function() onTap,
    ) {
      final selected = selectedIndex != null;
      list.add(
        GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: blockSize,
            child: Column(
              children: [
                Stack(
                  children: [
                    Card(
                      elevation: .5,
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.all(Radius.circular(imageRs)),
                        child: Container(
                          color: Colors.black,
                          child: widget,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.all(Radius.circular(imageRs)),
                      ),
                    ),
                    if (!selected)
                      Container(
                        width: imageSize,
                        height: imageSize,
                        color: Colors.black.withOpacity(.6),
                        margin: const EdgeInsets.all(4.0),
                      ),
                    if (selected)
                      Container(
                        width: imageSize,
                        height: imageSize,
                        color: Colors.black.withOpacity(.2),
                        margin: const EdgeInsets.all(4.0),
                      ),
                    if (selected)
                      Container(
                        color: Colors.black.withOpacity(.2),
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          "${selectedIndex + 1}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                Container(height: 5),
                Center(
                  child: Text(title),
                ),
              ],
            ),
          ),
        ),
      );
    }

    for (var value in widget.categories) {
      var id = value.id;
      append(
        SizedBox(
          width: imageSize,
          height: imageSize,
          child: Center(
            child: Text(
              value.name.substring(0, 1),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ),
        ),
        value.id,
        value.name,
        selectedIndexById[id],
        () {
          setState(() {
            _switch(id);
          });
        },
      );
    }

    return list;
  }

  Widget _saveIcon() {
    return IconButton(
      onPressed: () async {
        await saveCategoriesSort(_categoriesSort);
        Navigator.of(context).pop();
      },
      icon: const Icon(Icons.save),
    );
  }
}
