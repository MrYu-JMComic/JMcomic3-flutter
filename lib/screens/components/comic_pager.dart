import 'package:event/event.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/pager_controller_mode.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/comic_info_screen.dart';
import 'package:jmcomic3/screens/components/content_builder.dart';
import 'package:jmcomic3/screens/components/types.dart';

import '../../configs/is_pro.dart';
import 'comic_list.dart';

const _noProMax = 10;
const _pagerDividerColor = Color(0xFFEEEEEE);
const _pagerPageCacheLimit = 6;
final RegExp _digitsOnlyRegExp = RegExp(r'\d+');
const _badStatePrefix = 'Bad state:';

int _calcMaxPage(int total, int pageSize) {
  if (total <= 0 || pageSize <= 0) {
    return 1;
  }
  return (total / pageSize).ceil();
}

String _extractErrorMessage(Object error) {
  var message = error.toString().trim();
  if (message.startsWith(_badStatePrefix)) {
    message = message.substring(_badStatePrefix.length).trim();
  }
  return message;
}

bool _isProRequiredMessage(String message) {
  if (message.isEmpty) {
    return false;
  }
  final lower = message.toLowerCase();
  return message.contains('发电') ||
      message.contains('發電') ||
      lower.contains('发电') ||
      lower.contains('pro is required') ||
      lower.contains('activate pro') ||
      lower.contains('need pro') ||
      lower.contains('vip');
}

class ComicPager extends StatefulWidget {
  final Future<InnerComicPage> Function(int page) onPage;
  final List<ComicLongPressMenuItem>? longPressMenuItems;
  final List<Widget>? appendList;

  const ComicPager(
      {required this.onPage,
      this.longPressMenuItems,
      this.appendList,
      Key? key})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _ComicPagerState();
}

class _ComicPagerState extends State<ComicPager> {
  late PagerControllerMode _mode = currentPagerControllerMode;

  @override
  void initState() {
    super.initState();
    currentPagerControllerModeEvent.subscribe(_onPagerModeChanged);
  }

  @override
  void dispose() {
    currentPagerControllerModeEvent.unsubscribe(_onPagerModeChanged);
    super.dispose();
  }

  void _onPagerModeChanged(_) {
    final latestMode = currentPagerControllerMode;
    if (!mounted || latestMode == _mode) {
      return;
    }
    setState(() {
      _mode = latestMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case PagerControllerMode.stream:
        return _StreamPager(
            onPage: widget.onPage,
            longPressMenuItems: widget.longPressMenuItems,
            appendList: widget.appendList);
      case PagerControllerMode.pager:
        return _PagerPager(
            onPage: widget.onPage,
            longPressMenuItems: widget.longPressMenuItems,
            appendList: widget.appendList);
    }
  }
}

class _StreamPager extends StatefulWidget {
  final Future<InnerComicPage> Function(int page) onPage;
  final List<ComicLongPressMenuItem>? longPressMenuItems;
  final List<Widget>? appendList;

  const _StreamPager(
      {Key? key,
      required this.onPage,
      this.longPressMenuItems,
      this.appendList})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _StreamPagerState();
}

class _StreamPagerState extends State<_StreamPager> {
  int _maxPage = 1;
  int _nextPage = 1;
  int _total = 0;

  bool get _noPro => !hasProAccess && _nextPage > _noProMax;

  bool _joining = false;
  bool _joinSuccess = true;
  bool _joinBlockedByPro = false;
  String _joinErrorMessage = '';

  Future<void> _join() async {
    if (_joining || _nextPage > _maxPage || _noPro || _joinBlockedByPro) {
      return;
    }
    try {
      if (!mounted) {
        return;
      }
      setState(() {
        _joining = true;
      });
      final response = await widget.onPage(_nextPage);
      if (!mounted) {
        return;
      }
      if (_nextPage == 1) {
        if (_redirectAid(response.redirectAid, context)) {
          setState(() {
            _joining = false;
          });
          return;
        }
        _maxPage = _calcMaxPage(response.total, response.list.length);
        _total = response.total;
      }
      _nextPage++;
      _data.addAll(response.list);
      if (!mounted) {
        return;
      }
      setState(() {
        _joinSuccess = true;
        _joinBlockedByPro = false;
        _joinErrorMessage = '';
        _joining = false;
      });
    } catch (e, st) {
      final message = _extractErrorMessage(e);
      final blockedByPro = _isProRequiredMessage(message);
      debugPrient(
        blockedByPro ? message : "$e\n$st",
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _joinSuccess = false;
        _joinBlockedByPro = blockedByPro;
        _joinErrorMessage = message;
        _joining = false;
      });
      if (blockedByPro) {
        defaultToast(
          context,
          context.l10n
              .tr('Please activate Pro first', en: 'Please activate Pro first'),
        );
      }
    }
  }

