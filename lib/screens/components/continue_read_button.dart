import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/my_flat_button.dart';

// 继续阅读按钮
class ContinueReadButton extends StatefulWidget {
  final Future<ViewLog?> viewFuture;
  final AlbumResponse album;
  final Function(int epOrder, int pictureRank) onChoose;

  const ContinueReadButton({
    Key? key,
    required this.album,
    required this.onChoose,
    required this.viewFuture,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ContinueReadButtonState();
}

class _ContinueReadButtonState extends State<ContinueReadButton> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: widget.viewFuture,
      builder: (BuildContext context, AsyncSnapshot<ViewLog?> snapshot) {
        late void Function() onPressed;
        late String text;
        if (snapshot.connectionState != ConnectionState.done) {
          onPressed = () {};
          text = context.l10n.loading;
        } else {
          ViewLog? viewLog = snapshot.data;
          if (viewLog == null || viewLog.lastViewChapterId == 0) {
            if (widget.album.series.isEmpty) {
              return Container();
            }
            onPressed = () {
              widget.onChoose(widget.album.initialReadableChapterId, 0);
            };
            text = context.l10n.tr('从头开始', en: 'Start from beginning');
          } else {
            onPressed = () {
              widget.onChoose(
                viewLog.lastViewChapterId,
                viewLog.lastViewPage,
              );
            };
            text = context.l10n.tr('继续阅读', en: 'Continue reading');
            if (widget.album.series.isNotEmpty) {
              for (var i = 0; i < widget.album.series.length; i++) {
                if (widget.album.series[i].id == viewLog.lastViewChapterId) {
                  text += " (${i + 1}.";
                  if (widget.album.series[i].name.isNotEmpty) {
                    text += widget.album.series[i].name + ".";
                  }
                  text += "P${viewLog.lastViewPage + 1})";
                  break;
                }
              }
            } else {
              text += " (P${viewLog.lastViewPage + 1})";
            }
          }
        }
        return MyFlatButton(title: text, onPressed: onPressed);
      },
    );
  }
}
