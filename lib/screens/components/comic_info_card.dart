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
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleSmall!.copyWith(
      fontWeight: FontWeight.w500,
      height: 1.4,
    );
    final authorStyle = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.primary,
      height: 1.4,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: .18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            clipBehavior: Clip.antiAlias,
            child: JM3x4Cover(
              comicId: comic.id,
              width: 100 * 3 / 4,
              height: 100,
            ),
          ),
          const SizedBox(width: 12),
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
                                      children: const [],
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
                    : [
                        Text(
                          comic.name,
                          style: titleStyle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                const SizedBox(height: 6),
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
                const SizedBox(height: 6),
                _buildCategoryRow(context),
                ..._buildDateMetaRow(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(BuildContext context) {
    if (comic is ComicSimple) {
      final simple = comic as ComicSimple;
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ..._category(context, simple.category),
          ..._category(context, simple.categorySub),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  List<Widget> _buildDateMetaRow(BuildContext context) {
    final published = _formatUnixSeconds(comic.addtime);
    final updated = _formatUnixSeconds(comic.updateAt);
    if (published == null && updated == null) {
      return const [];
    }
    final style = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      height: 1.4,
    );
    return [
      const SizedBox(height: 6),
      Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          if (published != null)
            Text(
              "发布: $published",
              style: style,
            ),
          if (updated != null)
            Text(
              "更新: $updated",
              style: style,
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

  List<Widget> _category(BuildContext context, ComicSimpleCategory category) {
    if (category.title == null) {
      return [];
    }
    final theme = Theme.of(context);
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          category.title!,
          style: theme.textTheme.labelSmall!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ];
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
              Colors.blue.withValues(alpha: 0.3),
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
