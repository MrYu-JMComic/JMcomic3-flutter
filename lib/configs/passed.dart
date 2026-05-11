/// 自动全屏

import '../basic/methods.dart';
import 'bool_property.dart';

const _propertyName = "passed";
late bool _passed;

Future<void> initPassed() async {
  _passed = parseBoolPropertyValue(
    await methods.loadProperty(_propertyName),
    fallback: false,
  );
}

bool currentPassed() {
  return _passed;
}

Future<void> firstPassed() async {
  await methods.saveProperty(_propertyName, "true");
}
