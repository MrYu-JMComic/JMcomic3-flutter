import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/bool_property.dart';
import 'package:jmcomic3/configs/is_pro.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

enum LoginStatus {
  notSet,
  logging,
  loginField,
  loginSuccess,
  guest,
}

late SelfInfo _selfInfo;
LoginStatus _status = LoginStatus.notSet;
String _loginMessage = "";
const _guestModePropertyName = "guest_mode";
bool _guestMode = false;
final Event _event = Event();

SelfInfo get selfInfo => _selfInfo;

Event get loginEvent => _event;

LoginStatus get loginStatus => _status;

String get loginMessage => _loginMessage;

bool get hasJwtAccess => _status == LoginStatus.loginSuccess;

bool get isGuestMode => _status == LoginStatus.guest;

set _loginState(LoginStatus value) {
  _status = value;
  _event.broadcast();
}

Future initLogin(BuildContext context) async {
  try {
    _guestMode = parseBoolPropertyValue(
      await methods.loadProperty(_guestModePropertyName),
      fallback: false,
    );
    _loginState = LoginStatus.logging;
    final preLogin = await methods.preLogin();
    _loginMessage = preLogin.message ?? "";
    if (!preLogin.preSet) {
      _loginState = _guestMode ? LoginStatus.guest : LoginStatus.notSet;
    } else if (preLogin.preLogin) {
      _guestMode = false;
      await methods.saveProperty(_guestModePropertyName, "false");
      _selfInfo = preLogin.selfInfo!;
      _loginState = LoginStatus.loginSuccess;
      fav(context);
    } else {
      _loginState = _guestMode ? LoginStatus.guest : LoginStatus.loginField;
    }
  } catch (e, st) {
    debugPrient("$e\n$st");
    _loginState = _guestMode ? LoginStatus.guest : LoginStatus.loginField;
  } finally {
    reloadIsPro();
  }
}

List<FavoriteFolderItem> favData = [];

Widget createFavoriteFolderItemTile(BuildContext context) {
  return ListTile(
    title: Text(context.l10n.tr("创建收藏文件夹", en: "Create favorites folder")),
    onTap: () async {
      if (!await ensureJwtAccess(
        context,
        feature: context.l10n.tr("创建收藏夹", en: "Create favorites folder"),
      )) {
        return;
      }
      var name = await displayTextInputDialog(
        context,
        title: context.l10n.tr("创建收藏文件夹", en: "Create favorites folder"),
        hint: context.l10n.tr("文件夹名称", en: "Folder name"),
      );
      if (name == null) {
        return;
      }
      await methods.createFavoriteFolder(name);
      fav(context);
      defaultToast(
          context, context.l10n.tr("创建成功", en: "Created successfully"));
    },
  );
}

Widget deleteFavoriteFolderItemTile(BuildContext context) {
  return ListTile(
    title: Text(context.l10n.tr("删除收藏文件夹", en: "Delete favorites folder")),
    onTap: () async {
      if (!await ensureJwtAccess(
        context,
        feature: context.l10n.tr("删除收藏夹", en: "Delete favorites folder"),
      )) {
        return;
      }
      var j = favData.map((i) {
        return MapEntry(i.name, i.fid);
      }).toList();
      j.add(MapEntry(context.l10n.tr("默认 / 不删除", en: "Default / Keep"), 0));
      var v = await chooseMapDialog<int>(
        context,
        title: context.l10n.tr("删除资料夹", en: "Delete folder"),
        values: Map.fromEntries(j),
      );
      if (v != null && v != 0) {
        await methods.deleteFavoriteFolder(v);
        fav(context);
        defaultToast(
            context, context.l10n.tr("删除成功", en: "Deleted successfully"));
      }
    },
  );
}

