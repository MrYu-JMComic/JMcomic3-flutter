part of '../comic_reader_screen.dart';

class _EpChooser extends StatefulWidget {
  final ChapterResponse chapter;
  final FutureOr Function(int, bool) onChangeEp;
  final List<Series>? series;

  const _EpChooser(this.chapter, this.onChangeEp, {this.series});

  @override
  State<StatefulWidget> createState() => _EpChooserState();
}

class _EpChooserState extends State<_EpChooser> {
  bool _selectionInFlight = false;

  Future<void> _selectChapter(int id) async {
    if (_selectionInFlight || !mounted) {
      return;
    }
    _selectionInFlight = true;
    try {
      if (mounted) {
        Navigator.of(context).pop();
      }
      await Future<void>.sync(() => widget.onChangeEp(id, false));
    } catch (error, stackTrace) {
      debugPrient(
          "chapter selection failed: ${error.runtimeType}/${stackTrace.runtimeType}");
    } finally {
      _selectionInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series ?? widget.chapter.series;
    if (series.isEmpty) {
      return Center(
        child: Text(
          context.l10n.tr("无章节可选择", en: "No chapters available"),
          style: const TextStyle(color: Colors.white),
        ),
      );
    }

    var entries = _sortReaderSeries(series);
    var widgets = [
      Container(height: 20),
      ...entries.map((e) {
        return Container(
          margin: const EdgeInsets.only(left: 15, right: 15, top: 5, bottom: 5),
          decoration: BoxDecoration(
            color:
                widget.chapter.id == e.id ? Colors.grey.withAlpha(100) : null,
            border: Border.all(
              color: const Color(0xff484c60),
              style: BorderStyle.solid,
              width: .5,
            ),
          ),
          child: MaterialButton(
            onPressed: _selectionInFlight
                ? null
                : () => unawaited(_selectChapter(e.id)),
            textColor: Colors.white,
            child: Text(e.sort + (e.name == "" ? "" : (" - ${e.name}"))),
          ),
        );
      })
    ];
    final index = entries.map((e) => e.id).toList().indexOf(widget.chapter.id);
    return zoomable.ZoomablePositionedList.builder(
      enableZoom: false,
      initialScrollIndex: index < 2 ? 0 : index - 2,
      itemCount: widgets.length,
      itemBuilder: (BuildContext context, int index) => widgets[index],
    );
  }
}

class _SettingPanel extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _SettingPanelState();
}

class _SettingPanelState extends State<_SettingPanel> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Row(
          children: [
            _bottomIcon(
              icon: Icons.crop_sharp,
              title: readerDirectionName(currentReaderDirection, context),
              onPressed: () async {
                await chooseReaderDirection(context);
                if (mounted) setState(() {});
              },
            ),
            _bottomIcon(
              icon: Icons.view_day_outlined,
              title: readerTypeName(currentReaderType, context),
              onPressed: () async {
                await chooseReaderType(context);
                if (mounted) setState(() {});
              },
            ),
            _bottomIcon(
              icon: Icons.control_camera_outlined,
              title: currentReaderControllerTypeName(context),
              onPressed: () async {
                await chooseReaderControllerType(context);
                if (mounted) setState(() {});
              },
            ),
            _bottomIcon(
              icon: Icons.straighten_sharp,
              title: currentReaderSliderPositionName(context),
              onPressed: () async {
                await chooseReaderSliderPosition(context);
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _bottomIcon({
    required IconData icon,
    required String title,
    required void Function() onPressed,
  }) {
    return Expanded(
      child: Center(
        child: Column(
          children: [
            IconButton(
              iconSize: 55,
              icon: Column(
                children: [
                  Container(height: 3),
                  Icon(
                    icon,
                    size: 25,
                    color: Colors.white,
                  ),
                  Container(height: 3),
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                  ),
                  Container(height: 3),
                ],
              ),
              onPressed: onPressed,
            )
          ],
        ),
      ),
    );
  }
}
