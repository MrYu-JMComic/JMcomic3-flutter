import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/configs/display_jmcode.dart';
import 'package:jmcomic3/configs/search_title_words.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'images.dart';

class ComicDetailHeader extends StatefulWidget {
  final AlbumResponse album;
  final ComicBasic? simple;
  final ValueChanged<String> onSearch;

  const ComicDetailHeader({
    super.key,
    required this.album,
    this.simple,
    required this.onSearch,
  });

  @override
  State<ComicDetailHeader> createState() => _ComicDetailHeaderState();
}

class _ComicDetailHeaderState extends State<ComicDetailHeader> {
  bool _tagsExpanded = false;

  @override
  void didUpdateWidget(covariant ComicDetailHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.id != widget.album.id) {
      _tagsExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final panel = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: .05)
        : scheme.onSurface.withValues(alpha: .045);
    final tags = _uniqueValues(album.tags);
    final authors = _uniqueValues(album.author);
    final works = _uniqueValues(album.works);
    final categories = _categories();
    final title = album.name.trim().isNotEmpty
        ? album.name
        : widget.simple?.name ?? 'JM${album.id}';
    final description = album.description.trim();
    final dark = theme.brightness == Brightness.dark;
    final authorColor =
        dark ? const Color(0xFFC4B5FD) : const Color(0xFF6D48AD);
    final workColor = dark ? const Color(0xFFF4CE83) : const Color(0xFF97651C);
    final updated = _formatTimestamp(album.updateAt ?? widget.simple?.updateAt);
    final published = _formatTimestamp(album.addtime ?? widget.simple?.addtime);
    final displayJmcode = currentDisplayJmcode();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth <= 360 ||
            MediaQuery.textScalerOf(context).scale(16) > 20;
        final coverWidth = compact ? 104.0 : 120.0;
        final metaStyle = TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: JM3x4Cover(
                      key: const Key('comic-detail-cover'),
                      comicId: album.id,
                      width: coverWidth,
                      height: coverWidth * 4 / 3,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (categories.isNotEmpty) ...[
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (var index = 0;
                                    index < categories.length;
                                    index++)
                                  _DetailChip(
                                    label: categories[index],
                                    background: index == 0
                                        ? const Color(0xFFD63D88)
                                        : panel,
                                    foreground: index == 0
                                        ? Colors.white
                                        : scheme.onSurfaceVariant,
                                    rounded: true,
                                    onTap: () =>
                                        widget.onSearch(categories[index]),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          _ExpandableDetailText(
                            textKey: const Key('comic-detail-title'),
                            text: title,
                            maxLines: 2,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                              color: scheme.onSurface,
                            ),
                            expandKey: const Key('comic-detail-title-expand'),
                            searchTitleWords: currentSearchTitleWords(),
                            onSearch: widget.onSearch,
                            onLongPress: () => confirmCopy(context, title),
                          ),
                          if (published != null ||
                              updated != null ||
                              displayJmcode) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 4,
                              children: [
                                if (published != null)
                                  _DetailMeta(
                                    icon: Icons.event_outlined,
                                    text:
                                        '${context.l10n.tr('发布', en: 'Published')} $published',
                                    style: metaStyle,
                                  ),
                                if (updated != null)
                                  _DetailMeta(
                                    icon: Icons.schedule_outlined,
                                    text:
                                        '${context.l10n.tr('更新', en: 'Updated')} $updated',
                                    style: metaStyle,
                                  ),
                                if (displayJmcode)
                                  GestureDetector(
                                    onLongPress: () =>
                                        confirmCopy(context, 'JM${album.id}'),
                                    child: _DetailMeta(
                                      icon: Icons.description_outlined,
                                      text: 'JM${album.id}',
                                      style: metaStyle,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (authors.isNotEmpty || works.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final author in authors)
                      _DetailChip(
                        label:
                            '${context.l10n.tr('作者', en: 'Author')}: $author',
                        background:
                            authorColor.withValues(alpha: dark ? .14 : .09),
                        foreground: authorColor,
                        borderColor: authorColor.withValues(alpha: .20),
                        onTap: () => widget.onSearch(author),
                        onLongPress: () => confirmCopy(context, author),
                      ),
                    for (final work in works)
                      _DetailChip(
                        label: '${context.l10n.tr('作品', en: 'Work')}: $work',
                        background:
                            workColor.withValues(alpha: dark ? .14 : .09),
                        foreground: workColor,
                        borderColor: workColor.withValues(alpha: .20),
                        onTap: () => widget.onSearch(work),
                        onLongPress: () => confirmCopy(context, work),
                      ),
                  ],
                ),
              ],
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '${context.l10n.tr('标签', en: 'Tags')} ${tags.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in _tagsExpanded ? tags : tags.take(7))
                      _DetailChip(
                        label: tag,
                        background: _tagColor(tag, dark)
                            .withValues(alpha: dark ? .15 : .10),
                        foreground: _tagColor(tag, dark),
                        borderColor: _tagColor(tag, dark)
                            .withValues(alpha: dark ? .25 : .20),
                        onTap: () => widget.onSearch(tag),
                        onLongPress: () => confirmCopy(context, tag),
                      ),
                  ],
                ),
                if (tags.length > 7)
                  _DetailExpandButton(
                    key: const Key('comic-detail-tags-expand'),
                    expanded: _tagsExpanded,
                    text: _tagsExpanded
                        ? context.l10n.tr('收起标签', en: 'Collapse tags')
                        : context.l10n.tr(
                            '展开全部 ${tags.length - 7} 个标签',
                            en: 'Show ${tags.length - 7} more tags',
                          ),
                    onPressed: () =>
                        setState(() => _tagsExpanded = !_tagsExpanded),
                  ),
              ],
              if (description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.tr('简介', en: 'Description'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _ExpandableDetailText(
                        textKey: const Key('comic-detail-description'),
                        text: description,
                        maxLines: 3,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 1.6,
                          color: scheme.onSurfaceVariant,
                        ),
                        expandKey: const Key('comic-detail-description-expand'),
                        onLongPress: () => confirmCopy(context, description),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<String> _categories() {
    final simple = widget.simple;
    if (simple is! ComicSimple) return const [];
    return _uniqueValues([
      simple.category.title ?? '',
      simple.categorySub.title ?? '',
    ]);
  }

  static List<String> _uniqueValues(Iterable<String> values) => values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  // Keep a tag's color consistent when tags are expanded or reordered.
  static Color _tagColor(String tag, bool dark) {
    const light = [
      Color(0xFF087F9B),
      Color(0xFF7353B5),
      Color(0xFFA13773),
      Color(0xFF28765E)
    ];
    const night = [
      Color(0xFF7BDBEE),
      Color(0xFFC5AEF4),
      Color(0xFFF0A5C9),
      Color(0xFF88D8B5)
    ];
    var hash = 0;
    for (final rune in tag.runes) {
      hash = (hash * 31 + rune) % light.length;
    }
    return (dark ? night : light)[hash];
  }

  static String? _formatTimestamp(int? timestamp) {
    if (timestamp == null || timestamp <= 0) return null;
    try {
      final date =
          DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      return '${date.year}-${two(date.month)}-${two(date.day)}';
    } on ArgumentError {
      return null;
    }
  }
}

class _DetailChip extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool rounded;
  final Color? borderColor;

  const _DetailChip({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.onLongPress,
    this.rounded = false,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(rounded ? 30 : 6);
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor!),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: radius,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: rounded ? 8 : 10,
            vertical: rounded ? 3 : 5,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: rounded ? FontWeight.w500 : FontWeight.w400,
              height: 1.4,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailMeta extends StatelessWidget {
  final IconData icon;
  final String text;
  final TextStyle style;

  const _DetailMeta({
    required this.icon,
    required this.text,
    required this.style,
  });

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(icon, size: 12, color: style.color),
              ),
            ),
            TextSpan(text: text),
          ],
        ),
        style: style,
      );
}

