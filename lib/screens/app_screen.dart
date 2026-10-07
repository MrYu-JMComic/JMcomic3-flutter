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
      versionPop(context);
      await checkDailySignStatus(context);
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
    _pageController.jumpToPage(
      index,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = _screens(context);
    final isWideLayout = MediaQuery.sizeOf(context).width >= 700;
    final pageView = PageView(
      physics: const NeverScrollableScrollPhysics(),
      allowImplicitScrolling: false,
      controller: _pageController,
      onPageChanged: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      children: screens.map((e) => e.screen).toList(),
    );

    return ComicFloatingSearchBarScreen(
      onQuery: (value) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) {
          return ComicSearchScreen(initKeywords: value);
        }));
      },
      controller: _searchBarController,
      child: Scaffold(
        body: isWideLayout
            ? Row(
                children: [
                  SafeArea(
                    top: true,
                    bottom: true,
                    child: _buildNavigationRail(context, screens),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: pageView),
                ],
              )
            : pageView,
        bottomNavigationBar:
            isWideLayout ? null : _buildBottomNavigationBar(context, screens),
      ),
    );
  }

  Widget _buildNavigationRail(
      BuildContext context, List<AppScreenData> screens) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final navTheme = NavigationRailTheme.of(context);
    return NavigationRailTheme(
      data: navTheme.copyWith(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(
          alpha: theme.brightness == Brightness.dark ? .22 : .12,
        ),
        selectedIconTheme: IconThemeData(color: scheme.primary, size: 24),
        unselectedIconTheme:
            IconThemeData(color: scheme.onSurfaceVariant, size: 22),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: NavigationRail(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        labelType: NavigationRailLabelType.all,
        groupAlignment: -0.65,
        minWidth: 76,
        destinations: screens
            .map((e) => NavigationRailDestination(
                  icon: e.icon,
                  selectedIcon: e.activeIcon,
                  label: Text(e.title),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildBottomNavigationBar(
      BuildContext context, List<AppScreenData> screens) {
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
              destinations: screens
                  .map((e) => NavigationDestination(
                        icon: e.icon,
                        selectedIcon: e.activeIcon,
                        label: e.title,
                      ))
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
