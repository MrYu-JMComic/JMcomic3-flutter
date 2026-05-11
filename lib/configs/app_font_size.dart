import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/methods.dart';
import 'int_property.dart';

enum FontSizeAdjustType {
  fontSizeAdjustCommentContent,
}

const int _fontSizeAdjustMin = -5;
const int _fontSizeAdjustMax = 5;

final valueMap = {
  FontSizeAdjustType.fontSizeAdjustCommentContent: 0,
};

Future<void> initFontSizeAdjust() async {
  for (var key in valueMap.keys) {
    final raw = await methods.loadProperty(key.toString());
    valueMap[key] = _parseFontSizeAdjust(raw);
  }
}

int currentFontSizeAdjust(FontSizeAdjustType type) {
  return valueMap[type]!;
}

int _parseFontSizeAdjust(String raw) {
  // 本地属性来自旧版本缓存/手工迁移，初始化阶段必须兜底，避免设置页因单个脏值崩溃。
  return parseBoundedIntPropertyValue(
    raw,
    fallback: 0,
    min: _fontSizeAdjustMin,
    max: _fontSizeAdjustMax,
  );
}

List<Widget> fontSizeAdjustSettings() {
  return [
    for (var key in valueMap.keys) fontSizeAdjustSetting(key),
  ];
}

String _fontSizeAdjustTypeName(FontSizeAdjustType type, BuildContext context) {
  switch (type) {
    case FontSizeAdjustType.fontSizeAdjustCommentContent:
      return context.l10n.tr("评论", en: "Comments");
  }
}

Widget fontSizeAdjustSetting(FontSizeAdjustType type) {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text(
          context.l10n.tr("文字大小调整", en: "Text size adjustment") +
              " - ${_fontSizeAdjustTypeName(type, context)}",
        ),
        subtitle: Slider(
          value: valueMap[type]!.toDouble(), // 当前值
          min: _fontSizeAdjustMin.toDouble(), // 最小值
          max: _fontSizeAdjustMax.toDouble(), // 最大值
          divisions: 10, // 分成 10 等分（-5 到 5）
          label: valueMap[type].toString(), // 显示滑块标签
          onChanged: (value) {
            setState(() {
              valueMap[type] = value.toInt(); // 更新当前值
            });
            methods.saveProperty(
                type.toString(), value.toInt().toString()); // 保存当前值
          },
        ),
        trailing: Text(
          valueMap[type].toString(), // 显示当前值
          style: const TextStyle(fontSize: 16),
        ),
      );
    },
  );
}
