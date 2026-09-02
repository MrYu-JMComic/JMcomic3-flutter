import 'package:flutter/material.dart';
import 'package:jmcomic3/configs/daily_sign.dart';
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/browser_screen.dart';
import 'package:jmcomic3/screens/comic_search_screen.dart';
import 'package:jmcomic3/screens/components/badge.dart';
import 'package:jmcomic3/screens/components/floating_search_bar.dart';
import 'package:jmcomic3/screens/user_screen.dart';

import 'components/comic_floating_search_bar.dart';

class AppScreen extends StatefulWidget {
  const AppScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _AppScreenState();
}

class _AppScreenState extends State<AppScreen> {
  final _searchBarController = FloatingSearchBarController();

  List<AppScreenData> _screens(BuildContext context) {
    final l10n = context.l10n;
    return [
      AppScreenData(
        BrowserScreenWrapper(searchBarController: _searchBarController),
        l10n.navBrowse,
        const Icon(Icons.menu_book_outlined),
        const Icon(Icons.menu_book),
      ),
      AppScreenData(
        const UserScreen(),
        l10n.navLibrary,
        const VersionBadged(child: Icon(Icons.image_outlined)),
        const VersionBadged(child: Icon(Icons.image)),
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () async {
      if (!mounted) return;
      versionPop(context);
      await checkDailySignStatus(context);
      if (!mounted) return;
      versionEvent.subscribe(_versionSub);
    });
  }

  @override
  void dispose() {
    versionEvent.unsubscribe(_versionSub);
    _pageController.dispose();
    super.dispose();
  }

  _versionSub(_) {
    versionPop(context);
  }

  var _selectedIndex = 0;
  late final _pageController = PageController(initialPage: 0);

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    final screens = _screens(context);
    return ComicFloatingSearchBarScreen(
      onQuery: (value) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) {
              return ComicSearchScreen(initKeywords: value);
            },
          ),
        );
      },
      controller: _searchBarController,
      child: Scaffold(
        body: PageView(
          physics: const NeverScrollableScrollPhysics(),
          allowImplicitScrolling: false,
          controller: _pageController,
          onPageChanged: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          children: screens.map((e) => e.screen).toList(),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(context),
      ),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final navTheme = NavigationBarTheme.of(context);
    final selectedColor = scheme.primary;
    final unselectedColor = scheme.onSurfaceVariant;

    return SafeArea(
      top: false,
      minimum: EdgeInsets.zero,
      child: Material(
        color: scheme.surface,
        elevation: 0,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .55),
                width: .8,
              ),
            ),
          ),
          child: NavigationBarTheme(
            data: navTheme.copyWith(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              indicatorColor: selectedColor.withValues(
                alpha: theme.brightness == Brightness.dark ? .22 : .12,
              ),
              elevation: 0,
              height: 60,
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? selectedColor : unselectedColor,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return IconThemeData(
                  size: selected ? 23 : 21,
                  color: selected ? selectedColor : unselectedColor,
                );
              }),
            ),
            child: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onItemTapped,
              destinations: _screens(context)
                  .map(
                    (e) => NavigationDestination(
                      icon: e.icon,
                      selectedIcon: e.activeIcon,
                      label: e.title,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class AppScreenData {
  final Widget screen;
  final String title;
  final Widget icon;
  final Widget activeIcon;

  const AppScreenData(this.screen, this.title, this.icon, this.activeIcon);
}
