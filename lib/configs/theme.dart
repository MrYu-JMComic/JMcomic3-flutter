import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/log.dart';
import '../basic/methods.dart';
import '../basic/reader_system_ui.dart';
import 'string_property.dart';

const _seedColor = Color(0xFFECEFF2);

final ColorScheme _lightColorScheme = ColorScheme.fromSeed(
  seedColor: _seedColor,
  brightness: Brightness.light,
);

final ColorScheme _darkColorScheme = ColorScheme.fromSeed(
  seedColor: _seedColor,
  brightness: Brightness.dark,
);

final ThemeData _lightTheme =
    _buildAppTheme(_lightColorScheme, Brightness.light);
final ThemeData _darkTheme = _buildAppTheme(_darkColorScheme, Brightness.dark);

ThemeData get lightTheme => theme != "2" ? _lightTheme : _darkTheme;

ThemeData get darkTheme => theme != "1" ? _darkTheme : _lightTheme;

const _propertyName = "theme";
late String theme = "0";

/// 归一化本地持久化的主题配置。
///
/// 旧缓存和手工脚本可能保存 `auto/light/dark`、大小写混合文本或 JSON 字符串包装；
/// 初始化时统一收敛到现有协议的 `0/1/2`，避免设置页显示 `-` 或状态栏颜色误判。
String normalizeThemeCode(String raw) {
  final value = parseStringPropertyValue(raw, trim: true).toLowerCase();
  switch (value) {
    case "0":
    case "auto":
    case "system":
      return "0";
    case "1":
    case "light":
      return "1";
    case "2":
    case "dark":
      return "2";
    default:
      return "0";
  }
}

Map<String, String> _nameMap(BuildContext context) {
  return {
    "0": context.l10n.tr("自动 (如果设备支持)", en: "Auto (if supported)"),
    "1": context.l10n.tr("保持亮色", en: "Always light"),
    "2": context.l10n.tr("保持暗色", en: "Always dark"),
  };
}

