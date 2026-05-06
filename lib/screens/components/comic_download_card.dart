import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../../basic/methods.dart';
import 'images.dart';

class ComicDownloadCard extends StatelessWidget {
  final DownloadAlbum comic;

  const ComicDownloadCard(
    this.comic, {
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const titleStyle = TextStyle(fontWeight: FontWeight.bold);
    final authorStyle = TextStyle(
      fontSize: 13,
      color: Colors.pink.shade300,
    );
    return Container(
      padding: const EdgeInsets.only(top: 5, bottom: 5, left: 10, right: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Card(
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
                Text(comic.name, style: titleStyle),
                Container(height: 4),
                Text(comic.authorLabel, style: authorStyle),
                Container(height: 4),
                _buildCategoryRow(),
                Container(height: 4),
                Text.rich(TextSpan(children: [
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.download, size: 12),
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Container(width: 3),
                  ),
                  TextSpan(
                    text: "${comic.dledImageCount} / ${comic.imageCount}",
                    style: const TextStyle(fontSize: 10),
                  ),
                ])),
                Container(height: 4),
                _buildProgress(context),
                Container(height: 4),
                Text(
                  _statusText(context),
                  style: TextStyle(color: _statusColor()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final progress = comic.downloadProgress;
    if (progress == null) {
      return Container();
    }
    final color = _statusColor();
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(3)),
      child: LinearProgressIndicator(
        value: comic.isDeleting ? null : progress,
        minHeight: 4,
        color: color,
        backgroundColor: color.withOpacity(.14),
      ),
    );
  }

  String _statusText(BuildContext context) {
    if (comic.isQueuedOrDownloading) {
      if (comic.dledImageCount > 0) {
        return context.l10n.tr("下载中", en: "Downloading");
      }
      return context.l10n.tr("队列中", en: "Queued");
    }
    if (comic.isDownloaded) {
      return context.l10n.tr("已下载", en: "Downloaded");
    }
    if (comic.isFailed) {
      return context.l10n.tr("已失败", en: "Failed");
    }
    if (comic.isDeleting) {
      return context.l10n.tr("删除中", en: "Deleting");
    }
    return context.l10n.tr("未知状态", en: "Unknown status");
  }

  Color _statusColor() {
    if (comic.isQueuedOrDownloading) {
      return Colors.blue;
    }
    if (comic.isDownloaded) {
      return Colors.green;
    }
    if (comic.isFailed) {
      return Colors.red;
    }
    if (comic.isDeleting) {
      return Colors.orange;
    }
    return Colors.grey;
  }

  Widget _buildCategoryRow() {
    if (comic is ComicSimple) {
      var _comic = comic as ComicSimple;
      return Row(
        children: [
          ..._c(_comic.category),
          ..._c(_comic.categorySub),
        ],
      );
    }
    return Container();
  }

  List<Widget> _c(ComicSimpleCategory category) {
    if (category.title == null) {
      return [];
    }
    return [
      Text(category.title!),
      Container(width: 15),
    ];
  }
}