class _ExpandableDetailText extends StatefulWidget {
  final Key textKey;
  final String text;
  final int maxLines;
  final TextStyle style;
  final Key expandKey;
  final bool searchTitleWords;
  final ValueChanged<String>? onSearch;
  final VoidCallback? onLongPress;

  const _ExpandableDetailText({
    required this.textKey,
    required this.text,
    required this.maxLines,
    required this.style,
    required this.expandKey,
    this.searchTitleWords = false,
    this.onSearch,
    this.onLongPress,
  });

  @override
  State<_ExpandableDetailText> createState() => _ExpandableDetailTextState();
}

class _ExpandableDetailTextState extends State<_ExpandableDetailText> {
  bool _expanded = false;
  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan> _spans = const [];

  @override
  void initState() {
    super.initState();
    _updateSpans();
  }

  @override
  void didUpdateWidget(covariant _ExpandableDetailText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _expanded = false;
    if (oldWidget.text != widget.text ||
        oldWidget.searchTitleWords != widget.searchTitleWords ||
        oldWidget.onSearch != widget.onSearch ||
        oldWidget.style != widget.style) {
      _updateSpans();
    }
  }

  void _updateSpans() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    if (!widget.searchTitleWords || widget.onSearch == null) {
      _spans = [TextSpan(text: widget.text)];
      return;
    }
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in RegExp(r'\[([^\]]+)\]').allMatches(widget.text)) {
      spans.add(TextSpan(text: widget.text.substring(start, match.start + 1)));
      final keyword = match.group(1)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onSearch?.call(keyword);
      _recognizers.add(recognizer);
      spans.add(TextSpan(text: keyword, recognizer: recognizer));
      spans.add(const TextSpan(text: ']'));
      start = match.end;
    }
    spans.add(TextSpan(text: widget.text.substring(start)));
    _spans = spans;
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coloredSpans = _spans.map((span) {
      if (span is TextSpan && span.recognizer != null) {
        return TextSpan(
          text: span.text,
          recognizer: span.recognizer,
          style: TextStyle(
            color: Color.alphaBlend(
              theme.colorScheme.primary.withValues(alpha: .35),
              widget.style.color ?? theme.colorScheme.onSurface,
            ),
          ),
        );
      }
      return span;
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final span = TextSpan(
          style: DefaultTextStyle.of(context).style.merge(widget.style),
          children: coloredSpans,
        );
        final painter = TextPainter(
          text: span,
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: widget.onLongPress,
              child: Text.rich(
                TextSpan(children: coloredSpans),
                key: widget.textKey,
                style: widget.style,
                maxLines: _expanded ? null : widget.maxLines,
                overflow:
                    _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
            ),
            if (overflows)
              _DetailExpandButton(
                key: widget.expandKey,
                expanded: _expanded,
                text: _expanded
                    ? context.l10n.tr('收起', en: 'Collapse')
                    : context.l10n.tr('展开全文', en: 'Show more'),
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
          ],
        );
      },
    );
  }
}

class _DetailExpandButton extends StatelessWidget {
  final bool expanded;
  final String text;
  final VoidCallback onPressed;

  const _DetailExpandButton({
    super.key,
    required this.expanded,
    required this.text,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF22D3EE)
              : const Color(0xFF087F9B),
          padding: const EdgeInsets.symmetric(vertical: 4),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.centerLeft,
          textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
        ),
        child: Wrap(
          spacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(text),
            Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 14,
            ),
          ],
        ),
      );
}
