import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../../basic/commons.dart';
import 'floating_search_bar.dart';
import 'search_history_shared.dart';

final _event = Event();
final List<Block> _blockStore = [];
final List<SearchHistory> _histories = [];

set blockStore(List<Block> values) {
  _blockStore.clear();
  _blockStore.addAll(values);
  _event.broadcast();
}

set searchHistories(List<SearchHistory> values) {
  _histories.clear();
  _histories.addAll(normalizeSearchHistoriesForPanel(values));
  _event.broadcast();
}

class ComicFloatingSearchBarScreen extends StatefulWidget {
  final FloatingSearchBarController controller;
  final Widget child;
  final ValueChanged<String>? onQuery;

  const ComicFloatingSearchBarScreen({
    Key? key,
    required this.controller,
    required this.child,
    this.onQuery,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ComicFloatingSearchBarScreenState();
}

class _ComicFloatingSearchBarScreenState
    extends State<ComicFloatingSearchBarScreen> {
  final _panelController = ScrollController();

  @override
  void initState() {
    _event.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    _event.unsubscribe(_setState);
    _panelController.dispose();
    super.dispose();
  }

  void _setState(_) {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FloatingSearchBarScreen(
      controller: widget.controller,
      child: widget.child,
      onSubmitted: _onSubmitted,
      panel: _buildPanel(),
    );
  }

  void _onSubmitted(String value) {
    final query = normalizeSearchPanelQuery(value);
    widget.controller.hide();
    if (query != null && widget.onQuery != null) {
      widget.onQuery!(query);
    }
  }

  Widget _buildPanel() {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final compact = MediaQuery.sizeOf(context).width < 840;
    return ListView(
      controller: _panelController,
      // The search scaffold already resizes above the keyboard on phones.
      padding: compact
          ? const EdgeInsets.all(10)
          : EdgeInsets.fromLTRB(12, 8, 12, 12 + viewInsets.bottom),
      children: [
        ..._buildHistory(),
        ..._buildTags(),
      ],
    );
  }

  List<Widget> _buildHistory() {
    if (_histories.isEmpty) {
      return [];
    }
    final l10n = context.l10n;
    final yes = l10n.yes;
    final no = l10n.no;
    final List<Widget> widgets = [];
    widgets.add(_buildTitle(l10n.tr("历史记录", en: "History"), clear: () async {
      String? choose = await chooseListDialog(
        context,
        values: [yes, no],
        title: l10n.tr("清除所有历史记录?", en: "Clear all history?"),
      );
      if (yes == choose) {
        await methods.clearAllSearchLog();
        _histories.clear();
        _setState(null);
      }
    }));
    widgets.add(Wrap(
      children: _histories.map((e) {
        return _buildSuggestionChip(
          icon: Icons.history_rounded,
          label: e.searchQuery,
          onTap: () {
            _onSubmitted(e.searchQuery);
          },
          onLongPress: () async {
            String? choose = await chooseListDialog(
              context,
              values: [yes, no],
              title: l10n.tr(
                "清除历史记录\"${e.searchQuery}\"?",
                en: "Clear history \"${e.searchQuery}\"?",
              ),
            );
            if (yes == choose) {
              await methods.clearASearchLog(e.searchQuery);
              _histories.remove(e);
              _setState(null);
            }
          },
        );
      }).toList(),
    ));
    return widgets;
  }

  List<Widget> _buildTags() {
    final l10n = context.l10n;
    final List<Widget> widgets = [];
    widgets.add(_buildTitle(l10n.tr("板块", en: "Blocks")));
    for (final block in _blockStore) {
      widgets.add(_buildSubTitle(block.title));
      widgets.add(Wrap(
        children: block.content.map((e) {
          return _buildSuggestionChip(
            icon: Icons.local_offer_outlined,
            label: e,
            onTap: () {
              _onSubmitted(e);
            },
          );
        }).toList(),
      ));
    }
    return widgets;
  }

  Widget _buildSuggestionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    if (MediaQuery.sizeOf(context).width < 840) {
      // Restore the compact text-only tags used before PR #7. In particular,
      // do not reserve an icon slot or truncate longer tags to one line.
      return InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.pink.shade100,
            border: Border.all(color: Colors.pink.shade400),
            borderRadius: const BorderRadius.all(Radius.circular(30)),
          ),
          child: Text(
            label,
            style: TextStyle(color: Colors.pink.shade500, height: 1.4),
            strutStyle: const StrutStyle(height: 1.4),
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8, bottom: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: 40,
          maxWidth: 280,
        ),
        child: Material(
          color: scheme.secondaryContainer,
          shape: StadiumBorder(
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSecondaryContainer,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(String title, {void Function()? clear}) {
    if (clear != null) {
      return Container(
        margin: const EdgeInsets.only(top: 10, bottom: 5),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            Expanded(child: Container()),
            IconButton(
              onPressed: clear,
              icon: const Icon(Icons.close, size: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 5),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSubTitle(String title) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(
        title,
      ),
    );
  }
}
