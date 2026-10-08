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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0F1319) : null,
      appBar: AppBar(
          title: Text(context.l10n.profile),
          titleTextStyle:
              Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
          actions: [
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
                  hasProAccess
                      ? Icons.offline_bolt
                      : Icons.offline_bolt_outlined,
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
                  hasProAccess
                      ? Icons.offline_bolt
                      : Icons.offline_bolt_outlined,
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
                  fontWeight: FontWeight.w500,
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          key: const ValueKey('profile-library-card'),
          color: _cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: _cardBorderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildMobileLibraryAction(
                icon: Icons.favorite,
                iconColor: theme.brightness == Brightness.dark
                    ? const Color(0xFFF4A4B9)
                    : Colors.pink.shade400,
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
            ],
          ),
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
    Color? iconColor,
    bool last = false,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dividerColor = colors.outlineVariant.withValues(alpha: .2);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: last ? BorderSide.none : BorderSide(color: dividerColor),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? colors.onSurfaceVariant, size: 23),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: colors.onSurfaceVariant, size: 22),
          ],
        ),
      ),
    );
  }

  Color get _cardColor => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF17272E)
      : Theme.of(context).colorScheme.surfaceContainerLow;

  Color get _cardBorderColor => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF243940)
      : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .6);

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
                      fontWeight: FontWeight.w500,
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
    return Container(
      key: const ValueKey('profile-account-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorderColor),
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
    final dark = theme.brightness == Brightness.dark;
    final accent = dark ? const Color(0xFF28D1DC) : colors.primary;
    final message = selfInfo.message.trim();
    final nickname = selfInfo.fname.trim();
    final email = selfInfo.email.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final signAtRight = constraints.maxWidth / textScale >= 300;
            final stackedIdentity = constraints.maxWidth / textScale < 200;
            final accountName = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      selfInfo.username,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    _buildIdentityBadge(
                      'Lv.${selfInfo.level}',
                      foreground: accent,
                      background: accent.withValues(alpha: .12),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'UID ${selfInfo.uid}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (selfInfo.levelName.trim().isNotEmpty)
                      _buildIdentityBadge(
                        selfInfo.levelName,
                        foreground: dark
                            ? const Color(0xFFE1C668)
                            : colors.onTertiaryContainer,
                        background: dark
                            ? const Color(0xFF3C392B)
                            : colors.tertiaryContainer,
                      ),
                  ],
                ),
              ],
            );
            final identity = stackedIdentity
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Avatar(selfInfo.photo, size: 50),
                      const SizedBox(height: 8),
                      accountName,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Avatar(selfInfo.photo, size: 50),
                      const SizedBox(width: 10),
                      Expanded(child: accountName),
                    ],
                  );
            return signAtRight
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 106),
                        child: _buildDailySign(),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      identity,
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _buildDailySign(),
                      ),
                    ],
                  );
          },
        ),
        _buildProfileDivider(),
        LayoutBuilder(
          builder: (context, constraints) {
            // Keep large accessibility text readable instead of shrinking the
            // account's numbers to fit three narrow columns.
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final horizontal = constraints.maxWidth / textScale >= 260;
            final stats = [
              _buildProfileStat(
                label: context.l10n.experience,
                value: '${_formatExpPercent(selfInfo.expPercent)}%',
                progress: _experienceProgress,
                accent: accent,
              ),
              _buildProfileStat(
                label: context.l10n.coin,
                value: '${selfInfo.coin}',
              ),
              _buildProfileStat(
                label: context.l10n.badges,
                value: '${selfInfo.badges.length}',
              ),
            ];
            if (!horizontal) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < stats.length; index++) ...[
                    if (index != 0) const SizedBox(height: 14),
                    stats[index],
                  ],
                ],
              );
            }
            return Row(
              key: const ValueKey('profile-statistics-row'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < stats.length; index++) ...[
                  if (index != 0)
                    Container(
                      width: 1,
                      height: 36,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      color: colors.outlineVariant.withValues(alpha: .22),
                    ),
                  Expanded(child: stats[index]),
                ],
              ],
            );
          },
        ),
        _buildProfileDivider(),
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final inline = constraints.maxWidth / textScale >= 315;
            final emailDetail = _buildProfileDetail(context.l10n.email, email);
            final genderDetail = _buildProfileDetail(
                context.l10n.gender, _formatGender(selfInfo.gender));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (inline)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (email.isNotEmpty) ...[
                        Expanded(flex: 3, child: emailDetail),
                        const SizedBox(width: 14),
                      ],
                      Expanded(flex: 2, child: genderDetail),
                    ],
                  )
                else ...[
                  if (email.isNotEmpty) ...[
                    emailDetail,
                    const SizedBox(height: 8),
                  ],
                  genderDetail,
                ],
                if (nickname.isNotEmpty && nickname != selfInfo.username) ...[
                  const SizedBox(height: 8),
                  _buildProfileDetail(context.l10n.nickname, nickname),
                ],
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildProfileDetail(context.l10n.signature, message),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildIdentityBadge(
    String value, {
    required Color foreground,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        value,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w400,
            ),
      ),
    );
  }

  Widget _buildDailySign() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final signed = dailySignStatus == DailySignStatus.signed;
    final checking = dailySignStatus == DailySignStatus.checking;
    final error = dailySignStatus == DailySignStatus.error;
    final statusColor = signed
        ? (theme.brightness == Brightness.dark
            ? const Color(0xFF5CD49A)
            : Colors.green.shade700)
        : error
            ? colors.error
            : colors.onSurfaceVariant;
    final label = signed
        ? dailySignStatusLabel(context)
        : checking
            ? context.l10n.signing
            : context.l10n.manualSign;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.tonal(
          key: const ValueKey('profile-daily-sign'),
          onPressed: checking || signed
              ? null
              : () async {
                  await checkDailySignStatus(context, toast: true);
                },
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            backgroundColor: colors.onSurface.withValues(alpha: .05),
            disabledBackgroundColor: colors.onSurface.withValues(alpha: .05),
            foregroundColor: statusColor,
            disabledForegroundColor: statusColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                  signed
                      ? Icons.check
                      : checking
                          ? Icons.sync
                          : Icons.check_circle_outline,
                  size: 17),
              const SizedBox(width: 5),
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          ),
        ),
        if (!signed) ...[
          const SizedBox(height: 4),
          Text(
            dailySignStatusLabel(context),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
          ),
        ],
      ],
    );
  }

  Widget _buildProfileDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(
        height: 1,
        color:
            Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .22),
      ),
    );
  }

  double get _experienceProgress {
    final raw = selfInfo.expPercent;
    final normalized = raw <= 1 ? raw : raw / 100;
    return normalized.isNaN ? 0 : normalized.clamp(0.0, 1.0).toDouble();
  }

  Widget _buildProfileStat({
    required String label,
    required String value,
    double? progress,
    Color? accent,
  }) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        const SizedBox(height: 5),
        Text(
          value,
          textAlign: TextAlign.center,
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
        ),
        if (progress != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
            color: accent,
            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: .12),
          ),
        ],
      ],
    );
  }

  Widget _buildProfileDetail(String label, String value) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelPainter = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final labelWidth = labelPainter.width.ceilToDouble();
        labelPainter.dispose();
        if (labelWidth + 8 + MediaQuery.textScalerOf(context).scale(32) >
            constraints.maxWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: style?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 3),
              Text(value,
                  style: style?.copyWith(color: theme.colorScheme.onSurface)),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(label,
                  style: style?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(value,
                  style: style?.copyWith(color: theme.colorScheme.onSurface)),
            ),
          ],
        );
      },
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
                    fontWeight: FontWeight.w400,
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
