import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/app_font_size.dart';
import 'package:jmcomic3/configs/app_locale.dart';
import 'package:jmcomic3/configs/app_orientation.dart';
import 'package:jmcomic3/configs/network_api_host.dart';
import 'package:jmcomic3/configs/network_cdn_host.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/downloads_exports_screen2.dart';

import '../basic/commons.dart';
import '../basic/web_dav_sync.dart';
import '../configs/Authentication.dart';
import '../configs/android_display_mode.dart';
import '../configs/categories_sort.dart';
import '../configs/display_jmcode.dart';
import '../configs/download_and_export_to.dart';
import '../configs/disable_recommend_content.dart';
import '../configs/export_rename.dart';
import '../configs/ignore_upgrade_pop.dart';
import '../configs/ignore_view_log.dart';
import '../configs/is_pro.dart';
import '../configs/login.dart';
import '../configs/no_animation.dart';
import '../configs/proxy.dart';
import '../configs/search_title_words.dart';
import '../configs/theme.dart';
import '../configs/two_page_direction.dart';
import '../configs/using_right_click_pop.dart';
import '../configs/versions.dart';
import '../configs/volume_key_control.dart';
import '../configs/web_dav_password.dart';
import '../configs/web_dav_sync_switch.dart';
import '../configs/web_dav_url.dart';
import '../configs/web_dav_username.dart';
import 'init_screen.dart';
import 'components/right_click_pop.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _SettingsState();
  }
}

class _SettingsState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            ExpansionTile(
              leading: const Icon(Icons.manage_accounts),
              title: Text(l10n.sectionUserNetwork),
              children: [
                const Divider(),
                apiHostSetting(),
                cdnHostSetting(),
                proxySetting(),
                const Divider(),
                createFavoriteFolderItemTile(context),
                deleteFavoriteFolderItemTile(context),
                renameFavoriteFolderItemTile(context),
                const Divider(),
                ListTile(
                  onTap: () async {
                    if (await confirmDialog(
                        context, l10n.clearAccount, l10n.clearAccountConfirm)) {
                      await methods.logout();
                      if (!mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (BuildContext context) => const InitScreen(),
                        ),
                        (route) => false,
                      );
                    }
                  },
                  title: Text(l10n.clearAccount),
                ),
                const Divider(),
              ],
            ),
            ExpansionTile(
              leading: Icon(Icons.menu_book_outlined),
              title: Text(l10n.sectionReading),
              children: [
                const Divider(),
                volumeKeyControlSetting(),
                noAnimationSetting(),
                const Divider(),
                twoGalleryDirectionSetting(context),
                const Divider(),
              ],
            ),
            ExpansionTile(
              leading: Icon(Icons.backup),
              title: Text(l10n.sectionSync),
              children: [
                const Divider(),
                webDavSyncSwitchSetting(),
                webDavUrlSetting(),
                webDavUserNameSetting(),
                webDavPasswordSetting(),
                webDavSyncClick(context),
                webDavSyncUploadClick(context),
                webDavSyncDownloadClick(context),
                const Divider(),
              ],
            ),
            ExpansionTile(
              leading: Icon(Icons.ad_units),
              title: Text(l10n.sectionSystemApp),
              children: [
                disableRecommendContentSetting(),
                userAgreementSetting(context),
                const Divider(),
                if (hasProAccess) ...[
                  const Divider(),
                  autoUpdateCheckSetting(),
                  ignoreUpgradePopSetting(),
                  const Divider(),
                ],
                const Divider(),
                ignoreVewLogSetting(),
                const Divider(),
                appOrientationWidget(),
                const Divider(),
                categoriesSortSetting(context),
                themeSetting(context),
                appLocaleSetting(context),
                const Divider(),
                androidDisplayModeSetting(),
                const Divider(),
                usingRightClickPopSetting(),
                const Divider(),
                authenticationSetting(),
                const Divider(),
                exportRenameSetting(),
                downloadAndExportToSetting(),
                const Divider(),
                displayJmcodeSetting(),
                const Divider(),
                ListTile(
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (c) => const DownloadsExportScreen2()));
                  },
                  title: Text(l10n.exportIncomplete),
                ),
                const Divider(),
                searchTitleWordsSetting(),
                ...fontSizeAdjustSettings(),
                const Divider(),
              ],
            ),
            SafeArea(
              top: false,
              child: Container(
                height: 50,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