ThemeData _buildAppTheme(ColorScheme scheme, Brightness brightness) {
  final typography = Typography.material2021();
  final baseTextTheme =
      brightness == Brightness.light ? typography.black : typography.white;
  final textTheme = _buildTextTheme(baseTextTheme, scheme);
  final overlayStyle = brightness == Brightness.dark
      ? const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemStatusBarContrastEnforced: false,
        )
      : const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
        );
  final navLabelStyle = (textTheme.labelMedium ??
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))
      .copyWith(fontSize: 11, fontWeight: FontWeight.w500);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    typography: typography,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    scaffoldBackgroundColor: scheme.background,
    dialogBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      systemOverlayStyle: overlayStyle,
      toolbarHeight: 48,
      centerTitle: false,
      titleTextStyle:
          textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    bottomAppBarTheme: BottomAppBarThemeData(
      color: scheme.surface,
      elevation: 1,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      elevation: 2,
      height: 56,
      labelTextStyle: MaterialStatePropertyAll(navLabelStyle),
      iconTheme: MaterialStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(MaterialState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.onSurface,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelStyle:
          textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w400),
    ),
    splashFactory: InkRipple.splashFactory,
    splashColor: scheme.primary.withOpacity(.12),
    highlightColor: scheme.primary.withOpacity(.06),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 4,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle:
          textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
      contentTextStyle: textTheme.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.surfaceVariant,
      contentTextStyle: textTheme.bodyMedium
          ?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w400),
      behavior: SnackBarBehavior.floating,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary),
      ),
      labelStyle:
          textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: MaterialStatePropertyAll(scheme.secondary),
        foregroundColor: MaterialStatePropertyAll(scheme.onSecondary),
        shape: MaterialStatePropertyAll<RoundedRectangleBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        textStyle: MaterialStatePropertyAll(
          (textTheme.labelLarge ?? const TextStyle(fontWeight: FontWeight.w500))
              .copyWith(fontWeight: FontWeight.w500),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: MaterialStatePropertyAll(scheme.primary),
        foregroundColor: MaterialStatePropertyAll(scheme.onPrimary),
        shape: MaterialStatePropertyAll<RoundedRectangleBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        textStyle: MaterialStatePropertyAll(
          (textTheme.labelLarge ?? const TextStyle(fontWeight: FontWeight.w500))
              .copyWith(fontWeight: FontWeight.w500),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: MaterialStatePropertyAll(scheme.primary),
        shape: MaterialStatePropertyAll<RoundedRectangleBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        overlayColor: MaterialStatePropertyAll(scheme.primary.withOpacity(.12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: MaterialStatePropertyAll(scheme.primary),
        textStyle: MaterialStatePropertyAll(
          textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceVariant,
      selectedColor: scheme.secondaryContainer,
      secondarySelectedColor: scheme.primaryContainer,
      labelStyle: textTheme.bodyMedium,
      secondaryLabelStyle:
          textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.onSurface.withOpacity(.2),
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withOpacity(.16),
      trackHeight: 3,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStatePropertyAll(scheme.primary),
      trackColor: MaterialStatePropertyAll(scheme.primary.withOpacity(.5)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: MaterialStatePropertyAll(scheme.primary),
      checkColor: MaterialStatePropertyAll(scheme.onPrimary),
    ),
    radioTheme: RadioThemeData(
      fillColor: MaterialStatePropertyAll(scheme.primary),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 0.8,
    ),
  );
}

TextTheme _buildTextTheme(TextTheme base, ColorScheme scheme) {
  return base.copyWith(
    titleLarge: (base.titleLarge ?? const TextStyle()).copyWith(
      fontSize: 21,
      fontWeight: FontWeight.w600,
      height: 1.2,
      color: scheme.onSurface,
    ),
    titleMedium: (base.titleMedium ?? const TextStyle()).copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w500,
      height: 1.25,
      color: scheme.onSurface,
    ),
    titleSmall: (base.titleSmall ?? const TextStyle()).copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.3,
      color: scheme.onSurface,
    ),
    bodyLarge: (base.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: scheme.onSurface,
    ),
    bodyMedium: (base.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: scheme.onSurface,
    ),
    bodySmall: (base.bodySmall ?? const TextStyle()).copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.35,
      color: scheme.onSurfaceVariant,
    ),
    labelLarge: (base.labelLarge ?? const TextStyle()).copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.2,
      color: scheme.onSurface,
    ),
    labelMedium: (base.labelMedium ?? const TextStyle()).copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.2,
      color: scheme.onSurfaceVariant,
    ),
    labelSmall: (base.labelSmall ?? const TextStyle()).copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      height: 1.2,
      color: scheme.onSurfaceVariant,
    ),
  );
}

Future initTheme() async {
  try {
    // System UI is an optional platform capability. A desktop/web embedder
    // may not implement the channel; initialization must still continue with
    // the selected theme instead of redirecting the whole app to an error
    // screen.
    await setTrackedSystemUiMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
  } catch (error, stackTrace) {
    debugPrient(
      'system-ui initialization unavailable: '
      '${error.runtimeType}/${stackTrace.runtimeType}',
    );
  }
  theme = normalizeThemeCode(await methods.loadProperty(_propertyName));
  themeEvent.broadcast();
  _reloadBarColor();
}

String themeName(BuildContext context) {
  return _nameMap(context)[theme] ?? "-";
}

Future chooseTheme(BuildContext context) async {
  final nameMap = _nameMap(context);
  String? choose = await chooseMapDialog(context,
      title: context.l10n.tr("选择主题", en: "Choose theme"),
      values: nameMap.map((key, value) => MapEntry(value, key)));
  if (choose != null) {
    await methods.saveProperty(_propertyName, choose);
    theme = choose;
    themeEvent.broadcast();
    _reloadBarColor();
  }
}

void reloadBarColor({bool op = false}) {
  _reloadBarColor(op: op);
}

void _reloadBarColor({bool op = false}) {
  final isDark = theme == "2" ||
      (theme == "0" &&
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark);
  final navigationColor = op
      ? Colors.transparent
      : isDark
          ? Colors.black87
          : Colors.white;
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: navigationColor,
    systemNavigationBarIconBrightness:
        isDark ? Brightness.light : Brightness.dark,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  ));
}

final themeEvent = Event();

Widget themeSetting(BuildContext context) {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        onTap: () async {
          await chooseTheme(context);
          setState(() => {});
        },
        title: Text(context.l10n.tr("主题", en: "Theme")),
        subtitle: Text(themeName(context)),
      );
    },
  );
}
