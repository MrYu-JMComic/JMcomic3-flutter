import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'bool_property.dart';
import 'is_pro.dart';

const _propertyName = "disableRecommendContent";
late bool _disableRecommendContent;
final disableRecommendContentEvent = Event();

Future<void> initDisableRecommendContent() async {
  _disableRecommendContent = parseBoolPropertyValue(
    await methods.loadProperty(_propertyName),
    fallback: false,
  );
  if (!hasProAccess) {
    _disableRecommendContent = false;
  }
}

bool currentDisableRecommendContent() {
  return _disableRecommendContent;
}

Widget disableRecommendContentSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return SwitchListTile(
        title: Text(
          context.l10n.tr("关闭推荐内容", en: "Disable recommended content") +
              (!hasProAccess
                  ? "\n${context.l10n.tr("(发电后使用)", en: "(Pro required)")}"
                  : ""),
          style: TextStyle(color: hasProAccess ? null : Colors.grey),
        ),
        subtitle: Text(
          _disableRecommendContent
              ? context.l10n.tr("已关闭", en: "Disabled")
              : context.l10n.tr("已开启", en: "Enabled"),
        ),
        value: _disableRecommendContent,
        onChanged: (value) async {
          if (!hasProAccess) {
            defaultToast(
              context,
              context.l10n.tr(
                "发电才能使用哦~",
                en: "Pro is required for this feature",
              ),
            );
            return;
          }
          await methods.saveProperty(_propertyName, "$value");
          _disableRecommendContent = value;
          disableRecommendContentEvent.broadcast();
          setState(() {});
        },
      );
    },
  );
}
