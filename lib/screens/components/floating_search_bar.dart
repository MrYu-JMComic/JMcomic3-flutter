import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

class FloatingSearchBarScreen extends StatefulWidget {
  final FloatingSearchBarController controller;
  final Widget child;
  final ValueChanged<String>? onSubmitted;
  final String? hint;
  final bool showCursor;
  final bool autocorrect;
  final Widget? panel;

  const FloatingSearchBarScreen({
    required this.controller,
    required this.child,
    this.hint,
    this.showCursor = true,
    this.autocorrect = true,
    this.onSubmitted,
    this.panel,
    Key? key,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _FloatingSearchBarScreenState();
}

class _FloatingSearchBarScreenState extends State<FloatingSearchBarScreen>
    with SingleTickerProviderStateMixin {
  final _node = FocusNode();
  late final TextEditingController _textEditingController =
      TextEditingController();
  late final AnimationController _animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final _in = Tween(begin: 0.0, end: 1.0).animate(_animationController);

  @override
  void initState() {
    widget.controller._state = this;
    _animationController.addStatusListener(_onAnimationStatus);
    super.initState();
  }

  void _onAnimationStatus(AnimationStatus status) {
    // Add the overlay as opening starts and remove it after closing, including
    // when the controller is used without a search-history rebuild.
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant FloatingSearchBarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._state = null;
      widget.controller._state = this;
    }
  }

  @override
  void dispose() {
    widget.controller._state = null;
    _node.dispose();
    _textEditingController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          widget.child,
          ..._animationController.isDismissed
              ? []
              : [
                  _buildBackdrop(),
                  _buildSearchBar(),
                  _buildOnPop(),
                ],
        ],
      ),
    );
  }

  Widget _buildOnPop() {
    return WillPopScope(
      onWillPop: () async {
        if (_animationController.isDismissed) {
          return true;
        }
        _hideSearchBar();
        return false;
      },
      child: Container(),
    );
  }

  Widget _buildBackdrop() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return AnimatedBuilder(
          animation: _in,
          builder: (BuildContext context, Widget? child) {
            if (_in.value > 0) {
              return GestureDetector(
                onTap: () {
                  _hideSearchBar();
                },
                child: Container(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  color: Colors.black.withValues(alpha: .3 * _in.value),
                ),
              );
            }
            return Container();
          },
        );
      },
    );
  }

  Widget _buildSearchBar() {
    final mq = MediaQuery.of(context);
    double statusBarHeight = mq.padding.top;
    double finalHeight = 80 + statusBarHeight;
    return AnimatedBuilder(
      animation: _in,
      builder: (BuildContext context, Widget? child) {
        return SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: statusBarHeight),
                    child: Transform.translate(
                      offset:
                          Offset(0, (_in.value * finalHeight) - finalHeight),
                      child: Column(
                        children: [
                          _SearchBarContainer(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: MaterialLocalizations.of(context)
                                      .backButtonTooltip,
                                  onPressed: _hideSearchBar,
                                  icon: const Icon(Icons.arrow_back),
                                ),
                                Expanded(child: _buildTextField()),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ...(widget.panel == null
                      ? []
                      : [
                          Expanded(
                            child: Transform.translate(
                              offset: Offset(
                                (_in.value * mq.size.width) - mq.size.width,
                                0,
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(
                                  top: 5,
                                  left: 10,
                                  right: 10,
                                  bottom: 15,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                  ),
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: widget.panel,
                              ),
                            ),
                          ),
                        ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextField() {
    return TextField(
      controller: _textEditingController,
      showCursor: widget.showCursor,
      scrollPadding: EdgeInsets.zero,
      scrollPhysics: const NeverScrollableScrollPhysics(),
      focusNode: _node,
      maxLines: 1,
      autofocus: false,
      autocorrect: widget.autocorrect,
      textInputAction: TextInputAction.search,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint ?? context.l10n.tr("搜索", en: "Search"),
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        errorBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        fillColor: Colors.transparent,
      ),
    );
  }

  void _displayFloatingSearchBar({String? modifyInput}) {
    if (modifyInput != null) {
      _textEditingController.text = modifyInput;
    }
    _node.requestFocus();
    _animationController.forward();
  }

  void _hideSearchBar() {
    _node.unfocus();
    _animationController.reverse();
  }
}

class _SearchBarContainer extends StatelessWidget {
  final Widget child;

  const _SearchBarContainer({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

class FloatingSearchBarController {
  _FloatingSearchBarScreenState? _state;

  void hide() => _state?._hideSearchBar();

  void display({String? modifyInput}) =>
      _state?._displayFloatingSearchBar(modifyInput: modifyInput);
}
