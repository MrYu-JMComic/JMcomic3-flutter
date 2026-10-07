import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/comic_pager.dart';
import 'package:jmcomic3/screens/components/content_builder.dart';
import 'package:jmcomic3/screens/components/floating_search_bar.dart';

import '../configs/categories_sort.dart';
import '../configs/login.dart';
import 'components/browser_bottom_sheet.dart';
import 'components/comic_floating_search_bar.dart';
import 'components/content_error.dart';
import 'components/content_loading.dart';
import 'week_screen.dart';

class BrowserScreenWrapper extends StatefulWidget {
  final FloatingSearchBarController searchBarController;

  const BrowserScreenWrapper({Key? key, required this.searchBarController})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _BrowserScreenWrapperState();
}

class _BrowserScreenWrapperState extends State<BrowserScreenWrapper> {
  @override
  void initState() {
    loginEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    loginEvent.unsubscribe(_setState);
    super.dispose();
  }

  void _setState(_) {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    switch (loginStatus) {
      case LoginStatus.loginSuccess:
      case LoginStatus.guest:
        return BrowserScreen(searchBarController: widget.searchBarController);
      case LoginStatus.loginField:
        return ContentError(
          error: context.l10n.pleaseLogin,
          stackTrace: StackTrace.current,
          onRefresh: () async {},
        );
      case LoginStatus.logging:
        return ContentLoading(
          label: context.l10n.loggingIn,
        );
      case LoginStatus.notSet:
        return ContentError(
          error: context.l10n.pleaseLogin,
          stackTrace: StackTrace.current,
          onRefresh: () async {},
        );
    }
  }
}

class BrowserScreen extends StatefulWidget {
  final FloatingSearchBarController searchBarController;

  const BrowserScreen({Key? key, required this.searchBarController})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late Future<CategoriesResponse> _future;
  late Key _key;
  String _slug = "";
  SortBy _sortBy = sortByDefault;

  Future<CategoriesResponse> _categories() async {
    final rsp = await methods.categories();
    blockStore = rsp.blocks;
    sortCategories(rsp.categories);
    return rsp;
  }

  @override
  void initState() {
    _future = _categories();
    _key = UniqueKey();
    super.initState();
    categoriesSortEvent.subscribe(_resort);
  }

  @override
  void dispose() {
    categoriesSortEvent.unsubscribe(_resort);
    super.dispose();
  }

  _resort(_) {
    setState(() {
      _future = _categories();
      _key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.browse),
        actions: [
          IconButton(
            tooltip: l10n.weekMustSee,
            onPressed: () async {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const WeekScreen()));
            },
            icon: const Icon(Icons.calendar_month),
          ),
          const BrowserBottomSheetAction(),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: _buildSearchEntry(context),
                ),
                Expanded(
                    child: ContentBuilder(
                  key: _key,
                  future: _future,
                  onRefresh: () async {
                    setState(() {
                      _future = _categories();
                      _key = UniqueKey();
                    });
                  },
                  successBuilder: (
                    BuildContext context,
                    AsyncSnapshot<CategoriesResponse> snapshot,
                  ) {
                    final categories = snapshot.requireData.categories;
                    if (categories.isEmpty) {
                      _slug = "";
                      return Center(
                        child: Text(
                          l10n.tr("暂无可用分类", en: "No categories available"),
                        ),
                      );
                    }
                    final slugExists =
                        categories.any((element) => element.slug == _slug);
                    if (_slug.isEmpty || !slugExists) {
                      _slug = categories.first.slug;
                    }
                    return Column(children: [
                      _buildCategoryFilters(context, categories),
                      Expanded(
                        child: ComicPager(
                          key: Key("$_slug:$_sortBy"),
                          onPage: (int page) async {
                            final response =
                                await methods.comics(_slug, _sortBy, page);
                            return InnerComicPage(
                              total: response.total,
                              list: response.content,
                            );
                          },
                        ),
                      ),
                    ]);
                  },
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchEntry(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          searchHistories = await methods.lastSearchHistories(20);
          if (!mounted) return;
          widget.searchBarController.display(modifyInput: '');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.tr('搜索漫画、作者或关键词',
                      en: 'Search comics, authors or keywords'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilters(
      BuildContext context, List<Categories> categories) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final category in categories)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(category.name),
                        selected: category.slug == _slug,
                        showCheckmark: false,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _slug = category.slug);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 12),
            child: IconButton.filledTonal(
              tooltip:
                  '${context.l10n.chooseSort}: ${sortByName(context, _sortBy)}',
              onPressed: () async {
                final value = await chooseSortBy(context);
                if (!mounted || value == null) return;
                setState(() => _sortBy = value);
              },
              icon: const Icon(Icons.sort_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