  final List<ComicSimple> _data = [];
  late ScrollController _controller;
  final TextEditingController _textEditController = TextEditingController();

  _jumpPage() {
    if (_total == 0) {
      return;
    }
    if (!hasProAccess) {
      defaultToast(
        context,
        context.l10n.tr("发电才能跳页哦~", en: "Pro is required to jump pages"),
      );
      return;
    }
    _textEditController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Card(
            child: TextField(
              controller: _textEditController,
              decoration: InputDecoration(
                labelText: context.l10n.tr("请输入页数：", en: "Enter page number:"),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(_digitsOnlyRegExp),
              ],
            ),
          ),
          actions: <Widget>[
            MaterialButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text(context.l10n.tr('取消', en: 'Cancel')),
            ),
            MaterialButton(
              onPressed: () {
                Navigator.pop(context);
                var text = _textEditController.text;
                if (text.isEmpty || text.length > 7) {
                  return;
                }
                var num = int.parse(text);
                if (num == 0 || num > _maxPage) {
                  return;
                }
                _data.clear();
                _nextPage = num;
                _join();
              },
              child: Text(context.l10n.confirm),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    proEvent.subscribe(_onProChanged);
    _controller = ScrollController();
    _controller.addListener(_onScroll);
    _join();
  }

  @override
  void dispose() {
    proEvent.unsubscribe(_onProChanged);
    _textEditController.dispose();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) {
      return;
    }
    if (_joining || _nextPage > _maxPage || _noPro || _joinBlockedByPro) {
      return;
    }
    if (_controller.position.extentAfter < 300) {
      _join();
    }
  }

