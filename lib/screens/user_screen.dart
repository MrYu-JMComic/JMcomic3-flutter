import 'package:flutter/material.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/about_screen.dart';
import 'package:jmcomic3/screens/comments_screen.dart';
import 'package:jmcomic3/screens/components/avatar.dart';
import 'package:jmcomic3/screens/pro_oh_screen.dart';
import 'package:jmcomic3/screens/pro_screen.dart';
import 'package:jmcomic3/screens/components/recommend_links_panel.dart';
import 'package:jmcomic3/screens/settings_screen.dart';
import 'package:jmcomic3/screens/view_log_screen.dart';

import '../basic/platform.dart';
import '../configs/daily_sign.dart';
import '../configs/is_pro.dart';
import 'components/badge.dart';
import 'downloads_screen.dart';
import 'favorites_screen.dart';

class UserScreen extends StatefulWidget {
  const UserScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    loginEvent.subscribe(_setState);
    proEvent.subscribe(_setState);
    dailySignEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    loginEvent.unsubscribe(_setState);
    proEvent.unsubscribe(_setState);
    dailySignEvent.unsubscribe(_setState);
    super.dispose();
  }

  void _setState(_) {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.profile), actions: [
        if (!normalPlatform)
          IconButton(
            tooltip: 'Pro',
            onPressed: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (BuildContext context) {
                return const ProOhScreen();
              }));
            },
            icon: Icon(
              hasProAccess ? Icons.offline_bolt : Icons.offline_bolt_outlined,
            ),
          ),
        if (normalPlatform)
          IconButton(
            tooltip: 'Pro',
            onPressed: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (BuildContext context) {
                return const ProScreen();
              }));
            },
            icon: Icon(
              hasProAccess ? Icons.offline_bolt : Icons.offline_bolt_outlined,
            ),
          ),
        _buildSettingsIcon(),
        if (normalPlatform) _buildAboutIcon(),
      ]),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            final spacing = constraints.maxWidth >= 600 ? 24.0 : 16.0;
            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Padding(
                    padding: EdgeInsets.all(spacing),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 5, child: _buildCard()),
                              SizedBox(width: spacing),
                              Expanded(flex: 6, child: _buildLibrary()),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildCard(),
                              SizedBox(height: spacing),
                              _buildLibrary(),
                            ],
                          ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLibrary() {
    if (MediaQuery.sizeOf(context).width < 600) {
      return _buildMobileLibrary();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            context.l10n.navLibrary,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 560;
            final width = twoColumns
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildFavorites(),
                _buildViewLog(),
                _buildDownloads(),
                _buildComments(),
              ].map((child) => SizedBox(width: width, child: child)).toList(),
            );
          },
        ),
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: RecommendLinksPanel(
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLibrary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMobileLibraryAction(
          icon: Icons.favorite_border,
          title: context.l10n.favorites,
          onTap: _openFavorites,
        ),
        _buildMobileLibraryAction(
          icon: Icons.history,
          title: context.l10n.viewHistory,
          onTap: _openViewLog,
        ),
        _buildMobileLibraryAction(
          icon: Icons.download_outlined,
          title: context.l10n.downloadList,
          onTap: _openDownloads,
        ),
        _buildMobileLibraryAction(
          icon: Icons.chat_bubble_outline,
          title: context.l10n.comments,
          onTap: _openComments,
          last: true,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: RecommendLinksPanel(
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLibraryAction({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    bool last = false,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dividerColor = colors.outlineVariant.withValues(alpha: .7);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: dividerColor),
              bottom: last ? BorderSide(color: dividerColor) : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: colors.onSurfaceVariant, size: 23),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right,
                  color: colors.onSurfaceVariant, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountPrompt({
    required IconData icon,
    required String title,
    required Widget action,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 36, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        action,
      ],
    );
  }

  Widget _buildCard() {
    late Widget child;
    switch (loginStatus) {
      case LoginStatus.notSet:
        child = _buildAccountPrompt(
          icon: Icons.account_circle_outlined,
          title: context.l10n.account,
          action: _buildLoginButton(context.l10n.loginRegister),
        );
        break;
      case LoginStatus.logging:
        child = _buildLoginLoading();
        break;
      case LoginStatus.loginSuccess:
        child = _buildSelfInfoCard();
        break;
      case LoginStatus.guest:
        child = _buildGuestCard();
        break;
      case LoginStatus.loginField:
        child = _buildAccountPrompt(
          icon: Icons.error_outline,
          title: context.l10n.loginFailed,
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildLoginButton(context.l10n.login),
              _buildLoginErrorButton(),
            ],
          ),
        );
        break;
    }
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer.withValues(alpha: .45),
            colors.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .6)),
      ),
      child: child,
    );
  }

  Widget _buildLoginButton(String title) {
    return FilledButton.icon(
      onPressed: () async {
        await loginDialog(context);
      },
      icon: const Icon(Icons.login, size: 18),
      label: Text(title, textAlign: TextAlign.center),
    );
  }

  Widget _buildLoginLoading() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(context.l10n.loggingIn)),
        ],
      ),
    );
  }

  Widget _buildLoginErrorButton() {
    return OutlinedButton.icon(
      onPressed: () async {
        await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(context.l10n.loginFailed),
              content: SelectableText(loginMessage),
              actions: [
                MaterialButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(context.l10n.confirm),
                ),
              ],
            );
          },
        );
      },
      icon: const Icon(Icons.error_outline, size: 18),
      label: Text(context.l10n.viewError),
    );
  }

  Widget _buildSelfInfoCard() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final isLight = theme.brightness == Brightness.light;
    Color statusColor;
    switch (dailySignStatus) {
      case DailySignStatus.signed:
        statusColor = isLight ? Colors.green.shade700 : Colors.green.shade200;
        break;
      case DailySignStatus.error:
        statusColor = colors.error;
        break;
      case DailySignStatus.checking:
        statusColor = colors.primary;
        break;
      case DailySignStatus.unchecked:
        statusColor = colors.onSurfaceVariant;
        break;
    }
    final statusStyle = theme.textTheme.bodySmall?.copyWith(
      color: statusColor,
      fontWeight: FontWeight.w600,
    );
    final detailStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final uidText = "UID ${selfInfo.uid}";
    final levelText = "${selfInfo.levelName} Lv.${selfInfo.level}";
    final expPercentText = "${_formatExpPercent(selfInfo.expPercent)}%";
    final genderText = _formatGender(selfInfo.gender);
    final nickname =
        selfInfo.fname.trim().isEmpty ? "-" : selfInfo.fname.trim();
    final message = selfInfo.message.trim();
    final canSign = dailySignStatus != DailySignStatus.checking;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
      children: [
        if (compact)
          Column(
            children: [
              Avatar(selfInfo.photo),
              const SizedBox(height: 10),
              Text(
                selfInfo.username,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(uidText, textAlign: TextAlign.center, style: detailStyle),
            ],
          )
        else
          Row(
            children: [
              Avatar(selfInfo.photo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selfInfo.username,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(uidText, style: detailStyle),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),
        Wrap(
          alignment: compact ? WrapAlignment.center : WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildSelfInfoBadge(
              context,
              context.l10n.level,
              levelText,
              Icons.workspace_premium_outlined,
            ),
            _buildSelfInfoBadge(
              context,
              context.l10n.experience,
              expPercentText,
              Icons.trending_up,
            ),
            _buildSelfInfoBadge(
              context,
              context.l10n.coin,
              "${selfInfo.coin}",
              Icons.monetization_on_outlined,
            ),
            _buildSelfInfoBadge(
              context,
              context.l10n.badges,
              "${selfInfo.badges.length}",
              Icons.verified_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (selfInfo.email.trim().isNotEmpty) ...[
          Text(
            "${context.l10n.email}: ${selfInfo.email}",
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: detailStyle,
          ),
          const SizedBox(height: 4),
        ],
        Wrap(
          alignment: compact ? WrapAlignment.center : WrapAlignment.start,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text("${context.l10n.nickname}: $nickname",
                textAlign: compact ? TextAlign.center : TextAlign.start,
                style: detailStyle),
            Text("${context.l10n.gender}: $genderText",
                textAlign: compact ? TextAlign.center : TextAlign.start,
                style: detailStyle),
          ],
        ),
        if (message.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            "${context.l10n.signature}: $message",
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: detailStyle,
          ),
        ],
        const SizedBox(height: 16),
        if (compact)
          Column(
            children: [
              Text(dailySignStatusLabel(context), style: statusStyle),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 160,
                  maxWidth: 320,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: canSign
                        ? () async {
                            await checkDailySignStatus(context, toast: true);
                          }
                        : null,
                    icon: Icon(
                      canSign ? Icons.check_circle_outline : Icons.sync,
                      size: 18,
                    ),
                    label: Text(
                      canSign ? context.l10n.manualSign : context.l10n.signing,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: canSign
                    ? () async {
                        await checkDailySignStatus(context, toast: true);
                      }
                    : null,
                icon: Icon(
                  canSign ? Icons.check_circle_outline : Icons.sync,
                  size: 18,
                ),
                label: Text(
                  canSign ? context.l10n.manualSign : context.l10n.signing,
                  textAlign: TextAlign.center,
                ),
              ),
              Text(
                dailySignStatusLabel(context),
                style: statusStyle,
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildSelfInfoBadge(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: colors.primary,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              "$label: $value",
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatGender(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return "-";
    }
    if (value == "m" || value == "male" || value == "1") {
      return context.l10n.male;
    }
    if (value == "f" || value == "female" || value == "2") {
      return context.l10n.female;
    }
    return value;
  }

  String _formatExpPercent(double value) {
    final normalized = value <= 1 ? value * 100 : value;
    final safe = normalized.isNaN ? 0.0 : normalized.clamp(0, 100).toDouble();
    if (safe >= 10) {
      return safe.toStringAsFixed(0);
    }
    return safe.toStringAsFixed(1);
  }

  Widget _buildGuestCard() {
    return _buildAccountPrompt(
      icon: Icons.explore_outlined,
      title: context.l10n.guestMode,
      subtitle: context.l10n.guestModeSubtitle,
      action: _buildLoginButton(context.l10n.login),
    );
  }

  Widget _buildLibraryAction({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(icon, color: colors.primary, size: 24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: colors.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavorites() {
    return _buildLibraryAction(
      icon: Icons.favorite_border,
      title: context.l10n.favorites,
      onTap: _openFavorites,
    );
  }

  Widget _buildViewLog() {
    return _buildLibraryAction(
      icon: Icons.history,
      title: context.l10n.viewHistory,
      onTap: _openViewLog,
    );
  }

  Widget _buildDownloads() {
    return _buildLibraryAction(
      icon: Icons.download_outlined,
      title: context.l10n.downloadList,
      onTap: _openDownloads,
    );
  }

  Widget _buildComments() {
    return _buildLibraryAction(
      icon: Icons.chat_bubble_outline,
      title: context.l10n.comments,
      onTap: _openComments,
    );
  }

  Future<void> _openFavorites() async {
    if (!await ensureJwtAccess(
          context,
          feature: context.l10n.featureFavoritesFolder,
        ) ||
        !mounted) {
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (BuildContext context) {
        return const FavoritesScreen();
      },
    ));
  }

  void _openViewLog() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (BuildContext context) {
        return const ViewLogScreen();
      },
    ));
  }

  void _openDownloads() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (BuildContext context) {
        return const DownloadsScreen();
      },
    ));
  }

  void _openComments() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (BuildContext context) {
        return const CommentsScreen();
      },
    ));
  }

  Widget _buildSettingsIcon() {
    return IconButton(
      tooltip: context.l10n.settings,
      onPressed: () async {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (BuildContext context) {
            return const SettingsScreen();
          },
        ));
      },
      icon: const Icon(Icons.settings),
    );
  }

  Widget _buildAboutIcon() {
    return IconButton(
      tooltip: context.l10n.about,
      onPressed: () async {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (BuildContext context) {
            return const AboutScreen();
          },
        ));
      },
      icon: const VersionBadged(
        child: Padding(
          padding: EdgeInsets.all(1),
          child: Icon(Icons.info_outlined),
        ),
      ),
    );
  }
}
