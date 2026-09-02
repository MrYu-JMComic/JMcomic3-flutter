import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/comic_pager.dart';

import 'components/right_click_pop.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  int _folderId = 0;
  bool _isLoading = true;

  final Map<int, String> _folderMap = {0: ""};

  _chooseFolder() async {
    _folderMap[0] = context.l10n.all;
    int? f = await chooseMapDialog(
      context,
      values: _folderMap.map((key, value) => MapEntry(value, key)),
      title: context.l10n.chooseFolder,
    );
    if (f != null) {
      if (!mounted) return;
      setState(() {
        _folderId = f;
      });
    }
  }

  String _sort = "mr";

  Map<String, String> _sortNameMap(BuildContext context) {
    return {
      "mr": context.l10n.sortByFavoriteTime,
      "mp": context.l10n.sortByUpdateTime,
    };
  }

  _chooseSort() async {
    final nameMap = _sortNameMap(context);
    String? f = await chooseMapDialog(
      context,
      values: nameMap.map((key, value) => MapEntry(value, key)),
      title: context.l10n.chooseSort,
    );
    if (f != null) {
      if (!mounted) return;
      setState(() {
        _sort = f;
      });
      await methods.saveProperty("favorites_sort", f);
    }
  }

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () async {
      if (!await ensureJwtAccess(
            context,
            feature: context.l10n.featureFavoritesFolder,
          ) &&
          mounted) {
        Navigator.of(context).pop();
      }
    });
    for (var value in favData) {
      try {
        _folderMap[value.fid] = value.name;
      } catch (e) {
        debugPrient(e);
        defaultToast(context, "$e");
      }
    }
    _loadSort();
  }

  Future<void> _loadSort() async {
    try {
      final sort = await methods.loadProperty("favorites_sort");
      if (!mounted) return;
      if (sort.isNotEmpty && _sortNameMap(context).containsKey(sort)) {
        setState(() {
          _sort = sort;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      // 使用默认值
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    _folderMap[0] = context.l10n.all;
    final sortNameMap = _sortNameMap(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.favorites),
        actions: [
          MaterialButton(
            onPressed: _chooseSort,
            child: Row(
              children: [
                const Icon(Icons.sort, size: 15),
                Container(width: 8),
                Text(sortNameMap[_sort] ?? ""),
              ],
            ),
          ),
          MaterialButton(
            onPressed: _chooseFolder,
            child: Row(
              children: [
                const Icon(Icons.folder_copy_outlined, size: 15),
                Container(width: 8),
                Text(_folderMap[_folderId] ?? context.l10n.all),
              ],
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ComicPager(
              key: Key("FAVOUR:$_folderId:$_sort"),
              onPage: (int page) async {
                final response = await methods.favorites(
                  _folderId,
                  page,
                  _sort,
                );
                setState(() {
                  favData = response.folderList;
                });
                return InnerComicPage(
                  total: response.total,
                  list: response.list,
                );
              },
            ),
    );
  }
}
