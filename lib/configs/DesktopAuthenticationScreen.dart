import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

const _key = "desktopAuthPassword";

Future<bool> needDesktopAuthentication() async {
  return await methods.loadProperty(_key) != "";
}

class VerifyPassword extends StatefulWidget {
  const VerifyPassword({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _VerifyPasswordState();
}

class _VerifyPasswordState extends State<VerifyPassword> {
  String _password = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              Expanded(child: Container()),
              TextField(
                decoration: InputDecoration(
                  labelText: context.l10n.tr("当前密码", en: "Current password"),
                ),
                onChanged: (value) {
                  _password = value;
                },
              ),
              Container(height: 10),
              ElevatedButton(
                onPressed: () async {
                  String savedPassword = await methods.loadProperty(_key);
                  if (_password == savedPassword) {
                    Navigator.of(context).pop(true);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.l10n.tr("密码错误", en: "Wrong password"),
                        ),
                      ),
                    );
                  }
                },
                child: Text(context.l10n.confirm),
              ),
              Expanded(child: Container()),
            ],
          ),
        ),
      ),
    );
  }
}

class SetPassword extends StatefulWidget {
  const SetPassword({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _SetPasswordState();
}

class _SetPasswordState extends State<SetPassword> {
  String _password = "";
  String _password2 = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              Text(
                context.l10n.tr("密码初始化", en: "Initialize password"),
                style: TextStyle(
                  height: 18,
                ),
              ),
              Container(
                height: 10,
              ),
              TextField(
                decoration: InputDecoration(
                  labelText: context.l10n.password,
                ),
                onChanged: (value) {
                  _password = value;
                },
              ),
              Container(
                height: 10,
              ),
              TextField(
                decoration: InputDecoration(
                  labelText:
                      context.l10n.tr("再次输入密码", en: "Enter password again"),
                ),
                onChanged: (value) {
                  _password2 = value;
                },
              ),
              Container(
                height: 10,
              ),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop(false);
                    },
                    child: Text(context.l10n.tr("取消", en: "Cancel")),
                  ),
                  Container(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (_password != _password2) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                context.l10n.tr(
                                  "两次输入的密码不一致",
                                  en: "The two passwords do not match",
                                ),
                              ),
                            ),
                          );
                          return;
                        }
                        await methods.saveProperty(_key, _password);
                        Navigator.of(context).pop(true);
                      },
                      child: Text(
                        context.l10n.tr("设置密码", en: "Set password"),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