Widget renameFavoriteFolderItemTile(BuildContext context) {
  return ListTile(
    title: Text(context.l10n.tr("重命名收藏文件夹", en: "Rename favorites folder")),
    onTap: () async {
      if (!await ensureJwtAccess(
        context,
        feature: context.l10n.tr("重命名收藏夹", en: "Rename favorites folder"),
      )) {
        return;
      }
      var j = favData.map((i) {
        return MapEntry(i.name, i.fid);
      }).toList();
      j.add(MapEntry(context.l10n.tr("默认 / 不重命名", en: "Default / Keep"), 0));
      var v = await chooseMapDialog<int>(
        context,
        title: context.l10n.tr("重命名资料夹", en: "Rename folder"),
        values: Map.fromEntries(j),
      );
      if (v != null && v != 0) {
        var name = await displayTextInputDialog(
          context,
          title: context.l10n.tr("重命名收藏文件夹", en: "Rename favorites folder"),
          hint: context.l10n.tr("文件夹名称", en: "Folder name"),
        );
        if (name == null) {
          return;
        }
        await methods.renameFavoriteFolder(v, name);
        fav(context);
        defaultToast(
            context, context.l10n.tr("重命名成功", en: "Renamed successfully"));
      }
    },
  );
}

Future fav(BuildContext buildContext) async {
  try {
    favData = (await methods.favorite()).folderList;
  } catch (e, st) {
    debugPrient("$e\n$st");
    defaultToast(buildContext, "$e");
  }
}

Future login(String username, String password, BuildContext context) async {
  try {
    _loginState = LoginStatus.logging;
    final selfInfo = await methods.login(username, password);
    _guestMode = false;
    await methods.saveProperty(_guestModePropertyName, "false");
    _selfInfo = selfInfo;
    _loginState = LoginStatus.loginSuccess;
    fav(context);
  } catch (e, st) {
    debugPrient("$e\n$st");
    _loginState = LoginStatus.loginField;
    _loginMessage = "$e";
  }
}

Future<void> enterGuestMode() async {
  _guestMode = true;
  await methods.saveProperty(_guestModePropertyName, "true");
  _loginMessage = "";
  _loginState = LoginStatus.guest;
}

Future<bool> ensureJwtAccess(
  BuildContext context, {
  String? feature,
}) async {
  if (hasJwtAccess) {
    return true;
  }
  final shouldLogin = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      final l10n = context.l10n;
      final targetFeature = feature ?? l10n.tr("该功能", en: "This feature");
      return AlertDialog(
        title: Text(l10n.tr("登录提醒", en: "Login required")),
        content: Text(
          isGuestMode
              ? l10n.tr("当前是游客模式，$targetFeature 需要登录后才能使用。",
                  en: "Guest mode is active. $targetFeature requires login.")
              : l10n.tr("$targetFeature 需要登录后才能使用。",
                  en: "$targetFeature requires login."),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: Text(l10n.tr("取消", en: "Cancel")),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: Text(l10n.tr("去登录", en: "Go login")),
          ),
        ],
      );
    },
  );
  if (shouldLogin == true) {
    await loginDialog(context);
  }
  return hasJwtAccess;
}

Future loginDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (BuildContext context) {
      return Container(
        width: 30,
        height: 30,
        color: Colors.black.withOpacity(.1),
        child: Center(
          child: _LoginDialog(),
        ),
      );
    },
  );
}

Future showLoginAgreementBottomSheet(BuildContext context) async {
  await showMaterialModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xAA000000),
    builder: (context) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * (.6),
        child: const _LoginAgreementSheet(),
      );
    },
  );
}

Future showUserAgreementBottomSheet(BuildContext context) {
  return showLoginAgreementBottomSheet(context);
}

Widget userAgreementSetting(BuildContext context) {
  return ListTile(
    onTap: () => showUserAgreementBottomSheet(context),
    title: Text(context.l10n.tr("用户协议", en: "User agreement")),
    subtitle:
        Text(context.l10n.tr("查看当前应用使用协议", en: "View current app agreement")),
  );
}

class LoginAgreementHint extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const LoginAgreementHint({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 8),
  });

  @override
  Widget build(BuildContext context) {
    final agreeStyle = Theme.of(context).textTheme.bodyMedium
        //        ?.copyWith(color: Colors.grey)
        ;
    final agreeLinkStyle = agreeStyle?.copyWith(
      decoration: TextDecoration.underline,
      // decorationColor: Colors.grey.shade600,
      // color: Colors.grey.shade600,
    );
    return Padding(
      padding: padding,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(context.l10n.tr("登录即为同意 ", en: "By logging in you agree to "),
              style: agreeStyle),
          InkWell(
            onTap: () => showLoginAgreementBottomSheet(context),
            child: Text(context.l10n.tr("使用协议", en: "Terms of use"),
                style: agreeLinkStyle),
          ),
        ],
      ),
    );
  }
}

