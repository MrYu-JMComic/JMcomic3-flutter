import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/Authentication.dart';
import 'package:jmcomic3/configs/configs.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../basic/web_dav_sync.dart';
import '../configs/passed.dart';
import 'app_screen.dart';
import 'first_login_screen.dart';
import 'network_setting_screen.dart';

class InitScreen extends StatefulWidget {
  const InitScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _InitScreenState();
}

class _InitScreenState extends State<InitScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return Center(child: Text(context.l10n.initializing));
        },
      ),
    );
  }

  Future _init() async {
    try {
      await methods.init();
      await initConfigs(context);
      if (!mounted) return;
      debugPrient("STATE : ${loginStatus}");
      if (!currentPassed()) {
        await firstPassed();
        if (!mounted) return;
      }
      if (currentAuthentication()) {
        Future.delayed(Duration.zero, () async {
          if (!mounted) return;
          await webDavSyncAuto(context);
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (BuildContext context) {
                return const AuthScreen();
              },
            ),
          );
        });
      } else if (loginStatus == LoginStatus.notSet) {
        Future.delayed(Duration.zero, () async {
          if (!mounted) return;
          await webDavSyncAuto(context);
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (BuildContext context) {
                return firstLoginScreen;
              },
            ),
          );
        });
      } else {
        Future.delayed(Duration.zero, () async {
          if (!mounted) return;
          await webDavSyncAuto(context);
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (BuildContext context) {
                return const AppScreen();
              },
            ),
          );
        });
      }
    } catch (e, st) {
      debugPrient("$e\n$st");
      if (!mounted) return;
      defaultToast(context, context.l10n.initFailedSetNetwork);
      Future.delayed(Duration.zero, () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return const NetworkSettingScreen();
            },
          ),
        );
      });
    }
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () {
      test();
    });
  }

  test() async {
    if (await verifyAuthentication(context)) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return const AppScreen();
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.authTitle)),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: MaterialButton(
            onPressed: () async {
              test();
            },
            child: Text(context.l10n.authPrompt),
          ),
        ),
      ),
    );
  }
}
