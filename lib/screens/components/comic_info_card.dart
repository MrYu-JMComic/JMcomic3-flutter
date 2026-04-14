import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/screens/comic_search_screen.dart';

import '../../configs/display_jmcode.dart';
import '../../configs/search_title_words.dart';
import 'images.dart';

class ComicInfoCard extends StatelessWidget {
  final bool link;
  final ComicBasic comic;

  const ComicInfoCard(this.comic, {this.link = false, Key? key})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    const titleStyle = TextStyle(fontWeight: FontWeight.bold);
    final authorStyle = TextStyle(fontSize: 13, color: Colors.pink.shade300);
    return Container(
      padding: const EdgeInsets.only(top: 5, bottom: 5, left: 10, right: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Card(
            shape: coverShape,
            clipBehavior: Clip.antiAlias,
            child: JM3x4Cover(
              comicId: comic.id,
              width: 100 * 3 / 4,
              height: 100,
            ),
          ),
          Container(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...link
                    ? [
                        Text.rich(
                          TextSpan(
                            children: [
                              currentSearchTitleWords()
                                  ? TextSpan(
                                      style: titleStyle,
                                      children: titleProcess(
                                        comic.name,
                                        context,
                                      ),
                                      recognizer: LongPressGestureRecognizer()
                                        ..onLongPress = () {
                                          confirmCopy(context, comic.name);
                                        },
                                    )
                                  : TextSpan(
                                      text: comic.name,
                                      style: titleStyle,
                                      children: [],
                                      recognizer: LongPressGestureRecognizer()
                                        ..onLongPress = () {
                                          confirmCopy(context, comic.name);
                                        },
                                    ),
                              ...currentDisplayJmcode()
                                  ? [
                                      TextSpan(
                                        text: "  (JM${comic.id})",
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.orange.shade700,
                                        ),
                                        recognizer: LongPressGestureRecognizer()
                                          ..onLongPress = () {
                                            confirmCopy(
                                              context,
                                              "JM${comic.id}",
                                            );
                                          },
                                      ),
                                    ]
                                  : [],
                            ],
                          ),
                        ),
                      ]
                    : [Text(comic.name, style: titleStyle)],
                Container(height: 4),
                link
                    ? GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (BuildContext context) {
                                return ComicSearchScreen(
                                  initKeywords: comic.author,
                                );
                              },
                            ),
                          );
                        },
                        onLongPress: () {
                          confirmCopy(context, comic.author);
                        },
                        child: Text(comic.author, style: authorStyle),
                      )
                    : Text(comic.author, style: authorStyle),
                Container(height: 4),
                _buildCategoryRow(),
                ..._buildDateMetaRow(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow() {
    if (comic is ComicSimple) {
      var _comic = comic as ComicSimple;
      return Row(children: [..._c(_comic.category), ..._c(_comic.categorySub)]);
    }
    return Container();
  }

  List<Widget> _buildDateMetaRow(BuildContext context) {
    final published = _formatUnixSeconds(comic.addtime);
    final updated = _formatUnixSeconds(comic.updateAt);
    if (published == null && updated == null) {
      return const [];
    }
    final style = TextStyle(
      fontSize: 12,
      color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(.65),
      height: 1.4,
    );
    return [
      Container(height: 4),
      Row(
        children: [
          if (published != null)
            Expanded(
              child: Text(
                "发布: $published",
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (published != null && updated != null) const SizedBox(width: 10),
          if (updated != null)
            Expanded(
              child: Text(
                "更新: $updated",
                style: style,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    ];
  }

  String? _formatUnixSeconds(int? ts) {
    if (ts == null || ts <= 0) {
      return null;
    }
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      return "${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}";
    } catch (_) {
      return null;
    }
  }

  List<Widget> _c(ComicSimpleCategory category) {
    if (category.title == null) {
      return [];
    }
    return [Text(category.title!), Container(width: 15)];
  }

  List<TextSpan> titleProcess(String name, BuildContext context) {
    RegExp regExp = RegExp(r"\[[^\]]+\]");
    int start = 0;
    List<TextSpan> result = [];
    Iterable<Match> matches = regExp.allMatches(name);
    for (Match match in matches) {
      // =======
      // if (match.start > start) {
      //   result.add(TextSpan(text: name.substring(start, match.start)));
      // }
      // result.add(TextSpan(
      //   text: name.substring(match.start, match.end),
      //   style: const TextStyle(
      //     color: Colors.blue,
      //     decoration: TextDecoration.underline,
      //   ),
      //   recognizer: TapGestureRecognizer()
      //     ..onTap = () {
      //       Navigator.of(context).push(MaterialPageRoute(
      //         builder: (BuildContext context) {
      //           return ComicSearchScreen(
      //             initKeywords: name.substring(match.start + 1, match.end - 1),
      //           );
      //         },
      //       ));
      //     },
      // ));
      // start = match.end;
      // =======
      if (match.start > start) {
        result.add(TextSpan(text: name.substring(start, match.start + 1)));
      }
      result.add(
        TextSpan(
          text: name.substring(match.start + 1, match.end - 1),
          style: TextStyle(
            // 30%蓝色 叠加本该有的颜色
            color: Color.alphaBlend(
              Colors.blue.withOpacity(0.3),
              Theme.of(context).textTheme.bodyMedium!.color!,
            ),
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (BuildContext context) {
                    return ComicSearchScreen(
                      initKeywords: name.substring(
                        match.start + 1,
                        match.end - 1,
                      ),
                    );
                  },
                ),
              );
            },
        ),
      );
      if (match.start > start) {
        result.add(TextSpan(text: name.substring(match.end - 1, match.end)));
      }
      start = match.end;
    }
    if (start < name.length) {
      result.add(TextSpan(text: name.substring(start)));
    }
    return result;
  }
}