class _LoginAgreementSheet extends StatelessWidget {
  const _LoginAgreementSheet();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bodyStyle = textTheme.bodyMedium;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
                Expanded(
                  child: Text(
                    context.l10n.tr("使用协议", en: "Terms of use"),
                    style: textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  Text(
                    context.l10n.tr(
                      "继续登录/使用即表示您已阅读并同意以下内容：",
                      en: "By continuing to login/use, you acknowledge and agree to:",
                    ),
                    style: bodyStyle,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.tr(
                      "1. 为保障安全与改进服务，您的登录、浏览、搜索、下载等操作记录（含必要的设备与网络信息）可能会被供应商或服务器保存与分析。",
                      en: "1. To ensure security and improve services, your login, browsing, search, and download records (including necessary device/network info) may be stored and analyzed by providers or servers.",
                    ),
                    style: bodyStyle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.tr(
                      "2. 请勿上传、传播或利用本服务从事任何违法违规行为；如涉及敏感内容，请自行审慎判断并遵守当地法律法规。；因此产生的后果由您自行承担。",
                      en: "2. Do not upload, spread, or use this service for illegal activities. For sensitive content, use your own judgment and comply with local laws and regulations. You are responsible for all consequences.",
                    ),
                    style: bodyStyle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.tr(
                      "3. 本应用展示的任何信息仅供参考与交流，不构成医疗/诊断/治疗建议；因此产生的后果（含生理、病理等）由您自行承担。",
                      en: "3. Any information shown in this app is for reference and communication only, and does not constitute medical/diagnostic/treatment advice. You are responsible for any resulting consequences.",
                    ),
                    style: bodyStyle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.tr(
                      "4. 我们可能在必要时更新协议内容；更新后继续使用视为您接受更新。",
                      en: "4. We may update these terms when necessary. Continuing to use the app after updates means you accept the changes.",
                    ),
                    style: bodyStyle,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.tr(
                      "* 若您不同意上述条款，请停止登录并退出使用。",
                      en: "* If you do not agree with the terms above, please stop logging in and exit the app.",
                    ),
                    // style: captionStyle,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: MaterialButton(
                  color: Colors.orange.shade700,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      context.l10n.tr("我知道了", en: "Got it"),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginDialog extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  var _username = "";
  var _password = "";

  @override
  void initState() {
    Future.delayed(Duration.zero, () async {
      final username = await methods.loadUsername();
      final password = await methods.loadPassword();
      setState(() {
        _username = username;
        _password = password;
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      width: MediaQuery.of(context).size.width - 90,
      margin: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: Material(
        color: Colors.transparent,
        child: ListView(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(child: Container()),
              ],
            ),
            ListTile(
              title: Text(context.l10n.account),
              subtitle: Text(
                _username == ""
                    ? context.l10n.tr("未设置", en: "Not set")
                    : _username,
              ),
              onTap: () async {
                String? input = await displayTextInputDialog(
                  context,
                  src: _username,
                  title: context.l10n.account,
                  hint: context.l10n.inputAccount,
                );
                if (input != null) {
                  setState(() {
                    _username = input;
                  });
                }
              },
            ),
            ListTile(
              title: Text(context.l10n.password),
              subtitle: Text(
                _password == ""
                    ? context.l10n.tr("未设置", en: "Not set")
                    : '\u2022' * 10,
              ),
              onTap: () async {
                String? input = await displayTextInputDialog(
                  context,
                  src: _password,
                  title: context.l10n.password,
                  hint: context.l10n.inputPassword,
                  isPasswd: true,
                );
                if (input != null) {
                  setState(() {
                    _password = input;
                  });
                }
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  margin: const EdgeInsets.all(10),
                  child: TextButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await enterGuestMode();
                      await reloadIsPro();
                    },
                    child: Text(context.l10n.guestMode),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(10),
                  child: MaterialButton(
                    color: Colors.orange.shade700,
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await login(_username, _password, context);
                      await reloadIsPro();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        context.l10n.tr("保存", en: "Save"),
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
