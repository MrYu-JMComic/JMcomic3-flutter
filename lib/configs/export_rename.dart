import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';
import 'bool_property.dart';
import 'is_pro.dart';

const _propertyName = 'exportRename';
late bool _exportRename;

Future<void> initExportRename() async {
  _exportRename = parseBoolPropertyValue(
    await methods.loadProperty(_propertyName),
    fallback: false,
  );
}

bool currentExportRename() {
  return _exportRename;
}

Future<void> _chooseExportRename(BuildContext context) async {
  final l10n = context.l10n;
  String? result = await chooseListDialog<String>(
    context,
    title: l10n.tr('导出时重命名', en: 'Rename on export'),
    values: [l10n.yes, l10n.no],
  );
  if (result != null) {
    var target = result == l10n.yes;
    await methods.saveProperty(_propertyName, '$target');
    _exportRename = target;
  }
}

Widget exportRenameSetting() {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        title: Text(
          context.l10n.tr('导出时重命名', en: 'Rename on export'),
          style: TextStyle(
            color: !hasProAccess ? Colors.grey : null,
          ),
        ),
        subtitle: Text(
          context.l10n.boolLabel(_exportRename),
          style: TextStyle(
            color: !hasProAccess ? Colors.grey : null,
          ),
        ),
        onTap: () async {
          if (!hasProAccess) {
            return;
          }
          await _chooseExportRename(context);
          setState(() {});
        },
      );
    },
  );
}
