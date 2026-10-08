import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

class ComicDetailChapters extends StatelessWidget {
  static const _spacing = 8.0;
  static const _horizontalPadding = 14.0;

  final AlbumResponse album;
  final Future<ViewLog?> viewFuture;
  final void Function(int chapterId, int page) onRead;

  const ComicDetailChapters({
    required this.album,
    required this.viewFuture,
    required this.onRead,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: .03)
            : const Color(0xFFF4F5F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: album.series.isEmpty
          ? _singleChapter(context)
          : FutureBuilder<ViewLog?>(
              future: viewFuture,
              builder: (context, snapshot) {
                final log = snapshot.data;
                final lastChapterId = log != null &&
                        log.id == album.id &&
                        log.lastViewChapterId > 0 &&
                        album.series.any(
                          (chapter) => chapter.id == log.lastViewChapterId,
                        )
                    ? log.lastViewChapterId
                    : null;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    return _chapterRows(
                      context,
                      constraints.maxWidth,
                      lastChapterId,
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _chapterRows(
    BuildContext context,
    double availableWidth,
    int? lastChapterId,
  ) {
    final rows = <List<({Series chapter, double width})>>[];
    var row = <({Series chapter, double width})>[];
    var rowWidth = 0.0;
    final titleStyle = _chapterTextStyle(context);
    final historyWidth = _textWidth(
      context,
      context.l10n.tr('上次阅读', en: 'Last read'),
      const TextStyle(
        fontSize: 11,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
    );
    for (final chapter in album.series) {
      final titleWidth =
          _textWidth(context, _chapterTitle(chapter), titleStyle);
      final contentWidth = lastChapterId == chapter.id
          ? math.max(titleWidth, historyWidth)
          : titleWidth;
      final width = math.min(
        availableWidth,
        math.max(
            56.0, (contentWidth + _horizontalPadding * 2 + 2).ceilToDouble()),
      );
      if (row.isNotEmpty && rowWidth + _spacing + width > availableWidth) {
        rows.add(row);
        row = [];
        rowWidth = 0;
      }
      if (row.isNotEmpty) rowWidth += _spacing;
      row.add((chapter: chapter, width: width));
      rowWidth += width;
    }
    if (row.isNotEmpty) rows.add(row);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0) const SizedBox(height: _spacing),
          _filledChapterRow(
              context, rows[index], availableWidth, lastChapterId),
        ],
      ],
    );
  }

  Widget _filledChapterRow(
    BuildContext context,
    List<({Series chapter, double width})> row,
    double availableWidth,
    int? lastChapterId,
  ) {
    final naturalWidth = row.fold(0.0, (width, item) => width + item.width);
    final extraWidth = math.max(
          0.0,
          availableWidth - naturalWidth - _spacing * (row.length - 1),
        ) /
        row.length;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < row.length; index++) ...[
            if (index > 0) const SizedBox(width: _spacing),
            SizedBox(
              width: row[index].width + extraWidth,
              child: _chapterButton(
                context,
                row[index].chapter,
                lastChapterId == row[index].chapter.id,
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  TextStyle _chapterTextStyle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: 13,
        height: 1.45,
        fontWeight: FontWeight.w400,
      );

  String _chapterTitle(Series chapter) {
    final sort = chapter.sort.trim();
    final name = chapter.name.trim();
    if (sort.isEmpty) return name;
    if (name.isEmpty) return sort;
    return '$sort - $name';
  }

  Widget _singleChapter(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        children: [
          Text(
            context.l10n.tr('单章节作品', en: 'Single chapter'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.tr(
              '点击下方开始阅读，或直接打开本章。',
              en: 'Start reading below, or open this chapter.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            key: ValueKey('comic-detail-chapter-${album.id}'),
            style: TextButton.styleFrom(
              foregroundColor: _accent(context),
              minimumSize: const Size(0, 48),
              textStyle: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
            onPressed: () => onRead(album.id, 0),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: Text(
              context.l10n.tr('打开本章', en: 'Open chapter'),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chapterButton(
    BuildContext context,
    Series chapter,
    bool lastRead,
  ) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final color = lastRead
        ? accent.withValues(alpha: dark ? .12 : .07)
        : dark
            ? Colors.white.withValues(alpha: .05)
            : Colors.white;
    return Semantics(
      selected: lastRead,
      child: OutlinedButton(
        key: ValueKey('comic-detail-chapter-${chapter.id}'),
        style: OutlinedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: lastRead ? accent : theme.colorScheme.onSurface,
          minimumSize: const Size(56, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: _horizontalPadding,
            vertical: 12,
          ),
          side: BorderSide(
            color: lastRead
                ? accent.withValues(alpha: .3)
                : theme.colorScheme.onSurface.withValues(alpha: .06),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: _chapterTextStyle(context),
        ),
        onPressed: () => onRead(chapter.id, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(_chapterTitle(chapter), textAlign: TextAlign.center),
            if (lastRead) ...[
              const SizedBox(height: 4),
              Text(
                context.l10n.tr('上次阅读', en: 'Last read'),
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF22D3EE)
          : const Color(0xFF087F9B);
}
