import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/download_thread_count.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/content_loading.dart';
import 'package:jmcomic3/screens/download_import_screen.dart';

import 'components/comic_download_card.dart';
import 'components/right_click_pop.dart';
import 'download_album_screen.dart';
import 'downloads_exports_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  static const _autoRefreshInterval = Duration(seconds: 2);

  bool _loading = true;
  bool _loadingDownloads = false;
  List<DownloadAlbum> _downloads = [];
  Timer? _autoRefreshTimer;

  void _setState(_) {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load({bool showLoading = false}) async {
    if (_loadingDownloads) {
      _syncAutoRefresh();
      return;
    }
    _loadingDownloads = true;
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final downloads = await methods.allDownloads();
      if (!mounted) {
        return;
      }
      setState(() {
        _downloads = downloads;
        _loading = false;
      });
    } catch (_e) {
      // 极端情况才发生, 忽略
    } finally {
      _loadingDownloads = false;
      if (mounted) {
        if (showLoading && _loading) {
          setState(() {
            _loading = false;
          });
        }
        _syncAutoRefresh();
      }
    }
  }

  void _syncAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    if (!_downloads.any((e) => e.shouldAutoRefreshStatus)) {
      return;
    }
    _autoRefreshTimer = Timer(_autoRefreshInterval, () {
      _load();
    });
  }

  @override
  void initState() {
    super.initState();
    downloadThreadCountEvent.subscribe(_setState);
    _load(showLoading: true);
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    downloadThreadCountEvent.unsubscribe(_setState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.downloads),
        actions: [
          threadCountButton(),
          exportButton(),
          importButton(),
          IconButton(
            onPressed: () async {
              await methods.renewAllDownloads();
              if (!mounted) {
                return;
              }
              _load(showLoading: _downloads.isEmpty);
            },
            icon: const Icon(Icons.autorenew),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && _downloads.isEmpty) {
      return ContentLoading(label: context.l10n.loading);
    }
    // if (_loading) 可以加个浮层, 极为短暂, 性价比比较低
    return _listView();
  }

  Widget _listView() {
    // 下载记录可能长期累积；列表页只构建可见卡片，避免进入页面时一次性创建全部 Widget。
    return ListView.builder(
      itemCount: _downloads.length,
      itemBuilder: (context, index) {
        final download = _downloads[index];
        return GestureDetector(
          key: Key("DOWNLOAD:${download.id}"),
          onTap: () => _openDownload(download),
          onLongPress: () => _confirmDelete(download),
          child: ComicDownloadCard(download),
        );
      },
    );
  }

  Future<void> _openDownload(DownloadAlbum download) async {
    if (download.dlStatus == 3) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (BuildContext context) {
        return DownloadAlbumScreen(download);
      }),
    );
    if (!mounted) {
      return;
    }
    _load();
  }

  Future<void> _confirmDelete(DownloadAlbum download) async {
    final deleteLabel = context.l10n.delete;
    final chooseTitle = context.l10n.choose;
    final action = await chooseListDialog(
      context,
      values: [deleteLabel],
      title: chooseTitle,
    );
    if (!mounted || action != deleteLabel) {
      return;
    }
    await methods.deleteDownload(download.id);
    if (!mounted) {
      return;
    }
    _load(showLoading: _downloads.isEmpty);
  }

  Widget importButton() {
    return IconButton(
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const DownloadImportScreen(),
          ),
        );
        if (!mounted) {
          return;
        }
        _load(showLoading: _downloads.isEmpty);
      },
      icon: const Icon(
        Icons.drive_folder_upload,
      ),
    );
  }

  Widget exportButton() {
    return IconButton(
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const DownloadsExportScreen(),
          ),
        );
        if (!mounted) {
          return;
        }
        _load(showLoading: _downloads.isEmpty);
      },
      icon: const Icon(
        Icons.sim_card_download_outlined,
      ),
    );
  }

  Widget threadCountButton() {
    return MaterialButton(
      onPressed: () async {
        await chooseDownloadThread(context);
      },
      minWidth: 0,
      child: Text(
        "$downloadThreadCount${context.l10n.threadSuffix}",
      ),
    );
  }
}
