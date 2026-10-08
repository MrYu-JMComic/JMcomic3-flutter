import 'dart:math';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'components/browser_bottom_sheet.dart';
import 'components/comic_pager.dart';
import 'components/right_click_pop.dart';
import 'components/types.dart';

class ViewLogScreen extends StatefulWidget {
  const ViewLogScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ViewLogScreenState();
}

class _ViewLogScreenState extends State<ViewLogScreen> {
  // random key
  var key = "HISTORY::" + Random().nextInt(100000).toString();

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.viewHistory),
        actions: [
          IconButton(
            onPressed: () async {
              String? choose = await chooseListDialog(
                context,
                values: [l10n.yes, l10n.no],
                title: l10n.clearAllHistory,
              );
              if (l10n.yes == choose) {
                await methods.clearViewLog();
                Navigator.of(context).pushReplacement(MaterialPageRoute(
                  builder: (BuildContext context) {
                    return const ViewLogScreen();
                  },
                ));
              }
            },
            icon: const Icon(Icons.auto_delete),
          ),
          const BrowserBottomSheetAction(),
        ],
      ),
      body: ComicPager(
        key: Key(key),
        probeForMore: true,
        onPage: (int page) async {
          final response = await methods.pageViewLog(page);
          return InnerComicPage(
            total: response.total,
            list: response.content,
          );
        },
        longPressMenuItems: [
          ComicLongPressMenuItem(
            l10n.deleteViewHistory,
            (ComicBasic comic) async {
              defaultToast(context, l10n.deletingComic(comic.name));
              await methods.deleteViewLogByComicId(comic.id);
              setState(() {
                key = "HISTORY::" + Random().nextInt(100000).toString();
              });
            },
          ),
        ],
      ),
    );
  }
}