  Widget? _buildLoadingCard() {
    if (_joinBlockedByPro) {
      final message = _joinErrorMessage.isEmpty
          ? context.l10n
              .tr('Please activate Pro first', en: 'Please activate Pro first')
          : _joinErrorMessage;
      return Card(
        child: InkWell(
          onTap: () {
            setState(() {
              _joinBlockedByPro = false;
              _joinSuccess = true;
            });
            _join();
          },
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: const Icon(Icons.power_off_outlined),
              ),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
              Text(context.l10n.tr('Tap to retry', en: 'Tap to retry')),
            ],
          ),
        ),
      );
    }
    if (_noPro) {
      return Card(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: const Icon(Icons.power_off_outlined),
            ),
            Text(
              context.l10n.tr(
                '$_noProMax页以上需要发电鸭',
                en: 'Pro is required beyond page $_noProMax',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (_joining) {
      return Card(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: const CupertinoActivityIndicator(
                radius: 14,
              ),
            ),
            Text(context.l10n.loading),
          ],
        ),
      );
    }
    if (!_joinSuccess) {
      return Card(
        child: InkWell(
          onTap: () {
            _join();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: const Icon(Icons.sync_problem_rounded),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  context.l10n
                      .tr('Error, tap to retry', en: 'Error, tap to retry'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_joinErrorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Text(
                    _joinErrorMessage,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final loadingCard = _buildLoadingCard();
    return Column(
      children: [
        _buildPagerBar(),
        Expanded(
          child: ComicList(
            controller: _controller,
            data: _data,
            appendList: loadingCard != null
                ? [
                    loadingCard,
                    ...(widget.appendList ?? []),
                  ]
                : widget.appendList,
            longPressMenuItems: widget.longPressMenuItems,
          ),
        ),
      ],
    );
  }

  PreferredSize _buildPagerBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: .5,
              style: BorderStyle.solid,
              color: _pagerDividerColor,
            ),
          ),
        ),
        child: GestureDetector(
          onTap: _jumpPage,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 30,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  context.l10n.tr(
                    "已加载 ${_nextPage - 1} / $_maxPage 页",
                    en: "Loaded ${_nextPage - 1} / $_maxPage pages",
                  ),
                ),
                Text(
                  context.l10n.tr(
                    "已加载 ${_data.length} / $_total 项",
                    en: "Loaded ${_data.length} / $_total items",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onProChanged(EventArgs? args) {
    if (!mounted || _nextPage <= _noProMax) {
      return;
    }
    setState(() {});
  }
}

class _PagerPager extends StatefulWidget {
  final Future<InnerComicPage> Function(int page) onPage;
  final List<ComicLongPressMenuItem>? longPressMenuItems;
  final List<Widget>? appendList;

  const _PagerPager(
      {Key? key,
      required this.onPage,
      this.longPressMenuItems,
      this.appendList})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _PagerPagerState();
}

class _PagerPagerState extends State<_PagerPager> {
  final TextEditingController _textEditController =
      TextEditingController(text: '');
  late int _currentPage = 1;
  late int _maxPage = 1;
  late final List<ComicSimple> _data = [];
  final Map<int, List<ComicSimple>> _pageCache = <int, List<ComicSimple>>{};
  late Future<void> _pageFuture = _load();

  void _cachePageData(int page, List<ComicSimple> list) {
    if (_pageCache.containsKey(page)) {
      _pageCache.remove(page);
    }
    _pageCache[page] = List<ComicSimple>.unmodifiable(list);
    while (_pageCache.length > _pagerPageCacheLimit) {
      _pageCache.remove(_pageCache.keys.first);
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final requestedPage = _currentPage;
    if (forceRefresh) {
      _pageCache.remove(requestedPage);
    }
    final cached = _pageCache[requestedPage];
    if (cached != null) {
      _data
        ..clear()
        ..addAll(cached);
      return;
    }

    final response = await widget.onPage(requestedPage);
    if (!mounted || requestedPage != _currentPage) {
      return;
    }
    if (requestedPage == 1) {
      if (_redirectAid(response.redirectAid, context)) {
        return;
      }
      _maxPage = _calcMaxPage(response.total, response.list.length);
    }
    _cachePageData(requestedPage, response.list);
    _data
      ..clear()
      ..addAll(response.list);
  }

  void _openPage(int page, {bool forceRefresh = false}) {
    if (!hasProAccess && page > _noProMax) {
      defaultToast(
        context,
        context.l10n.tr(
          "$_noProMax页以上需要发电鸭",
          en: "Pro is required beyond page $_noProMax",
        ),
      );
      return;
    }
    if (!forceRefresh && page == _currentPage) {
      return;
    }
    setState(() {
      _currentPage = page;
      _pageFuture = _load(forceRefresh: forceRefresh);
    });
  }

  @override
  void dispose() {
    _textEditController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContentBuilder(
      future: _pageFuture,
      onRefresh: () async {
        _pageCache.clear();
        _openPage(_currentPage, forceRefresh: true);
      },
      successBuilder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
        return Scaffold(
          appBar: _buildPagerBar(),
          body: ComicList(
            appendList: widget.appendList,
            data: _data,
            longPressMenuItems: widget.longPressMenuItems,
          ),
        );
      },
    );
  }

  PreferredSize _buildPagerBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(50),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: .5,
              style: BorderStyle.solid,
              color: _pagerDividerColor,
            ),
          ),
        ),
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () {
                  if (!hasProAccess) {
                    defaultToast(
                      context,
                      context.l10n.tr(
                        "发电才能跳页哦~",
                        en: "Pro is required to jump pages",
                      ),
                    );
                    return;
                  }
                  _textEditController.clear();
                  showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        content: Card(
                          child: TextField(
                            controller: _textEditController,
                            decoration: InputDecoration(
                              labelText: context.l10n.tr(
                                "请输入页数：",
                                en: "Enter page number:",
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.allow(
                                _digitsOnlyRegExp,
                              ),
                            ],
                          ),
                        ),
                        actions: <Widget>[
                          MaterialButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: Text(context.l10n.tr('取消', en: 'Cancel')),
                          ),
                          MaterialButton(
                            onPressed: () {
                              Navigator.pop(context);
                              var text = _textEditController.text;
                              if (text.isEmpty || text.length > 5) {
                                return;
                              }
                              var num = int.parse(text);
                              if (num == 0 || num > _maxPage) {
                                return;
                              }
                              _openPage(num);
                            },
                            child: Text(context.l10n.confirm),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: Row(
                  children: [
                    Text(
                      context.l10n.tr(
                        "第 $_currentPage / $_maxPage 页",
                        en: "Page $_currentPage / $_maxPage",
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  MaterialButton(
                    minWidth: 0,
                    onPressed: () {
                      if (_currentPage > 1) {
                        _openPage(_currentPage - 1);
                      }
                    },
                    child: Text(context.l10n.tr('上一页', en: 'Prev')),
                  ),
                  MaterialButton(
                    minWidth: 0,
                    onPressed: () {
                      if (_currentPage < _maxPage) {
                        if (!hasProAccess && _currentPage + 1 > _noProMax) {
                          defaultToast(
                            context,
                            context.l10n.tr(
                              "$_noProMax页以上需要发电鸭",
                              en: "Pro is required beyond page $_noProMax",
                            ),
                          );
                          return;
                        }
                        _openPage(_currentPage + 1);
                      }
                    },
                    child: Text(context.l10n.tr('下一页', en: 'Next')),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _redirectAid(int? redirectAid, BuildContext context) {
  if (redirectAid != null) {
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (BuildContext context) {
      return ComicInfoScreen(redirectAid, null);
    }));
    return true;
  }
  return false;
}
