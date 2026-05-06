import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/configs/auto_clean.dart';
import 'package:jmcomic3/configs/network_api_host.dart';
import 'package:jmcomic3/configs/network_cdn_host.dart';
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_controller_mode.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

class BrowserBottomSheetAction extends StatelessWidget {
  const BrowserBottomSheetAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        _displayBrowserBottomSheet(context);
      },
      icon: const Icon(Icons.menu),
    );
  }
}

Future<void> _displayBrowserBottomSheet(BuildContext context) async {
  await showMaterialModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xAA000000),
    builder: (context) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * .45,
        child: const _BrowserBottomSheet(),
      );
    },
  );
}

class _BrowserBottomSheet extends StatefulWidget {
  const _BrowserBottomSheet();

  @override
  State<StatefulWidget> createState() => _BrowserBottomSheetState();
}

class _BrowserBottomSheetState extends State<_BrowserBottomSheet> {
  bool _manualCleaning = false;

  bool get _cleaning => _manualCleaning || cacheCleaningInProgress;

  @override
  void initState() {
    currentPagerControllerModeEvent.subscribe(_setState);
    currentPagerViewModeEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    currentPagerControllerModeEvent.unsubscribe(_setState);
    currentPagerViewModeEvent.unsubscribe(_setState);
    super.dispose();
  }

  void _setState(_) {
    setState(() {});
  }

  Future<void> _runManualClean() async {
    if (_cleaning) {
      return;
    }
    setState(() {
      _manualCleaning = true;
    });
    defaultToast(
        context, context.l10n.tr('开始清理缓存', en: 'Start cleaning cache'));
    final result = await cleanCache();
    if (!mounted) {
      return;
    }
    setState(() {
      _manualCleaning = false;
    });
    if (result.success) {
      defaultToast(
        context,
        context.l10n.tr(
          '清理完成 (${result.duration.inMilliseconds}ms)',
          en: 'Cleanup complete (${result.duration.inMilliseconds}ms)',
        ),
      );
      return;
    }
    debugPrient('clean cache failed: ${result.error}');
    defaultToast(
      context,
      context.l10n
          .tr('清理失败，请稍后重试', en: 'Cleanup failed, please try again later'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Row(
          children: [
            Expanded(child: Container()),
            _bottomIcon(
              icon: Icons.view_quilt,
              title: currentPagerViewModeName(context),
              onPressed: () async {
                await choosePagerViewMode(context);
                setState(() {});
              },
            ),
            Expanded(child: Container()),
            _bottomIcon(
              icon: Icons.view_day_outlined,
              title: currentPagerControllerModeName(context),
              onPressed: () async {
                await choosePagerControllerMode(context);
                setState(() {});
              },
            ),
            Expanded(child: Container()),
            _bottomIcon(
              icon: Icons.grid_on_sharp,
              title: pagerCoverRateName(currentPagerCoverRate, context),
              onPressed: () async {
                await choosePagerCoverRate(context);
                setState(() {});
              },
            ),
            Expanded(child: Container()),
            _bottomIcon(
              icon: Icons.view_column_sharp,
              title: context.l10n
                  .tr('$pagerColumnNumber 列', en: '$pagerColumnNumber cols'),
              onPressed: () async {
                await choosePagerColumnCount(context);
                setState(() {});
              },
            ),
            Expanded(child: Container()),
          ],
        ),
        Row(
          children: [
            Expanded(child: Container()),
            _bottomIcon(
              icon: _cleaning
                  ? Icons.cleaning_services_outlined
                  : Icons.cleaning_services_rounded,
              title: _cleaning
                  ? context.l10n.tr('清理中...', en: 'Cleaning...')
                  : context.l10n.tr('清理', en: 'Clean'),
              onPressed: _cleaning
                  ? null
                  : () {
                      _runManualClean();
                    },
            ),
            Expanded(child: Container()),
            _bottomIcon(
              icon: Icons.auto_delete_outlined,
              title: autoCleanNameOf(context),
              onPressed: () async {
                await chooseAutoClean(context);
                setState(() {});
              },
            ),
            Expanded(child: Container()),
            _bottomIcon(
              icon: Icons.shuffle,
              title: currentApiHostName,
              onPressed: () async {
                await chooseApiHost(context);
                setState(() {});
              },
            ),
            Expanded(child: Container()),
            _bottomIcon(
              icon: Icons.repeat_one,
              title: currentCdnHostName,
              onPressed: () async {
                await chooseCdnHost(context);
                setState(() {});
              },
            ),
            Expanded(child: Container()),
          ],
        ),
      ],
    );
  }

  Widget _bottomIcon({
    required IconData icon,
    required String title,
    required VoidCallback? onPressed,
  }) {
    final disabled = onPressed == null;
    final color = disabled ? Colors.white54 : Colors.white;
    return Expanded(
      child: Center(
        child: Column(
          children: [
            IconButton(
              iconSize: 55,
              icon: Column(
                children: [
                  const SizedBox(height: 3),
                  Icon(
                    icon,
                    size: 25,
                    color: color,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    title,
                    style: TextStyle(color: color, fontSize: 10),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 3),
                ],
              ),
              onPressed: onPressed,
            ),
          ],
        ),
      ),
    );
  }
}
