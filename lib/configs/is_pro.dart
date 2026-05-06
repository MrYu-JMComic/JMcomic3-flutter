import 'package:event/event.dart';
import '../basic/methods.dart';

const _permanentProExpire = 4102444800; // 2100-01-01 00:00:00 UTC

var isPro = true;
var isProEx = _permanentProExpire;

bool get hasProAccess => isPro;

ProInfoAf? _proInfoAf =
    ProInfoAf.fromJson({"is_pro": true, "expire": _permanentProExpire});
ProInfoPat? _proInfoPat = ProInfoPat.fromJson({
  "is_pro": true,
  "pat_id": "",
  "bind_uid": "",
  "request_delete": 0,
  "re_bind": 0,
  "error_type": 0,
  "error_msg": "",
  "access_key": "",
});

ProInfoAf get proInfoAf =>
    _proInfoAf ??
    ProInfoAf.fromJson({"is_pro": true, "expire": _permanentProExpire});
ProInfoPat get proInfoPat =>
    _proInfoPat ??
    ProInfoPat.fromJson({
      "is_pro": true,
      "pat_id": "",
      "bind_uid": "",
      "request_delete": 0,
      "re_bind": 0,
      "error_type": 0,
      "error_msg": "",
      "access_key": "",
    });

final proEvent = Event();

Future reloadIsPro() async {
  // Always keep Pro enabled locally; backend state is optional.
  try {
    final proInfoAll = await methods.proInfoAll();
    _proInfoAf = proInfoAll.proInfoAf;
    _proInfoPat = proInfoAll.proInfoPat;
  } catch (_) {}

  isPro = true;
  isProEx = _permanentProExpire;
  _proInfoAf =
      ProInfoAf.fromJson({"is_pro": true, "expire": _permanentProExpire});
  _proInfoPat = ProInfoPat.fromJson({
    "is_pro": true,
    "pat_id": _proInfoPat?.patId ?? "",
    "bind_uid": _proInfoPat?.bindUid ?? "",
    "request_delete": _proInfoPat?.requestDelete ?? 0,
    "re_bind": _proInfoPat?.reBind ?? 0,
    "error_type": _proInfoPat?.errorType ?? 0,
    "error_msg": _proInfoPat?.errorMsg ?? "",
    "access_key": _proInfoPat?.accessKey ?? "",
  });

  proEvent.broadcast();
}

Future<bool> ensureProAccess() async {
  return true;
}
