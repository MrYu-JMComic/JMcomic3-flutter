import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/screens/comic_info_screen.dart';
import 'package:jmcomic3/screens/components/types.dart';

import 'comic_info_card.dart';
import 'images.dart';

class ComicList extends StatefulWidget {
  final bool inScroll;
  final List<ComicBasic> data;
  final List<Widget>? appendList;
  final ScrollController? controller;
  final Function? onScroll;
  final List<ComicLongPressMenuItem>? longPressMenuItems;

  const ComicList({
    Key? key,
    required this.data,
    this.appendList,
    this.controller,
    this.inScroll = false,
    this.onScroll,
    this.longPressMenuItems,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ComicListState();
}

class _ComicListState extends State<ComicList> {
  @override
  void initState() {
    currentPagerViewModeEvent.subscribe(_setState);
    pageColumnEvent.subscribe(_setState);
    pagerCoverRateEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    currentPagerViewModeEvent.unsubscribe(_setState);
    pageColumnEvent.unsubscribe(_setState);
    pagerCoverRateEvent.unsubscribe(_setState);
    super.dispose();
  }

  _setState(_) {
    setState(() {});
  }

  static const double _spacing = 12;
  static const EdgeInsets _contentPadding = EdgeInsets.all(12);

  @override
  Widget build(BuildContext context) {
    if (currentPagerViewMode == PagerViewMode.info) {
      return _buildInfoMode();
    }
    return _buildGridMode();
  }

  int get _itemCount => widget.data.length + (widget.appendList?.length ?? 0);

  double get _coverAspectRatio =>
      currentPagerCoverRate == PagerCoverRate.rate3x4 ? 3 / 4 : 1;

  Widget _buildGridMode() {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth <= 0) return const SizedBox.shrink();
      final horizontalPadding = math.min(12.0, constraints.maxWidth / 4);
      final contentWidth = constraints.maxWidth - horizontalPadding * 2;
      // Two columns keep covers and titles readable on phone-sized screens;
      // the saved desktop preference still applies to wider layouts.
      final columnCount = constraints.maxWidth < 600
          ? math.min(pagerColumnNumber, 2)
          : pagerColumnNumber;
      // Keep the configured number of columns even in an unusually small
      // desktop window; reduce gaps only when 12px would consume the grid.
      final spacing = math.min(_spacing, contentWidth / (columnCount * 2));
      final padding = EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 12,
      );
      final columnWidth =
          (contentWidth - spacing * (columnCount - 1)) / columnCount;
      final coverHeight = columnWidth / _coverAspectRatio;
      final titleStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
            height: 1.3,
            fontWeight: FontWeight.w500,
          );
      // Reserve two complete lines at the active text scale, including fonts
      // whose ascent/descent is larger than their nominal font size.
      final titlePainter = TextPainter(
        text: TextSpan(text: 'Ag国\nAg国', style: titleStyle),
        textDirection: Directionality.of(context),
        locale: Localizations.maybeLocaleOf(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 2,
      )..layout();
      final titleHeight = titlePainter.height.ceilToDouble();
      titlePainter.dispose();
      final itemHeight = coverHeight +
          (currentPagerViewMode == PagerViewMode.titleAndCover
              ? titleHeight + 8
              : 0);

      Widget itemBuilder(BuildContext context, int index) {
        if (index >= widget.data.length) {
          return widget.appendList![index - widget.data.length];
        }
        return _buildGridItem(index, coverHeight, titleHeight, titleStyle);
      }

      if (widget.inScroll) {
        return Padding(
          padding: padding,
          child: Wrap(
            spacing: spacing,
            runSpacing: _spacing,
            children: List.generate(
              _itemCount,
              (index) => SizedBox(
                width: columnWidth,
                height: itemHeight,
                child: itemBuilder(context, index),
              ),
            ),
          ),
        );
      }
      return _wrapWithScrollListener(GridView.builder(
        controller: widget.controller,
        padding: padding,
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columnCount,
          mainAxisSpacing: _spacing,
          crossAxisSpacing: spacing,
          mainAxisExtent: itemHeight,
        ),
        itemCount: _itemCount,
        itemBuilder: itemBuilder,
      ));
    });
  }

  Widget _buildGridItem(
    int index,
    double coverHeight,
    double titleHeight,
    TextStyle titleStyle,
  ) {
    final comic = widget.data[index];
    final cover = SizedBox(
      height: coverHeight,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (context, constraints) {
          final image = _buildCover(index, constraints);
          if (currentPagerViewMode != PagerViewMode.titleInCover) {
            return image;
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              image,
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xE6000000)],
                    ),
                  ),
                  child: Text(
                    comic.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _pushToComicInfo(comic),
      onLongPress: _longPressCallback(index),
      child: currentPagerViewMode == PagerViewMode.titleAndCover
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cover,
                const SizedBox(height: 8),
                SizedBox(
                  height: titleHeight,
                  child: Text(
                    comic.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
              ],
            )
          : cover,
    );
  }

  Widget _buildCover(int index, BoxConstraints constraints) {
    switch (currentPagerCoverRate) {
      case PagerCoverRate.rate3x4:
        return JM3x4Cover(
          comicId: widget.data[index].id,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          longPressMenuItems: _longPressImageCallback(index),
        );
      case PagerCoverRate.rateSquare:
        return JMSquareCover(
          comicId: widget.data[index].id,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          longPressMenuItems: _longPressImageCallback(index),
        );
    }
  }

  Widget _buildInfoMode() {
    Widget itemBuilder(BuildContext context, int index) {
      if (index >= widget.data.length) {
        return widget.appendList![index - widget.data.length];
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pushToComicInfo(widget.data[index]),
        onLongPress: _longPressCallback(index),
        child: ComicInfoCard(widget.data[index]),
      );
    }

    if (widget.inScroll) {
      return Padding(
        padding: _contentPadding,
        child: Column(
          children: [
            for (var index = 0; index < _itemCount; index++) ...[
              if (index > 0) const SizedBox(height: _spacing),
              itemBuilder(context, index),
            ],
          ],
        ),
      );
    }
    return _wrapWithScrollListener(ListView.separated(
      controller: widget.controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: _contentPadding,
      itemCount: _itemCount,
      separatorBuilder: (context, index) => const SizedBox(height: _spacing),
      itemBuilder: itemBuilder,
    ));
  }

  void _pushToComicInfo(ComicBasic data) {
    Navigator.push(context, MaterialPageRoute(builder: (BuildContext context) {
      return ComicInfoScreen(data.id, data);
    }));
  }

  Widget _wrapWithScrollListener(Widget child) {
    if (widget.onScroll == null) {
      return child;
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (scrollNotification) {
        widget.onScroll?.call();
        return false;
      },
      child: child,
    );
  }

  GestureLongPressCallback? _longPressCallback(int index) {
    if (widget.longPressMenuItems != null &&
        widget.longPressMenuItems!.isNotEmpty) {
      return () {
        showMenu(
          context: context,
          position: const RelativeRect.fromLTRB(0, 0, 0, 0),
          items: widget.longPressMenuItems!
              .map((e) => PopupMenuItem(
                    child: Text(e.title),
                    value: e,
                  ))
              .toList(),
        ).then((value) {
          if (value != null) {
            value.onChoose.call(widget.data[index]);
          }
        });
      };
    }
    return null;
  }

  List<LongPressMenuItem>? _longPressImageCallback(int index) {
    if (widget.longPressMenuItems != null &&
        widget.longPressMenuItems!.isNotEmpty) {
      return widget.longPressMenuItems!
          .map((e) => LongPressMenuItem(e.title, () {
                e.onChoose(widget.data[index]);
              }))
          .toList();
    }
    return null;
  }
}
