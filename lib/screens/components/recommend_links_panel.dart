import 'package:flutter/material.dart';

import '../../basic/commons.dart';
import '../../configs/disable_recommend_content.dart';
import '../../configs/is_pro.dart';
import '../../configs/recommend_links.dart';

class RecommendLinksPanel extends StatefulWidget {
  final EdgeInsetsGeometry padding;

  const RecommendLinksPanel({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  @override
  State<StatefulWidget> createState() => _RecommendLinksPanelState();
}

class _RecommendLinksPanelState extends State<RecommendLinksPanel> {
  @override
  void initState() {
    recommendLinksEvent.subscribe(_setState);
    disableRecommendContentEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    recommendLinksEvent.unsubscribe(_setState);
    disableRecommendContentEvent.unsubscribe(_setState);
    super.dispose();
  }

  void _setState(_) {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final links = currentRecommendLinks();
    if (links.isEmpty) {
      return const SizedBox.shrink();
    }
    if (hasProAccess && currentDisableRecommendContent()) {
      return const SizedBox.shrink();
    }

    final filteredLinks = links.entries.where((entry) {
      return !entry.key.contains("网络加速");
    }).toList();
    if (filteredLinks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          ...filteredLinks.map((entry) {
            return ListTile(
              onTap: () => openUrl(entry.value),
              title: Text(entry.key),
            );
          }),
        ],
      ),
    );
  }
}
