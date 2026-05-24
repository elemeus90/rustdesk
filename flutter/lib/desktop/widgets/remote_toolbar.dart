import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/plugin/widgets/desc_ui.dart';
import 'package:flutter_hbb/plugin/common.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:debounce_throttle/debounce_throttle.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_size/window_size.dart' as window_size;

import '../../common.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../common/shared_state.dart';
import './popup_menu.dart';
import './kb_layout_type_chooser.dart';
import 'package:flutter_hbb/utils/scale.dart';
import 'package:flutter_hbb/common/widgets/custom_scale_base.dart';

class ToolbarState {
  late RxBool _pin;

  RxBool collapse = false.obs;
  RxBool hide = false.obs;

  // Track initialization state to prevent flickering
  final RxBool initialized = false.obs;
  bool _isInitializing = false;

  ToolbarState() {
    _pin = RxBool(false);
    final s = bind.getLocalFlutterOption(k: kOptionRemoteMenubarState);
    if (s.isEmpty) {
      return;
    }

    try {
      final m = jsonDecode(s);
      if (m != null) {
        _pin = RxBool(m['pin'] ?? false);
      }
    } catch (e) {
      debugPrint('Failed to decode toolbar state ${e.toString()}');
    }
  }

  bool get pin => _pin.value;

  /// Initialize all toolbar states from session options.
  /// This should be called once when the toolbar is first created.
  Future<void> init(SessionID sessionId) async {
    if (initialized.value || _isInitializing) return;
    _isInitializing = true;

    try {
      // Load both states in parallel for better performance
      final results = await Future.wait([
        bind.sessionGetToggleOption(
            sessionId: sessionId, arg: kOptionCollapseToolbar),
        bind.sessionGetToggleOption(
            sessionId: sessionId, arg: kOptionHideToolbar),
      ]);

      collapse.value = results[0] ?? false;
      hide.value = results[1] ?? false;
    } finally {
      _isInitializing = false;
      initialized.value = true;
    }
  }

  switchCollapse(SessionID sessionId) async {
    bind.sessionToggleOption(
        sessionId: sessionId, value: kOptionCollapseToolbar);
    collapse.value = !collapse.value;
  }

  // Switch hide state for entire toolbar visibility
  switchHide(SessionID sessionId) async {
    bind.sessionToggleOption(sessionId: sessionId, value: kOptionHideToolbar);
    hide.value = !hide.value;
  }

  switchPin() async {
    _pin.value = !_pin.value;
    // Save everytime changed, as this func will not be called frequently
    await _savePin();
  }

  setPin(bool v) async {
    if (_pin.value != v) {
      _pin.value = v;
      // Save everytime changed, as this func will not be called frequently
      await _savePin();
    }
  }

  _savePin() async {
    bind.setLocalFlutterOption(
        k: kOptionRemoteMenubarState, v: jsonEncode({'pin': _pin.value}));
  }
}

class _ToolbarTheme {
  // TajDesk: glass toolbar palette — buttons have no solid coloured square
  // background by default. Active indicators (pin, recording) get a soft
  // translucent accent tint; inactive icons sit on the blurred glass.
  static Color blueColor = MyTheme.accent.withOpacity(0.22);
  static Color hoverBlueColor = MyTheme.accent.withOpacity(0.36);
  static Color inactiveColor = Colors.transparent;
  static Color hoverInactiveColor = Colors.white.withOpacity(0.10);

  static const Color redColor = Colors.redAccent;
  static const Color hoverRedColor = Colors.red;
  // kMinInteractiveDimension
  static const double height = 20.0;
  static const double dividerHeight = 12.0;

  static const double buttonSize = 32;
  static const double buttonHMargin = 2;
  static const double buttonVMargin = 6;
  static const double iconRadius = 8;
  static const double elevation = 3;

  static double dividerSpaceToAction = isWindows ? 8 : 14;

  static double menuBorderRadius = isWindows ? 5.0 : 7.0;
  static EdgeInsets menuPadding = isWindows
      ? EdgeInsets.fromLTRB(4, 12, 4, 12)
      : EdgeInsets.fromLTRB(6, 14, 6, 14);
  static const double menuButtonBorderRadius = 3.0;

  static Color borderColor(BuildContext context) =>
      MyTheme.color(context).border3 ?? MyTheme.border;

  static Color? dividerColor(BuildContext context) =>
      MyTheme.color(context).divider;

  // TajDesk stage 12: vertical separator between logical groups of toolbar
  // buttons. Thin hairline tinted to match the glass surface — readable on
  // both light and dark wallpapers without screaming for attention.
  static Widget groupDivider() => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(1),
        ),
      );

  // TajDesk stage 12: unified tooltip styling for every tooltip inside the
  // remote toolbar (both expanded panel and collapsed chip). Dark graphite
  // surface, soft shadow, rounded 6px corners — matches the rest of the UI
  // and replaces Flutter's stock sharp-edged grey balloon.
  static TooltipThemeData tooltipTheme() => TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        verticalOffset: 22,
        preferBelow: true,
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2230).withOpacity(0.96),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.30),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      );

  static MenuStyle defaultMenuStyle(BuildContext context) => MenuStyle(
        side: MaterialStateProperty.all(BorderSide(
          width: 1,
          color: borderColor(context),
        )),
        shape: MaterialStatePropertyAll(RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(_ToolbarTheme.menuBorderRadius))),
        padding: MaterialStateProperty.all(_ToolbarTheme.menuPadding),
      );
  static final defaultMenuButtonStyle = ButtonStyle(
    backgroundColor: MaterialStatePropertyAll(Colors.transparent),
    padding: MaterialStatePropertyAll(EdgeInsets.zero),
    overlayColor: MaterialStatePropertyAll(Colors.transparent),
  );

  static Widget borderWrapper(
      BuildContext context, Widget child, BorderRadius borderRadius) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: borderColor(context),
          width: 1,
        ),
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }
}

typedef DismissFunc = void Function();

class RemoteMenuEntry {
  static MenuEntryButton<String> insertLock(
    SessionID sessionId,
    EdgeInsets? padding, {
    DismissFunc? dismissFunc,
    DismissCallback? dismissCallback,
  }) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Insert Lock'),
        style: style,
      ),
      proc: () {
        bind.sessionLockScreen(sessionId: sessionId);
        if (dismissFunc != null) {
          dismissFunc();
        }
      },
      padding: padding,
      dismissOnClicked: true,
      dismissCallback: dismissCallback,
    );
  }

  static insertCtrlAltDel(
    SessionID sessionId,
    EdgeInsets? padding, {
    DismissFunc? dismissFunc,
    DismissCallback? dismissCallback,
  }) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate("Insert Ctrl + Alt + Del"),
        style: style,
      ),
      proc: () {
        bind.sessionCtrlAltDel(sessionId: sessionId);
        if (dismissFunc != null) {
          dismissFunc();
        }
      },
      padding: padding,
      dismissOnClicked: true,
      dismissCallback: dismissCallback,
    );
  }
}

class RemoteToolbar extends StatefulWidget {
  final String id;
  final FFI ffi;
  final ToolbarState state;
  final Function(int, Function(bool)) onEnterOrLeaveImageSetter;
  final Function(int) onEnterOrLeaveImageCleaner;
  final Function(VoidCallback) setRemoteState;

  RemoteToolbar({
    Key? key,
    required this.id,
    required this.ffi,
    required this.state,
    required this.onEnterOrLeaveImageSetter,
    required this.onEnterOrLeaveImageCleaner,
    required this.setRemoteState,
  }) : super(key: key);

  @override
  State<RemoteToolbar> createState() => _RemoteToolbarState();
}

class _RemoteToolbarState extends State<RemoteToolbar> {
  late Debouncer<int> _debouncerHide;
  bool _isCursorOverImage = false;
  final _fractionX = 0.5.obs;
  final _dragging = false.obs;

  // TajDesk stage 18: live-measured widget sizes for absolute positioning.
  // Defaults are sensible approximations used on the very first build;
  // they are overwritten with real measurements via _MeasureSize callbacks
  // on the next frame. The Rx wrappers make AnimatedPositioned react to
  // changes automatically.
  final _measuredToolbarWidth = 700.0.obs;
  final _measuredToolbarHeight = 50.0.obs;
  final _measuredChipWidth = 120.0.obs;
  final _measuredChipHeight = 32.0.obs;

  int get windowId => stateGlobal.windowId;

  void _setFullscreen(bool v) {
    stateGlobal.setFullscreen(v);
    // stateGlobal.fullscreen is RxBool now, no need to call setState.
    // setState(() {});
  }

  RxBool get collapse => widget.state.collapse;
  RxBool get hide => widget.state.hide;
  bool get pin => widget.state.pin;

  PeerInfo get pi => widget.ffi.ffiModel.pi;
  FfiModel get ffiModel => widget.ffi.ffiModel;

  triggerAutoHide() => _debouncerHide.value = _debouncerHide.value + 1;

  void _minimize() async =>
      await WindowController.fromWindowId(windowId).minimize();

  @override
  initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _fractionX.value = double.tryParse(await bind.sessionGetOption(
                  sessionId: widget.ffi.sessionId,
                  arg: 'remote-menubar-drag-x') ??
              '0.5') ??
          0.5;
      // Initialize toolbar states (collapse, hide) from session options
      widget.state.init(widget.ffi.sessionId);
    });

    _debouncerHide = Debouncer<int>(
      Duration(milliseconds: 5000),
      onChanged: _debouncerHideProc,
      initialValue: 0,
    );

    widget.onEnterOrLeaveImageSetter(identityHashCode(this), (enter) {
      if (enter) {
        triggerAutoHide();
        _isCursorOverImage = true;
      } else {
        _isCursorOverImage = false;
      }
    });
  }

  _debouncerHideProc(int v) {
    if (!pin && collapse.isFalse && _isCursorOverImage && _dragging.isFalse) {
      collapse.value = true;
    }
  }

  @override
  dispose() {
    super.dispose();

    widget.onEnterOrLeaveImageCleaner(identityHashCode(this));
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Wait for initialization to complete to prevent flickering
      if (!widget.state.initialized.value) {
        return const SizedBox.shrink();
      }
      // If toolbar is hidden, return empty widget
      if (hide.value) {
        return const SizedBox.shrink();
      }
      // TajDesk stage 18: pixel-accurate layout via Stack + Positioned +
      // LayoutBuilder. Replaces the original RustDesk geometry where the
      // chip lived inside the toolbar's Column with its own FractionalOffset
      // (which caused the chip to "jump" between expanded and collapsed
      // states because the two used different reference widths).
      //
      // Key idea: _fractionX is now interpreted as the *centre* of the chip
      // as a fraction of the screen width (was: left edge of chip as a
      // fraction of [0, screen - chip_w]). Both the chip and the toolbar
      // are centred horizontally on the same pixel coordinate
      // chipCentreX = _fractionX * screenW, then independently clamped to
      // stay inside the screen. That way:
      //   * Chip stays exactly where the user dropped it.
      //   * Toolbar (when expanded) opens centred above the chip.
      //   * Switching between expanded and collapsed never moves the chip.
      //
      // Widget sizes are measured at render time via _MeasureSize callbacks
      // that store the real widths in _measuredToolbarWidth / Height /
      // _measuredChipWidth / Height. First-frame defaults are decent
      // approximations; the next frame uses the real values.
      //
      // Animation between expanded and collapsed is driven by
      // AnimatedPositioned + AnimatedOpacity, giving a smooth slide+fade
      // morph (preserves stage 12 🅴 behaviour).
      return TooltipTheme(
        data: _ToolbarTheme.tooltipTheme(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenW = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 1920.0;
            return Obx(() {
              final isExpanded = collapse.isFalse;
              final chipW = _measuredChipWidth.value;
              final chipH = _measuredChipHeight.value;
              final toolbarW = _measuredToolbarWidth.value;
              final toolbarH = _measuredToolbarHeight.value;

              // Chip centre in pixels, clamped so the chip stays on-screen.
              final rawCentre = _fractionX.value * screenW;
              final minCentre = chipW / 2;
              final maxCentre = (screenW - chipW / 2) > minCentre
                  ? (screenW - chipW / 2)
                  : minCentre;
              final chipCentrePx = rawCentre < minCentre
                  ? minCentre
                  : (rawCentre > maxCentre ? maxCentre : rawCentre);
              final chipLeft = chipCentrePx - chipW / 2;

              // Toolbar centred on the same pixel, clamped to screen.
              final desiredToolbarLeft = chipCentrePx - toolbarW / 2;
              final maxToolbarLeft = (screenW - toolbarW) > 0
                  ? (screenW - toolbarW)
                  : 0.0;
              final toolbarLeft = desiredToolbarLeft < 0
                  ? 0.0
                  : (desiredToolbarLeft > maxToolbarLeft
                      ? maxToolbarLeft
                      : desiredToolbarLeft);

              // Container is wide enough for the full toolbar, tall enough
              // for toolbar + chip. AnimatedContainer smooths height changes
              // (so the desktop image behind isn't suddenly uncovered).
              final containerHeight =
                  (isExpanded ? toolbarH : 0.0) + chipH;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: screenW,
                height: containerHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Toolbar — always in the tree (so measurement keeps
                    // working). Opacity controls visibility, IgnorePointer
                    // blocks interaction when collapsed.
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      left: toolbarLeft,
                      top: isExpanded ? 0 : -toolbarH,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: isExpanded ? 1.0 : 0.0,
                        child: IgnorePointer(
                          ignoring: !isExpanded,
                          child: _MeasureSize(
                            onChange: (s) {
                              if (s.width > 0 && s.height > 0) {
                                _measuredToolbarWidth.value = s.width;
                                _measuredToolbarHeight.value = s.height;
                              }
                            },
                            child: _buildToolbarPanel(context),
                          ),
                        ),
                      ),
                    ),
                    // Chip — slides down when toolbar expands.
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      left: chipLeft,
                      top: isExpanded ? toolbarH : 0,
                      child: _MeasureSize(
                        onChange: (s) {
                          if (s.width > 0 && s.height > 0) {
                            _measuredChipWidth.value = s.width;
                            _measuredChipHeight.value = s.height;
                          }
                        },
                        child: _buildChip(context),
                      ),
                    ),
                  ],
                ),
              );
            });
          },
        ),
      );
    });
  }

  // TajDesk stage 18: chip widget without any horizontal positioning of its
  // own — the outer Stack/Positioned in build() handles that. Just the
  // Material + drag/show/hide buttons themselves. The auto-hide timer is
  // still kicked here so it behaves the same as before.
  Widget _buildChip(BuildContext context) {
    return Obx(() {
      if (collapse.isFalse && _dragging.isFalse) {
        triggerAutoHide();
      }
      final borderRadius = BorderRadius.vertical(
        bottom: Radius.circular(14),
      );
      return Offstage(
        offstage: _dragging.isTrue,
        child: Material(
          elevation: _ToolbarTheme.elevation,
          shadowColor: MyTheme.color(context).shadow,
          borderRadius: borderRadius,
          child: _DraggableShowHide(
            id: widget.id,
            sessionId: widget.ffi.sessionId,
            dragging: _dragging,
            fractionX: _fractionX,
            toolbarState: widget.state,
            setFullscreen: _setFullscreen,
            setMinimize: _minimize,
            borderRadius: borderRadius,
          ),
        ),
      );
    });
  }

  Widget _buildDraggableCollapse(BuildContext context) {
    return Obx(() {
      if (collapse.isFalse && _dragging.isFalse) {
        triggerAutoHide();
      }
      final borderRadius = BorderRadius.vertical(
        bottom: Radius.circular(14),
      );
      // TajDesk stage 17: restored to the original RustDesk behaviour —
      // the chip is always positioned by FractionalOffset(_fractionX, 0)
      // within its parent. In the expanded state that parent is the inner
      // glass-panel Column (so the chip can move within the toolbar's
      // width); in the collapsed state it's the full screen via the outer
      // Align. Yes, this means the chip can drift away from the toolbar
      // for non-centre _fractionX values, but at least the drag works
      // reliably and nothing snaps to corners.
      return Align(
        alignment: FractionalOffset(_fractionX.value, 0),
        child: Offstage(
          offstage: _dragging.isTrue,
          child: Material(
            elevation: _ToolbarTheme.elevation,
            shadowColor: MyTheme.color(context).shadow,
            borderRadius: borderRadius,
            child: _DraggableShowHide(
              id: widget.id,
              sessionId: widget.ffi.sessionId,
              dragging: _dragging,
              fractionX: _fractionX,
              toolbarState: widget.state,
              setFullscreen: _setFullscreen,
              setMinimize: _minimize,
              borderRadius: borderRadius,
            ),
          ),
        ),
      );
    });
  }

  // TajDesk stage 18: just the frosted-glass panel with buttons — no chip
  // attached below, no Column wrapper. The chip is rendered separately in
  // build() via Stack/Positioned. This is what we actually want to measure
  // and position as a unit. Logic for grouping buttons and inserting
  // dividers is identical to _buildToolbar (kept around as legacy for
  // safety, no longer called from build()).
  Widget _buildToolbarPanel(BuildContext context) {
    final List<List<Widget>> groups = [];

    final g1 = <Widget>[];
    g1.add(_PinMenu(state: widget.state));
    if (!isWebDesktop) {
      g1.add(_MobileActionMenu(ffi: widget.ffi));
    }
    groups.add(g1);

    final g2 = <Widget>[];
    g2.add(Obx(() {
      if ((PrivacyModeState.find(widget.id).isEmpty ||
              allowDisplaySwitchInPrivacyMode(pi)) &&
          pi.displaysCount.value > 1) {
        return _MonitorMenu(
            id: widget.id,
            ffi: widget.ffi,
            setRemoteState: widget.setRemoteState);
      } else {
        return Offstage();
      }
    }));
    g2.add(_ControlMenu(id: widget.id, ffi: widget.ffi, state: widget.state));
    groups.add(g2);

    final g3 = <Widget>[];
    g3.add(_DisplayMenu(
      id: widget.id,
      ffi: widget.ffi,
      state: widget.state,
      setFullscreen: _setFullscreen,
    ));
    if (widget.ffi.connType == ConnType.defaultConn) {
      g3.add(_KeyboardMenu(id: widget.id, ffi: widget.ffi));
    }
    groups.add(g3);

    final g4 = <Widget>[];
    g4.add(_ChatMenu(id: widget.id, ffi: widget.ffi));
    if (!isWeb) {
      g4.add(_VoiceCallMenu(id: widget.id, ffi: widget.ffi));
    }
    groups.add(g4);

    if (!isWeb) groups.add([_RecordMenu()]);
    groups.add([_CloseMenu(id: widget.id, ffi: widget.ffi)]);

    final List<Widget> rowChildren = [];
    rowChildren.add(SizedBox(width: _ToolbarTheme.buttonHMargin * 2));
    bool firstGroup = true;
    for (final group in groups) {
      if (group.isEmpty) continue;
      if (!firstGroup) {
        rowChildren.add(_ToolbarTheme.groupDivider());
      }
      rowChildren.addAll(group);
      firstGroup = false;
    }
    rowChildren.add(SizedBox(width: _ToolbarTheme.buttonHMargin * 2));

    // TajDesk stage 42 (variant A1): single rounded "pill" (radius 24) instead
    // of the boxy RustDesk panel. Grouping dividers + buttons are unchanged.
    final toolbarBorderRadius = BorderRadius.all(Radius.circular(24.0));
    return ClipRRect(
      borderRadius: toolbarBorderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          elevation: _ToolbarTheme.elevation,
          shadowColor: Colors.black.withOpacity(0.4),
          borderRadius: toolbarBorderRadius,
          color: Colors.black.withOpacity(0.32),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Theme(
              data: themeData(),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                    width: 1,
                  ),
                  borderRadius: toolbarBorderRadius,
                ),
                child: Row(
                  children: rowChildren,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    // TajDesk stage 12: structure buttons into logical groups so we can
    // insert thin vertical dividers between them. Order is preserved 1:1
    // with the original RustDesk layout — only visual grouping changes.
    //   group 1: pin + mobile actions
    //   group 2: monitor switcher + control menu
    //   group 3: display settings + keyboard
    //   group 4: chat + voice call
    //   group 5: record
    //   group 6: close
    final List<List<Widget>> groups = [];

    final g1 = <Widget>[];
    g1.add(_PinMenu(state: widget.state));
    if (!isWebDesktop) {
      g1.add(_MobileActionMenu(ffi: widget.ffi));
    }
    groups.add(g1);

    final g2 = <Widget>[];
    g2.add(Obx(() {
      if ((PrivacyModeState.find(widget.id).isEmpty ||
              allowDisplaySwitchInPrivacyMode(pi)) &&
          pi.displaysCount.value > 1) {
        return _MonitorMenu(
            id: widget.id,
            ffi: widget.ffi,
            setRemoteState: widget.setRemoteState);
      } else {
        return Offstage();
      }
    }));
    g2.add(_ControlMenu(id: widget.id, ffi: widget.ffi, state: widget.state));
    groups.add(g2);

    final g3 = <Widget>[];
    g3.add(_DisplayMenu(
      id: widget.id,
      ffi: widget.ffi,
      state: widget.state,
      setFullscreen: _setFullscreen,
    ));
    // Do not show keyboard for camera connection type.
    if (widget.ffi.connType == ConnType.defaultConn) {
      g3.add(_KeyboardMenu(id: widget.id, ffi: widget.ffi));
    }
    groups.add(g3);

    final g4 = <Widget>[];
    g4.add(_ChatMenu(id: widget.id, ffi: widget.ffi));
    if (!isWeb) {
      g4.add(_VoiceCallMenu(id: widget.id, ffi: widget.ffi));
    }
    groups.add(g4);

    if (!isWeb) groups.add([_RecordMenu()]);
    groups.add([_CloseMenu(id: widget.id, ffi: widget.ffi)]);

    // Stitch the groups together. Drop empty groups; insert one hairline
    // divider between every pair of consecutive non-empty groups.
    final List<Widget> rowChildren = [];
    rowChildren.add(SizedBox(width: _ToolbarTheme.buttonHMargin * 2));
    bool firstGroup = true;
    for (final group in groups) {
      if (group.isEmpty) continue;
      if (!firstGroup) {
        rowChildren.add(_ToolbarTheme.groupDivider());
      }
      rowChildren.addAll(group);
      firstGroup = false;
    }
    rowChildren.add(SizedBox(width: _ToolbarTheme.buttonHMargin * 2));

    // TajDesk: floating glass toolbar — softer corners and bigger radius
    final toolbarBorderRadius = BorderRadius.all(Radius.circular(12.0));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // TajDesk: frosted-glass background for the expanded toolbar.
        // Wrap the original Material in a BackdropFilter so the desktop image
        // behind the toolbar is blurred and slightly tinted, instead of the
        // solid menu-bar colour. ClipRRect is required for the blur to honour
        // the rounded corners.
        ClipRRect(
          borderRadius: toolbarBorderRadius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Material(
              elevation: _ToolbarTheme.elevation,
              shadowColor: Colors.black.withOpacity(0.4),
              borderRadius: toolbarBorderRadius,
              color: Colors.black.withOpacity(0.32),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Theme(
                  data: themeData(),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                        width: 1,
                      ),
                      borderRadius: toolbarBorderRadius,
                    ),
                    child: Row(
                      children: rowChildren,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _buildDraggableCollapse(context),
      ],
    );
  }

  ThemeData themeData() {
    return Theme.of(context).copyWith(
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          minimumSize: MaterialStatePropertyAll(Size(64, 32)),
          textStyle: MaterialStatePropertyAll(
            TextStyle(fontWeight: FontWeight.normal),
          ),
          shape: MaterialStatePropertyAll(RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(_ToolbarTheme.menuButtonBorderRadius))),
        ),
      ),
      dividerTheme: DividerThemeData(
        space: _ToolbarTheme.dividerSpaceToAction,
        color: _ToolbarTheme.dividerColor(context),
      ),
      menuBarTheme: MenuBarThemeData(
          style: MenuStyle(
        // TajDesk stage 13: force MenuBar background to be transparent so
        // every toolbar button sits directly on the frosted-glass panel,
        // instead of carrying a dark grey card behind it (inherited from
        // the global dark theme). Without this override the icons looked
        // like they were stuck on black tiles, fighting the glass effect.
        backgroundColor: MaterialStatePropertyAll(Colors.transparent),
        surfaceTintColor: MaterialStatePropertyAll(Colors.transparent),
        shadowColor: MaterialStatePropertyAll(Colors.transparent),
        padding: MaterialStatePropertyAll(EdgeInsets.zero),
        elevation: MaterialStatePropertyAll(0),
        shape: MaterialStatePropertyAll(BeveledRectangleBorder()),
      )),
    );
  }
}

class _PinMenu extends StatelessWidget {
  final ToolbarState state;
  const _PinMenu({Key? key, required this.state}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => _IconMenuButton(
        assetName: state.pin ? "assets/pinned.svg" : "assets/unpinned.svg",
        tooltip: state.pin ? 'Unpin Toolbar' : 'Pin Toolbar',
        onPressed: state.switchPin,
        color:
            state.pin ? _ToolbarTheme.blueColor : _ToolbarTheme.inactiveColor,
        hoverColor: state.pin
            ? _ToolbarTheme.hoverBlueColor
            : _ToolbarTheme.hoverInactiveColor,
      ),
    );
  }
}

class _MobileActionMenu extends StatelessWidget {
  final FFI ffi;
  const _MobileActionMenu({Key? key, required this.ffi}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!ffi.ffiModel.isPeerAndroid) return Offstage();
    return Obx(() => _IconMenuButton(
          assetName: 'assets/actions_mobile.svg',
          tooltip: 'Mobile Actions',
          onPressed: () => ffi.dialogManager.setMobileActionsOverlayVisible(
              !ffi.dialogManager.mobileActionsOverlayVisible.value),
          color: ffi.dialogManager.mobileActionsOverlayVisible.isTrue
              ? _ToolbarTheme.blueColor
              : _ToolbarTheme.inactiveColor,
          hoverColor: ffi.dialogManager.mobileActionsOverlayVisible.isTrue
              ? _ToolbarTheme.hoverBlueColor
              : _ToolbarTheme.hoverInactiveColor,
        ));
  }
}

class _MonitorMenu extends StatelessWidget {
  final String id;
  final FFI ffi;
  final Function(VoidCallback) setRemoteState;
  const _MonitorMenu({
    Key? key,
    required this.id,
    required this.ffi,
    required this.setRemoteState,
  }) : super(key: key);

  bool get showMonitorsToolbar =>
      bind.mainGetUserDefaultOption(key: kKeyShowMonitorsToolbar) == 'Y';

  bool get supportIndividualWindows =>
      !isWeb && ffi.ffiModel.pi.isSupportMultiDisplay;

  @override
  Widget build(BuildContext context) => showMonitorsToolbar
      ? buildMultiMonitorMenu(context)
      : Obx(() => buildMonitorMenu(context));

  Widget buildMonitorMenu(BuildContext context) {
    final width = SimpleWrapper<double>(0);
    final monitorsIcon =
        globalMonitorsWidget(width, Colors.white, Colors.black38);
    return _IconSubmenuButton(
        tooltip: 'Select Monitor',
        icon: monitorsIcon,
        ffi: ffi,
        width: width.value,
        color: _ToolbarTheme.blueColor,
        hoverColor: _ToolbarTheme.hoverBlueColor,
        menuStyle: MenuStyle(
            padding:
                MaterialStatePropertyAll(EdgeInsets.symmetric(horizontal: 6))),
        menuChildrenGetter: (_) => [buildMonitorSubmenuWidget(context)]);
  }

  Widget buildMultiMonitorMenu(BuildContext context) {
    return Row(children: buildMonitorList(context, true));
  }

  Widget buildMonitorSubmenuWidget(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: buildMonitorList(context, false)),
        supportIndividualWindows ? Divider() : Offstage(),
        supportIndividualWindows ? chooseDisplayBehavior() : Offstage(),
      ],
    );
  }

  Widget chooseDisplayBehavior() {
    final value =
        bind.sessionGetDisplaysAsIndividualWindows(sessionId: ffi.sessionId) ==
            'Y';
    return CkbMenuButton(
        value: value,
        onChanged: (value) async {
          if (value == null) return;
          await bind.sessionSetDisplaysAsIndividualWindows(
              sessionId: ffi.sessionId, value: value ? 'Y' : 'N');
        },
        ffi: ffi,
        child: Text(translate('Show displays as individual windows')));
  }

  buildOneMonitorButton(i, curDisplay) => Text(
        '${i + 1}',
        style: TextStyle(
          color: i == curDisplay
              ? _ToolbarTheme.blueColor
              : _ToolbarTheme.inactiveColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );

  List<Widget> buildMonitorList(BuildContext context, bool isMulti) {
    final List<Widget> monitorList = [];
    final pi = ffi.ffiModel.pi;

    buildMonitorButton(int i) => Obx(() {
          RxInt display = CurrentDisplayState.find(id);

          final isAllMonitors = i == kAllDisplayValue;
          final width = SimpleWrapper<double>(0);
          Widget? monitorsIcon;
          if (isAllMonitors) {
            monitorsIcon = globalMonitorsWidget(
                width, Colors.white, _ToolbarTheme.blueColor);
          }
          return _IconMenuButton(
            tooltip: isMulti
                ? ''
                : isAllMonitors
                    ? 'all monitors'
                    : '#${i + 1} monitor',
            hMargin: isMulti ? null : 6,
            vMargin: isMulti ? null : 12,
            topLevel: false,
            color: i == display.value
                ? _ToolbarTheme.blueColor
                : _ToolbarTheme.inactiveColor,
            hoverColor: i == display.value
                ? _ToolbarTheme.hoverBlueColor
                : _ToolbarTheme.hoverInactiveColor,
            width: isAllMonitors ? width.value : null,
            icon: isAllMonitors
                ? monitorsIcon
                : Container(
                    alignment: AlignmentDirectional.center,
                    constraints:
                        const BoxConstraints(minHeight: _ToolbarTheme.height),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SvgPicture.asset(
                          "assets/screen.svg",
                          colorFilter:
                              ColorFilter.mode(Colors.white, BlendMode.srcIn),
                        ),
                        Obx(() => buildOneMonitorButton(i, display.value)),
                      ],
                    ),
                  ),
            onPressed: () => onPressed(i, pi, isMulti),
          );
        });

    for (int i = 0; i < pi.displays.length; i++) {
      monitorList.add(buildMonitorButton(i));
    }
    if (supportIndividualWindows && pi.displays.length > 1) {
      monitorList.add(buildMonitorButton(kAllDisplayValue));
    }
    return monitorList;
  }

  globalMonitorsWidget(
      SimpleWrapper<double> width, Color activeTextColor, Color activeBgColor) {
    getMonitors() {
      final pi = ffi.ffiModel.pi;
      RxInt display = CurrentDisplayState.find(id);
      final rect = ffi.ffiModel.globalDisplaysRect();
      if (rect == null) {
        return Offstage();
      }

      final scale = _ToolbarTheme.buttonSize / rect.height * 0.75;
      final startY = (_ToolbarTheme.buttonSize - rect.height * scale) * 0.5;
      final startX = startY;

      final children = <Widget>[];
      for (var i = 0; i < pi.displays.length; i++) {
        final d = pi.displays[i];
        double s = d.scale;
        int dWidth = d.width.toDouble() ~/ s;
        int dHeight = d.height.toDouble() ~/ s;
        final fontSize = (dWidth * scale < dHeight * scale
                ? dWidth * scale
                : dHeight * scale) *
            0.65;
        children.add(Positioned(
          left: (d.x - rect.left) * scale + startX,
          top: (d.y - rect.top) * scale + startY,
          width: dWidth * scale,
          height: dHeight * scale,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.grey,
                width: 1.0,
              ),
              color: display.value == i ? activeBgColor : Colors.white,
            ),
            child: Center(
                child: Text(
              '${i + 1}',
              style: TextStyle(
                color: display.value == i
                    ? activeTextColor
                    : _ToolbarTheme.inactiveColor,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
              ),
            )),
          ),
        ));
      }
      width.value = rect.width * scale + startX * 2;
      return SizedBox(
        width: width.value,
        height: rect.height * scale + startY * 2,
        child: Stack(
          children: children,
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(height: _ToolbarTheme.buttonSize),
        getMonitors(),
      ],
    );
  }

  onPressed(int i, PeerInfo pi, bool isMulti) {
    if (!isMulti) {
      // If show monitors in toolbar(`buildMultiMonitorMenu()`), then the menu will dismiss automatically.
      _menuDismissCallback(ffi);
    }
    RxInt display = CurrentDisplayState.find(id);
    if (display.value != i) {
      final isChooseDisplayToOpenInNewWindow = pi.isSupportMultiDisplay &&
          bind.sessionGetDisplaysAsIndividualWindows(
                  sessionId: ffi.sessionId) ==
              'Y';
      if (isChooseDisplayToOpenInNewWindow) {
        openMonitorInNewTabOrWindow(i, ffi.id, pi);
      } else {
        openMonitorInTheSameTab(i, ffi, pi, updateCursorPos: !isMulti);
      }
    }
  }
}

class _ControlMenu extends StatelessWidget {
  final String id;
  final FFI ffi;
  final ToolbarState state;
  _ControlMenu(
      {Key? key, required this.id, required this.ffi, required this.state})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _IconSubmenuButton(
        tooltip: 'Control Actions',
        svg: "assets/actions.svg",
        color: _ToolbarTheme.blueColor,
        hoverColor: _ToolbarTheme.hoverBlueColor,
        ffi: ffi,
        menuChildrenGetter: (_) => toolbarControls(context, id, ffi).map((e) {
              if (e.divider) {
                return Divider();
              } else {
                return MenuButton(
                    child: e.child,
                    onPressed: e.onPressed,
                    ffi: ffi,
                    trailingIcon: e.trailingIcon);
              }
            }).toList());
  }
}

class ScreenAdjustor {
  final String id;
  final FFI ffi;
  final VoidCallback cbExitFullscreen;
  window_size.Screen? _screen;

  ScreenAdjustor({
    required this.id,
    required this.ffi,
    required this.cbExitFullscreen,
  });

  bool get isFullscreen => stateGlobal.fullscreen.isTrue;
  int get windowId => stateGlobal.windowId;

  adjustWindow(BuildContext context) {
    return futureBuilder(
        future: isWindowCanBeAdjusted(),
        hasData: (data) {
          final visible = data as bool;
          if (!visible) return Offstage();
          return Column(
            children: [
              MenuButton(
                  child: Text(translate('Adjust Window')),
                  onPressed: () => doAdjustWindow(context),
                  ffi: ffi),
              Divider(),
            ],
          );
        });
  }

  doAdjustWindow(BuildContext context) async {
    await updateScreen();
    if (_screen != null) {
      cbExitFullscreen();
      double scale = _screen!.scaleFactor;
      final wndRect = await WindowController.fromWindowId(windowId).getFrame();
      final mediaSize = MediaQueryData.fromView(View.of(context)).size;
      // On windows, wndRect is equal to GetWindowRect and mediaSize is equal to GetClientRect.
      // https://stackoverflow.com/a/7561083
      double magicWidth =
          wndRect.right - wndRect.left - mediaSize.width * scale;
      double magicHeight =
          wndRect.bottom - wndRect.top - mediaSize.height * scale;
      final canvasModel = ffi.canvasModel;
      final width = (canvasModel.getDisplayWidth() * canvasModel.scale +
                  CanvasModel.leftToEdge +
                  CanvasModel.rightToEdge) *
              scale +
          magicWidth;
      final height = (canvasModel.getDisplayHeight() * canvasModel.scale +
                  CanvasModel.topToEdge +
                  CanvasModel.bottomToEdge) *
              scale +
          magicHeight;
      double left = wndRect.left + (wndRect.width - width) / 2;
      double top = wndRect.top + (wndRect.height - height) / 2;

      Rect frameRect = _screen!.frame;
      if (!isFullscreen) {
        frameRect = _screen!.visibleFrame;
      }
      if (left < frameRect.left) {
        left = frameRect.left;
      }
      if (top < frameRect.top) {
        top = frameRect.top;
      }
      if ((left + width) > frameRect.right) {
        left = frameRect.right - width;
      }
      if ((top + height) > frameRect.bottom) {
        top = frameRect.bottom - height;
      }
      await WindowController.fromWindowId(windowId)
          .setFrame(Rect.fromLTWH(left, top, width, height));
      stateGlobal.setMaximized(false);
    }
  }

  updateScreen() async {
    final String info =
        isWeb ? screenInfo : await _getScreenInfoDesktop() ?? '';
    if (info.isEmpty) {
      _screen = null;
    } else {
      final screenMap = jsonDecode(info);
      _screen = window_size.Screen(
          Rect.fromLTRB(screenMap['frame']['l'], screenMap['frame']['t'],
              screenMap['frame']['r'], screenMap['frame']['b']),
          Rect.fromLTRB(
              screenMap['visibleFrame']['l'],
              screenMap['visibleFrame']['t'],
              screenMap['visibleFrame']['r'],
              screenMap['visibleFrame']['b']),
          screenMap['scaleFactor']);
    }
  }

  _getScreenInfoDesktop() async {
    final v = await rustDeskWinManager.call(
        WindowType.Main, kWindowGetWindowInfo, '');
    return v.result;
  }

  Future<bool> isWindowCanBeAdjusted() async {
    final viewStyle =
        await bind.sessionGetViewStyle(sessionId: ffi.sessionId) ?? '';
    if (viewStyle != kRemoteViewStyleOriginal) {
      return false;
    }
    if (!isWeb) {
      final remoteCount = RemoteCountState.find().value;
      if (remoteCount != 1) {
        return false;
      }
    }
    if (_screen == null) {
      return false;
    }
    final scale = kIgnoreDpi ? 1.0 : _screen!.scaleFactor;
    double selfWidth = _screen!.visibleFrame.width;
    double selfHeight = _screen!.visibleFrame.height;
    if (isFullscreen) {
      selfWidth = _screen!.frame.width;
      selfHeight = _screen!.frame.height;
    }

    final canvasModel = ffi.canvasModel;
    final displayWidth = canvasModel.getDisplayWidth();
    final displayHeight = canvasModel.getDisplayHeight();
    final requiredWidth =
        CanvasModel.leftToEdge + displayWidth + CanvasModel.rightToEdge;
    final requiredHeight =
        CanvasModel.topToEdge + displayHeight + CanvasModel.bottomToEdge;
    return selfWidth > (requiredWidth * scale) &&
        selfHeight > (requiredHeight * scale);
  }
}

class _DisplayMenu extends StatefulWidget {
  final String id;
  final FFI ffi;
  final ToolbarState state;
  final Function(bool) setFullscreen;
  final Widget pluginItem;
  _DisplayMenu(
      {Key? key,
      required this.id,
      required this.ffi,
      required this.state,
      required this.setFullscreen})
      : pluginItem = LocationItem.createLocationItem(
          id,
          ffi,
          kLocationClientRemoteToolbarDisplay,
          true,
        ),
        super(key: key);

  @override
  State<_DisplayMenu> createState() => _DisplayMenuState();
}

class _DisplayMenuState extends State<_DisplayMenu> {
  final RxInt _customPercent = 100.obs;
  late final ScreenAdjustor _screenAdjustor = ScreenAdjustor(
    id: widget.id,
    ffi: widget.ffi,
    cbExitFullscreen: () => widget.setFullscreen(false),
  );

  int get windowId => stateGlobal.windowId;
  Map<String, bool> get perms => widget.ffi.ffiModel.permissions;
  PeerInfo get pi => widget.ffi.ffiModel.pi;
  FfiModel get ffiModel => widget.ffi.ffiModel;
  FFI get ffi => widget.ffi;
  String get id => widget.id;

  @override
  void initState() {
    super.initState();
    // Initialize custom percent from stored option once
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final v = await getSessionCustomScalePercent(widget.ffi.sessionId);
        if (_customPercent.value != v) {
          _customPercent.value = v;
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    _screenAdjustor.updateScreen();
    menuChildrenGetter(_IconSubmenuButtonState state) {
      final menuChildren = <Widget>[
        _screenAdjustor.adjustWindow(context),
        viewStyle(customPercent: _customPercent),
        scrollStyle(state, colorScheme),
        imageQuality(),
        codec(),
        if (ffi.connType == ConnType.defaultConn)
          _ResolutionsMenu(
            id: widget.id,
            ffi: widget.ffi,
            screenAdjustor: _screenAdjustor,
          ),
        if (showVirtualDisplayMenu(ffi) && ffi.connType == ConnType.defaultConn)
          _SubmenuButton(
            ffi: widget.ffi,
            menuChildren: getVirtualDisplayMenuChildren(ffi, id, null),
            child: Text(translate("Virtual display")),
          ),
        if (ffi.connType == ConnType.defaultConn) cursorToggles(),
        Divider(),
        toggles(),
      ];
      // privacy mode
      final privacyModeState = PrivacyModeState.find(id);
      if (ffi.connType == ConnType.defaultConn &&
          (pi.features.privacyMode || privacyModeState.isNotEmpty) &&
          (ffiModel.keyboard || privacyModeState.isNotEmpty)) {
        final privacyModeList =
            toolbarPrivacyMode(privacyModeState, context, id, ffi);
        if (privacyModeList.length == 1) {
          menuChildren.add(CkbMenuButton(
              value: privacyModeList[0].value,
              onChanged: privacyModeList[0].onChanged,
              child: privacyModeList[0].child,
              ffi: ffi));
        } else if (privacyModeList.length > 1) {
          menuChildren.addAll([
            Divider(),
            _SubmenuButton(
                ffi: widget.ffi,
                child: Text(translate('Privacy mode')),
                menuChildren: privacyModeList
                    .map((e) => CkbMenuButton(
                        value: e.value,
                        onChanged: e.onChanged,
                        child: e.child,
                        ffi: ffi))
                    .toList()),
          ]);
        }
      }
      if (ffi.connType == ConnType.defaultConn) {
        menuChildren.add(widget.pluginItem);
      }
      return menuChildren;
    }

    return _IconSubmenuButton(
      tooltip: 'Display Settings',
      svg: "assets/display.svg",
      ffi: widget.ffi,
      color: _ToolbarTheme.blueColor,
      hoverColor: _ToolbarTheme.hoverBlueColor,
      menuChildrenGetter: menuChildrenGetter,
    );
  }

  viewStyle({required RxInt customPercent}) {
    return futureBuilder(
        future: toolbarViewStyle(context, widget.id, widget.ffi),
        hasData: (data) {
          final v = data as List<TRadioMenu<String>>;
          final bool isCustomSelected = v.isNotEmpty
              ? v.first.groupValue == kRemoteViewStyleCustom
              : false;
          return Column(children: [
            ...v.map((e) {
              final isCustom = e.value == kRemoteViewStyleCustom;
              final child =
                  isCustom ? Text(translate('Scale custom')) : e.child;
              // Whether the current selection is already custom
              final bool isGroupCustomSelected =
                  e.groupValue == kRemoteViewStyleCustom;
              // Keep menu open when switching INTO custom so the slider is visible immediately
              final bool keepOpenForThisItem =
                  isCustom && !isGroupCustomSelected;
              return RdoMenuButton<String>(
                  value: e.value,
                  groupValue: e.groupValue,
                  onChanged: (value) {
                    // Perform the original change
                    e.onChanged?.call(value);
                    // Only force a rebuild when we keep the menu open to reveal the slider
                    if (keepOpenForThisItem) {
                      setState(() {});
                    }
                  },
                  child: child,
                  ffi: ffi,
                  // When entering custom, keep submenu open to show the slider controls
                  closeOnActivate: !keepOpenForThisItem);
            }).toList(),
            // Only show a divider when custom is NOT selected
            if (!isCustomSelected) Divider(),
            _customControlsIfCustomSelected(
                onChanged: (v) => customPercent.value = v),
          ]);
        });
  }

  Widget _customControlsIfCustomSelected({ValueChanged<int>? onChanged}) {
    return futureBuilder(future: () async {
      final current = await bind.sessionGetViewStyle(sessionId: ffi.sessionId);
      return current == kRemoteViewStyleCustom;
    }(), hasData: (data) {
      final isCustom = data as bool;
      return AnimatedSwitcher(
        duration: Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: isCustom
            ? _CustomScaleMenuControls(ffi: ffi, onChanged: onChanged)
            : SizedBox.shrink(),
      );
    });
  }

  scrollStyle(_IconSubmenuButtonState state, ColorScheme colorScheme) {
    return futureBuilder(future: () async {
      final viewStyle =
          await bind.sessionGetViewStyle(sessionId: ffi.sessionId) ?? '';
      final visible = viewStyle == kRemoteViewStyleOriginal ||
          viewStyle == kRemoteViewStyleCustom;
      final scrollStyle =
          await bind.sessionGetScrollStyle(sessionId: ffi.sessionId) ?? '';
      final edgeScrollEdgeThickness = await bind
          .sessionGetEdgeScrollEdgeThickness(sessionId: ffi.sessionId);
      return {
        'visible': visible,
        'scrollStyle': scrollStyle,
        'edgeScrollEdgeThickness': edgeScrollEdgeThickness,
      };
    }(), hasData: (data) {
      final visible = data['visible'] as bool;
      if (!visible) return Offstage();
      final groupValue = data['scrollStyle'] as String;
      final edgeScrollEdgeThickness = data['edgeScrollEdgeThickness'] as int;

      onChangeScrollStyle(String? value) async {
        if (value == null) return;
        await bind.sessionSetScrollStyle(
            sessionId: ffi.sessionId, value: value);
        widget.ffi.canvasModel.updateScrollStyle();
        state.setState(() {});
      }

      onChangeEdgeScrollEdgeThickness(double? value) async {
        if (value == null) return;
        final newThickness = value.round();
        await bind.sessionSetEdgeScrollEdgeThickness(
            sessionId: ffi.sessionId, value: newThickness);
        widget.ffi.canvasModel.updateEdgeScrollEdgeThickness(newThickness);
        state.setState(() {});
      }

      return Obx(() => Column(children: [
            RdoMenuButton<String>(
              child: Text(translate('ScrollAuto')),
              value: kRemoteScrollStyleAuto,
              groupValue: groupValue,
              onChanged: widget.ffi.canvasModel.imageOverflow.value
                  ? (value) => onChangeScrollStyle(value)
                  : null,
              closeOnActivate: groupValue != kRemoteScrollStyleEdge,
              ffi: widget.ffi,
            ),
            RdoMenuButton<String>(
              child: Text(translate('Scrollbar')),
              value: kRemoteScrollStyleBar,
              groupValue: groupValue,
              onChanged: widget.ffi.canvasModel.imageOverflow.value
                  ? (value) => onChangeScrollStyle(value)
                  : null,
              closeOnActivate: groupValue != kRemoteScrollStyleEdge,
              ffi: widget.ffi,
            ),
            if (!isWeb) ...[
              RdoMenuButton<String>(
                child: Text(translate('ScrollEdge')),
                value: kRemoteScrollStyleEdge,
                groupValue: groupValue,
                closeOnActivate: false,
                onChanged: widget.ffi.canvasModel.imageOverflow.value
                    ? (value) => onChangeScrollStyle(value)
                    : null,
                ffi: widget.ffi,
              ),
              Offstage(
                  offstage: groupValue != kRemoteScrollStyleEdge,
                  child: EdgeThicknessControl(
                    value: edgeScrollEdgeThickness.toDouble(),
                    onChanged: onChangeEdgeScrollEdgeThickness,
                    colorScheme: colorScheme,
                  )),
            ],
            Divider(),
          ]));
    });
  }

  imageQuality() {
    return futureBuilder(
        future: toolbarImageQuality(context, widget.id, widget.ffi),
        hasData: (data) {
          final v = data as List<TRadioMenu<String>>;
          return _SubmenuButton(
            ffi: widget.ffi,
            child: Text(translate('Image Quality')),
            menuChildren: v
                .map((e) => RdoMenuButton<String>(
                    value: e.value,
                    groupValue: e.groupValue,
                    onChanged: e.onChanged,
                    child: e.child,
                    ffi: ffi))
                .toList(),
          );
        });
  }

  codec() {
    return futureBuilder(
        future: toolbarCodec(context, id, ffi),
        hasData: (data) {
          final v = data as List<TRadioMenu<String>>;
          if (v.isEmpty) return Offstage();

          return _SubmenuButton(
              ffi: widget.ffi,
              child: Text(translate('Codec')),
              menuChildren: v
                  .map((e) => RdoMenuButton(
                      value: e.value,
                      groupValue: e.groupValue,
                      onChanged: e.onChanged,
                      child: e.child,
                      ffi: ffi))
                  .toList());
        });
  }

  cursorToggles() {
    return futureBuilder(
        future: toolbarCursor(context, id, ffi),
        hasData: (data) {
          final v = data as List<TToggleMenu>;
          if (v.isEmpty) return Offstage();
          return Column(children: [
            Divider(),
            ...v
                .map((e) => CkbMenuButton(
                    value: e.value,
                    onChanged: e.onChanged,
                    child: e.child,
                    ffi: ffi))
                .toList(),
          ]);
        });
  }

  toggles() {
    return futureBuilder(
        future: toolbarDisplayToggle(context, id, ffi),
        hasData: (data) {
          final v = data as List<TToggleMenu>;
          if (v.isEmpty) return Offstage();
          return Column(
              children: v
                  .map((e) => CkbMenuButton(
                      value: e.value,
                      onChanged: e.onChanged,
                      child: e.child,
                      ffi: ffi))
                  .toList());
        });
  }
}

class _CustomScaleMenuControls extends StatefulWidget {
  final FFI ffi;
  final ValueChanged<int>? onChanged;
  const _CustomScaleMenuControls({Key? key, required this.ffi, this.onChanged})
      : super(key: key);

  @override
  State<_CustomScaleMenuControls> createState() =>
      _CustomScaleMenuControlsState();
}

class _CustomScaleMenuControlsState
    extends CustomScaleControls<_CustomScaleMenuControls> {
  @override
  FFI get ffi => widget.ffi;

  @override
  ValueChanged<int>? get onScaleChanged => widget.onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const smallBtnConstraints = BoxConstraints(minWidth: 28, minHeight: 28);

    final sliderControl = Semantics(
      label: translate('Custom scale slider'),
      value: '$scaleValue%',
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: colorScheme.primary,
          thumbColor: colorScheme.primary,
          overlayColor: colorScheme.primary.withOpacity(0.1),
          showValueIndicator: ShowValueIndicator.never,
          thumbShape: _RectValueThumbShape(
            min: CustomScaleControls.minPercent.toDouble(),
            max: CustomScaleControls.maxPercent.toDouble(),
            width: 52,
            height: 24,
            radius: 4,
            displayValueForNormalized: (t) => mapPosToPercent(t),
          ),
        ),
        child: Slider(
          value: scalePos,
          min: 0.0,
          max: 1.0,
          // Use a wide range of divisions (calculated as (CustomScaleControls.maxPercent - CustomScaleControls.minPercent)) to provide ~1% precision increments.
          // This allows users to set precise scale values. Lower values would require more fine-tuning via the +/- buttons, which is undesirable for big ranges.
          divisions:
              (CustomScaleControls.maxPercent - CustomScaleControls.minPercent)
                  .round(),
          onChanged: onSliderChanged,
        ),
      ),
    );

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Row(children: [
          Tooltip(
            message: translate('Decrease'),
            child: IconButton(
              iconSize: 16,
              padding: EdgeInsets.all(1),
              constraints: smallBtnConstraints,
              icon: const Icon(Icons.remove),
              onPressed: () => nudgeScale(-1),
            ),
          ),
          Expanded(child: sliderControl),
          Tooltip(
            message: translate('Increase'),
            child: IconButton(
              iconSize: 16,
              padding: EdgeInsets.all(1),
              constraints: smallBtnConstraints,
              icon: const Icon(Icons.add),
              onPressed: () => nudgeScale(1),
            ),
          ),
        ]),
      ),
      Divider(),
    ]);
  }
}

// Lightweight rectangular thumb that paints the current percentage.
// Stateless and uses only SliderTheme colors; avoids allocations beyond a TextPainter per frame.
class _RectValueThumbShape extends SliderComponentShape {
  final double min;
  final double max;
  final double width;
  final double height;
  final double radius;
  final String unit;
  // Optional mapper to compute display value from normalized position [0,1]
  // If null, falls back to linear interpolation between min and max.
  final int Function(double normalized)? displayValueForNormalized;

  const _RectValueThumbShape({
    required this.min,
    required this.max,
    required this.width,
    required this.height,
    required this.radius,
    this.displayValueForNormalized,
    this.unit = '%',
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size(width, height);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    // Resolve color based on enabled/disabled animation, with safe fallbacks.
    final ColorTween colorTween = ColorTween(
      begin: sliderTheme.disabledThumbColor,
      end: sliderTheme.thumbColor,
    );
    final Color? evaluatedColor = colorTween.evaluate(enableAnimation);
    final Color? thumbColor = sliderTheme.thumbColor;
    final Color fillColor = evaluatedColor ?? thumbColor ?? Colors.blueAccent;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: height),
      Radius.circular(radius),
    );
    final Paint paint = Paint()..color = fillColor;
    canvas.drawRRect(rrect, paint);

    // Compute displayed value from normalized slider value.
    final int displayValue = displayValueForNormalized != null
        ? displayValueForNormalized!(value)
        : (min + value * (max - min)).round();
    final TextSpan span = TextSpan(
      text: '$displayValue$unit',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
    final TextPainter tp = TextPainter(
      text: span,
      textAlign: TextAlign.center,
      textDirection: textDirection,
    );
    tp.layout(maxWidth: width - 4);
    tp.paint(
        canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }
}

class _ResolutionsMenu extends StatefulWidget {
  final String id;
  final FFI ffi;
  final ScreenAdjustor screenAdjustor;

  _ResolutionsMenu({
    Key? key,
    required this.id,
    required this.ffi,
    required this.screenAdjustor,
  }) : super(key: key);

  @override
  State<_ResolutionsMenu> createState() => _ResolutionsMenuState();
}

const double _kCustomResolutionEditingWidth = 42;
const _kCustomResolutionValue = 'custom';

class _ResolutionsMenuState extends State<_ResolutionsMenu> {
  String _groupValue = '';
  Resolution? _localResolution;

  late final TextEditingController _customWidth =
      TextEditingController(text: rect?.width.toInt().toString() ?? '');
  late final TextEditingController _customHeight =
      TextEditingController(text: rect?.height.toInt().toString() ?? '');

  FFI get ffi => widget.ffi;
  PeerInfo get pi => widget.ffi.ffiModel.pi;
  FfiModel get ffiModel => widget.ffi.ffiModel;
  Rect? get rect => scaledRect();
  List<Resolution> get resolutions => pi.resolutions;
  bool get isWayland => bind.mainCurrentIsWayland();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getLocalResolutionWayland();
    });
  }

  Rect? scaledRect() {
    final scale = pi.scaleOfDisplay(pi.currentDisplay);
    final rect = ffiModel.rect;
    if (rect == null) {
      return null;
    }
    return Rect.fromLTWH(
      rect.left,
      rect.top,
      rect.width / scale,
      rect.height / scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVirtualDisplay = ffiModel.isVirtualDisplayResolution;
    final visible = ffiModel.keyboard &&
        (isVirtualDisplay || resolutions.length > 1) &&
        pi.currentDisplay != kAllDisplayValue;
    if (!visible) return Offstage();
    final showOriginalBtn =
        ffiModel.isOriginalResolutionSet && !ffiModel.isOriginalResolution;
    final showFitLocalBtn = !_isRemoteResolutionFitLocal();
    _setGroupValue();
    return _SubmenuButton(
      ffi: widget.ffi,
      menuChildren: <Widget>[
            _OriginalResolutionMenuButton(context, showOriginalBtn),
            _FitLocalResolutionMenuButton(context, showFitLocalBtn),
            _customResolutionMenuButton(context, isVirtualDisplay),
            _menuDivider(showOriginalBtn, showFitLocalBtn, isVirtualDisplay),
          ] +
          _supportedResolutionMenuButtons(),
      child: Text(translate("Resolution")),
    );
  }

  _setGroupValue() {
    if (pi.currentDisplay == kAllDisplayValue) {
      return;
    }
    final lastGroupValue =
        stateGlobal.getLastResolutionGroupValue(widget.id, pi.currentDisplay);
    if (lastGroupValue == _kCustomResolutionValue) {
      _groupValue = _kCustomResolutionValue;
    } else {
      _groupValue =
          '${(rect?.width ?? 0).toInt()}x${(rect?.height ?? 0).toInt()}';
    }
  }

  _menuDivider(
      bool showOriginalBtn, bool showFitLocalBtn, bool isVirtualDisplay) {
    return Offstage(
      offstage: !(showOriginalBtn || showFitLocalBtn || isVirtualDisplay),
      child: Divider(),
    );
  }

  Future<void> _getLocalResolutionWayland() async {
    if (!isWayland) return _getLocalResolution();
    final window = await window_size.getWindowInfo();
    final screen = window.screen;
    if (screen != null) {
      setState(() {
        _localResolution = Resolution(
          screen.frame.width.toInt(),
          screen.frame.height.toInt(),
        );
      });
    }
  }

  _getLocalResolution() {
    _localResolution = null;
    final String mainDisplay = bind.mainGetMainDisplay();
    if (mainDisplay.isNotEmpty) {
      try {
        final display = json.decode(mainDisplay);
        if (display['w'] != null && display['h'] != null) {
          _localResolution = Resolution(display['w'], display['h']);
          if (isWeb) {
            if (display['scaleFactor'] != null) {
              _localResolution = Resolution(
                (display['w'] / display['scaleFactor']).toInt(),
                (display['h'] / display['scaleFactor']).toInt(),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to decode $mainDisplay, $e');
      }
    }
  }

  // This widget has been unmounted, so the State no longer has a context
  _onChanged(String? value) async {
    if (pi.currentDisplay == kAllDisplayValue) {
      return;
    }
    stateGlobal.setLastResolutionGroupValue(
        widget.id, pi.currentDisplay, value);
    if (value == null) return;

    int? w;
    int? h;
    if (value == _kCustomResolutionValue) {
      w = int.tryParse(_customWidth.text);
      h = int.tryParse(_customHeight.text);
    } else {
      final list = value.split('x');
      if (list.length == 2) {
        w = int.tryParse(list[0]);
        h = int.tryParse(list[1]);
      }
    }

    if (w != null && h != null) {
      if (w != rect?.width.toInt() || h != rect?.height.toInt()) {
        await _changeResolution(w, h);
      }
    }
  }

  _changeResolution(int w, int h) async {
    if (pi.currentDisplay == kAllDisplayValue) {
      return;
    }
    await bind.sessionChangeResolution(
      sessionId: ffi.sessionId,
      display: pi.currentDisplay,
      width: w,
      height: h,
    );
    Future.delayed(Duration(seconds: 3), () async {
      final rect = ffiModel.rect;
      if (rect == null) {
        return;
      }
      if (w == rect.width.toInt() && h == rect.height.toInt()) {
        if (await widget.screenAdjustor.isWindowCanBeAdjusted()) {
          widget.screenAdjustor.doAdjustWindow(context);
        }
      }
    });
  }

  Widget _OriginalResolutionMenuButton(
      BuildContext context, bool showOriginalBtn) {
    final display = pi.tryGetDisplayIfNotAllDisplay();
    if (display == null) {
      return Offstage();
    }
    if (!resolutions.any((e) =>
        e.width == display.originalWidth &&
        e.height == display.originalHeight)) {
      return Offstage();
    }
    return Offstage(
      offstage: !showOriginalBtn,
      child: MenuButton(
        onPressed: () =>
            _changeResolution(display.originalWidth, display.originalHeight),
        ffi: widget.ffi,
        child: Text(
            '${translate('resolution_original_tip')} ${display.originalWidth}x${display.originalHeight}'),
      ),
    );
  }

  Widget _FitLocalResolutionMenuButton(
      BuildContext context, bool showFitLocalBtn) {
    return Offstage(
      offstage: !showFitLocalBtn,
      child: MenuButton(
        onPressed: () {
          final resolution = _getBestFitResolution();
          if (resolution != null) {
            _changeResolution(resolution.width, resolution.height);
          }
        },
        ffi: widget.ffi,
        child: Text(
            '${translate('resolution_fit_local_tip')} ${_localResolution?.width ?? 0}x${_localResolution?.height ?? 0}'),
      ),
    );
  }

  Widget _customResolutionMenuButton(BuildContext context, isVirtualDisplay) {
    return Offstage(
      offstage: !isVirtualDisplay,
      child: RdoMenuButton(
        value: _kCustomResolutionValue,
        groupValue: _groupValue,
        onChanged: (String? value) => _onChanged(value),
        ffi: widget.ffi,
        child: Row(
          children: [
            Text('${translate('resolution_custom_tip')} '),
            SizedBox(
              width: _kCustomResolutionEditingWidth,
              child: _resolutionInput(_customWidth),
            ),
            Text(' x '),
            SizedBox(
              width: _kCustomResolutionEditingWidth,
              child: _resolutionInput(_customHeight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resolutionInput(TextEditingController controller) {
    return TextField(
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.fromLTRB(3, 3, 3, 3),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
        FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
      ],
      controller: controller,
    ).workaroundFreezeLinuxMint();
  }

  List<Widget> _supportedResolutionMenuButtons() => resolutions
      .map((e) => RdoMenuButton(
          value: '${e.width}x${e.height}',
          groupValue: _groupValue,
          onChanged: (String? value) => _onChanged(value),
          ffi: widget.ffi,
          child: Text('${e.width}x${e.height}')))
      .toList();

  Resolution? _getBestFitResolution() {
    if (_localResolution == null) {
      return null;
    }

    if (ffiModel.isVirtualDisplayResolution) {
      return _localResolution!;
    }

    for (final r in resolutions) {
      if (r.width == _localResolution!.width &&
          r.height == _localResolution!.height) {
        return r;
      }
    }

    return null;
  }

  bool _isRemoteResolutionFitLocal() {
    if (_localResolution == null) {
      return true;
    }
    final bestFitResolution = _getBestFitResolution();
    if (bestFitResolution == null) {
      return true;
    }
    return bestFitResolution.width == rect?.width.toInt() &&
        bestFitResolution.height == rect?.height.toInt();
  }
}

class _KeyboardMenu extends StatelessWidget {
  final String id;
  final FFI ffi;
  _KeyboardMenu({
    Key? key,
    required this.id,
    required this.ffi,
  }) : super(key: key);

  PeerInfo get pi => ffi.ffiModel.pi;

  @override
  Widget build(BuildContext context) {
    var ffiModel = Provider.of<FfiModel>(context);
    if (!ffiModel.keyboard) return Offstage();
    toolbarToggles() {
      final toggles = toolbarKeyboardToggles(ffi)
          .map((e) => CkbMenuButton(
              value: e.value,
              onChanged: e.onChanged,
              child: e.child,
              ffi: ffi) as Widget)
          .toList();
      if (toggles.isNotEmpty) {
        toggles.add(Divider());
      }
      return toggles;
    }

    return _IconSubmenuButton(
        tooltip: 'Keyboard Settings',
        svg: "assets/keyboard_mouse.svg",
        ffi: ffi,
        color: _ToolbarTheme.blueColor,
        hoverColor: _ToolbarTheme.hoverBlueColor,
        menuChildrenGetter: (_) => [
              keyboardMode(),
              localKeyboardType(),
              inputSource(),
              Divider(),
              viewMode(),
              if ([kPeerPlatformWindows, kPeerPlatformMacOS, kPeerPlatformLinux]
                  .contains(pi.platform))
                showMyCursor(),
              Divider(),
              ...toolbarToggles(),
              ...mouseSpeed(),
              ...mobileActions(),
            ]);
  }

  mouseSpeed() {
    final speedWidgets = [];
    final sessionId = ffi.sessionId;
    if (isDesktop) {
      if (ffi.ffiModel.keyboard) {
        final enabled = !ffi.ffiModel.viewOnly;
        final trackpad = MenuButton(
          child: Text(translate('Trackpad speed')).paddingOnly(left: 26.0),
          onPressed: enabled ? () => trackpadSpeedDialog(sessionId, ffi) : null,
          ffi: ffi,
        );
        speedWidgets.add(trackpad);
      }
    }
    return speedWidgets;
  }

  keyboardMode() {
    return futureBuilder(future: () async {
      return await bind.sessionGetKeyboardMode(sessionId: ffi.sessionId) ??
          kKeyLegacyMode;
    }(), hasData: (data) {
      final groupValue = data as String;
      List<InputModeMenu> modes = [
        InputModeMenu(key: kKeyLegacyMode, menu: 'Legacy mode'),
        InputModeMenu(key: kKeyMapMode, menu: 'Map mode'),
        InputModeMenu(key: kKeyTranslateMode, menu: 'Translate mode'),
      ];
      List<RdoMenuButton> list = [];
      final enabled = !ffi.ffiModel.viewOnly;
      onChanged(String? value) async {
        if (value == null) return;
        await bind.sessionSetKeyboardMode(
            sessionId: ffi.sessionId, value: value);
        await ffi.inputModel.updateKeyboardMode();
      }

      // If use flutter to grab keys, we can only use one mode.
      // Map mode and Legacy mode, at least one of them is supported.
      String? modeOnly;
      // Keep both map and legacy mode on web at the moment.
      // TODO: Remove legacy mode after web supports translate mode on web.
      if (isInputSourceFlutter && isDesktop) {
        if (bind.sessionIsKeyboardModeSupported(
            sessionId: ffi.sessionId, mode: kKeyMapMode)) {
          modeOnly = kKeyMapMode;
        } else if (bind.sessionIsKeyboardModeSupported(
            sessionId: ffi.sessionId, mode: kKeyLegacyMode)) {
          modeOnly = kKeyLegacyMode;
        }
      }

      for (InputModeMenu mode in modes) {
        if (modeOnly != null && mode.key != modeOnly) {
          continue;
        } else if (!bind.sessionIsKeyboardModeSupported(
            sessionId: ffi.sessionId, mode: mode.key)) {
          continue;
        }

        if (pi.isWayland) {
          // Legacy mode is hidden on desktop control side because dead keys
          // don't work properly on Wayland. When the control side is mobile,
          // Legacy mode is used automatically (mobile always sends Legacy events).
          if (mode.key == kKeyLegacyMode) {
            continue;
          }
          // Translate mode requires server >= 1.4.6.
          if (mode.key == kKeyTranslateMode &&
              versionCmp(pi.version, '1.4.6') < 0) {
            continue;
          }
        }

        var text = translate(mode.menu);
        if (mode.key == kKeyTranslateMode) {
          text = '$text beta';
        }
        list.add(RdoMenuButton<String>(
          child: Text(text),
          value: mode.key,
          groupValue: groupValue,
          onChanged: enabled ? onChanged : null,
          ffi: ffi,
        ));
      }
      return Column(children: list);
    });
  }

  localKeyboardType() {
    final localPlatform = getLocalPlatformForKBLayoutType(pi.platform);
    final visible = localPlatform != '';
    if (!visible) return Offstage();
    final enabled = !ffi.ffiModel.viewOnly;
    return Column(
      children: [
        Divider(),
        MenuButton(
          child: Text(
              '${translate('Local keyboard type')}: ${KBLayoutType.value}'),
          trailingIcon: const Icon(Icons.settings),
          ffi: ffi,
          onPressed: enabled
              ? () => showKBLayoutTypeChooser(localPlatform, ffi.dialogManager)
              : null,
        )
      ],
    );
  }

  inputSource() {
    final supportedInputSource = bind.mainSupportedInputSource();
    if (supportedInputSource.isEmpty) return Offstage();
    late final List<dynamic> supportedInputSourceList;
    try {
      supportedInputSourceList = jsonDecode(supportedInputSource);
    } catch (e) {
      debugPrint('Failed to decode $supportedInputSource, $e');
      return;
    }
    if (supportedInputSourceList.length < 2) return Offstage();
    final inputSource = stateGlobal.getInputSource();
    final enabled = !ffi.ffiModel.viewOnly;
    final children = <Widget>[Divider()];
    children.addAll(supportedInputSourceList.map((e) {
      final d = e as List<dynamic>;
      return RdoMenuButton<String>(
        child: Text(translate(d[1] as String)),
        value: d[0] as String,
        groupValue: inputSource,
        onChanged: enabled
            ? (v) async {
                if (v != null) {
                  await stateGlobal.setInputSource(ffi.sessionId, v);
                  await ffi.ffiModel.checkDesktopKeyboardMode();
                  await ffi.inputModel.updateKeyboardMode();
                }
              }
            : null,
        ffi: ffi,
      );
    }));
    return Column(children: children);
  }

  viewMode() {
    final ffiModel = ffi.ffiModel;
    final enabled = versionCmp(pi.version, '1.2.0') >= 0 && ffiModel.keyboard;
    return CkbMenuButton(
        value: ffiModel.viewOnly,
        onChanged: enabled
            ? (value) async {
                if (value == null) return;
                await bind.sessionToggleOption(
                    sessionId: ffi.sessionId, value: kOptionToggleViewOnly);
                final viewOnly = await bind.sessionGetToggleOption(
                    sessionId: ffi.sessionId, arg: kOptionToggleViewOnly);
                ffiModel.setViewOnly(id, viewOnly ?? value);
                final showMyCursor = await bind.sessionGetToggleOption(
                    sessionId: ffi.sessionId, arg: kOptionToggleShowMyCursor);
                ffiModel.setShowMyCursor(showMyCursor ?? value);
              }
            : null,
        ffi: ffi,
        child: Text(translate('View Mode')));
  }

  showMyCursor() {
    final ffiModel = ffi.ffiModel;
    return CkbMenuButton(
            value: ffiModel.showMyCursor,
            onChanged: (value) async {
              if (value == null) return;
              await bind.sessionToggleOption(
                  sessionId: ffi.sessionId, value: kOptionToggleShowMyCursor);
              final showMyCursor = await bind.sessionGetToggleOption(
                      sessionId: ffi.sessionId,
                      arg: kOptionToggleShowMyCursor) ??
                  value;
              ffiModel.setShowMyCursor(showMyCursor);

              // Also set view only if showMyCursor is enabled and viewOnly is not enabled.
              if (showMyCursor && !ffiModel.viewOnly) {
                await bind.sessionToggleOption(
                    sessionId: ffi.sessionId, value: kOptionToggleViewOnly);
                final viewOnly = await bind.sessionGetToggleOption(
                    sessionId: ffi.sessionId, arg: kOptionToggleViewOnly);
                ffiModel.setViewOnly(id, viewOnly ?? value);
              }
            },
            ffi: ffi,
            child: Text(translate('Show my cursor')))
        .paddingOnly(left: 26.0);
  }

  mobileActions() {
    if (pi.platform != kPeerPlatformAndroid) return [];
    final enabled = versionCmp(pi.version, '1.2.7') >= 0;
    if (!enabled) return [];
    return [
      Divider(),
      MenuButton(
          child: Text(translate('Back')),
          onPressed: () => ffi.inputModel.onMobileBack(),
          ffi: ffi),
      MenuButton(
          child: Text(translate('Home')),
          onPressed: () => ffi.inputModel.onMobileHome(),
          ffi: ffi),
      MenuButton(
          child: Text(translate('Apps')),
          onPressed: () => ffi.inputModel.onMobileApps(),
          ffi: ffi),
      MenuButton(
          child: Text(translate('Volume up')),
          onPressed: () => ffi.inputModel.onMobileVolumeUp(),
          ffi: ffi),
      MenuButton(
          child: Text(translate('Volume down')),
          onPressed: () => ffi.inputModel.onMobileVolumeDown(),
          ffi: ffi),
      MenuButton(
          child: Text(translate('Power')),
          onPressed: () => ffi.inputModel.onMobilePower(),
          ffi: ffi),
    ];
  }
}

class _ChatMenu extends StatefulWidget {
  final String id;
  final FFI ffi;
  _ChatMenu({
    Key? key,
    required this.id,
    required this.ffi,
  }) : super(key: key);

  @override
  State<_ChatMenu> createState() => _ChatMenuState();
}

class _ChatMenuState extends State<_ChatMenu> {
  // Using in StatelessWidget got `Looking up a deactivated widget's ancestor is unsafe`.
  final chatButtonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    if (isWeb) {
      return buildTextChatButton();
    } else {
      return _IconSubmenuButton(
          tooltip: 'Chat',
          key: chatButtonKey,
          svg: 'assets/chat.svg',
          ffi: widget.ffi,
          color: _ToolbarTheme.blueColor,
          hoverColor: _ToolbarTheme.hoverBlueColor,
          menuChildrenGetter: (_) => [textChat(), voiceCall()]);
    }
  }

  buildTextChatButton() {
    return _IconMenuButton(
      assetName: 'assets/message_24dp_5F6368.svg',
      tooltip: 'Text chat',
      key: chatButtonKey,
      onPressed: _textChatOnPressed,
      color: _ToolbarTheme.blueColor,
      hoverColor: _ToolbarTheme.hoverBlueColor,
    );
  }

  textChat() {
    return MenuButton(
        child: Text(translate('Text chat')),
        ffi: widget.ffi,
        onPressed: _textChatOnPressed);
  }

  _textChatOnPressed() {
    RenderBox? renderBox =
        chatButtonKey.currentContext?.findRenderObject() as RenderBox?;
    Offset? initPos;
    if (renderBox != null) {
      final pos = renderBox.localToGlobal(Offset.zero);
      initPos = Offset(pos.dx, pos.dy + _ToolbarTheme.dividerHeight);
    }
    widget.ffi.chatModel
        .changeCurrentKey(MessageKey(widget.ffi.id, ChatModel.clientModeID));
    widget.ffi.chatModel.toggleChatOverlay(chatInitPos: initPos);
  }

  voiceCall() {
    return MenuButton(
      child: Text(translate('Voice call')),
      ffi: widget.ffi,
      onPressed: () =>
          bind.sessionRequestVoiceCall(sessionId: widget.ffi.sessionId),
    );
  }
}

class _VoiceCallMenu extends StatelessWidget {
  final String id;
  final FFI ffi;
  _VoiceCallMenu({
    Key? key,
    required this.id,
    required this.ffi,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    menuChildrenGetter(_IconSubmenuButtonState state) {
      final audioInput = AudioInput(
        builder: (devices, currentDevice, setDevice) {
          return Column(
            children: devices
                .map((d) => RdoMenuButton<String>(
                      child: Container(
                        child: Text(
                          d,
                          overflow: TextOverflow.ellipsis,
                        ),
                        constraints: BoxConstraints(maxWidth: 250),
                      ),
                      value: d,
                      groupValue: currentDevice,
                      onChanged: (v) {
                        if (v != null) setDevice(v);
                      },
                      ffi: ffi,
                    ))
                .toList(),
          );
        },
        isCm: false,
        isVoiceCall: true,
      );
      return [
        audioInput,
        Divider(),
        MenuButton(
          child: Text(translate('End call')),
          onPressed: () => bind.sessionCloseVoiceCall(sessionId: ffi.sessionId),
          ffi: ffi,
        ),
      ];
    }

    return Obx(
      () {
        switch (ffi.chatModel.voiceCallStatus.value) {
          case VoiceCallStatus.waitingForResponse:
            return buildCallWaiting(context);
          case VoiceCallStatus.connected:
            return _IconSubmenuButton(
              tooltip: 'Voice call',
              svg: 'assets/voice_call.svg',
              color: _ToolbarTheme.blueColor,
              hoverColor: _ToolbarTheme.hoverBlueColor,
              menuChildrenGetter: menuChildrenGetter,
              ffi: ffi,
            );
          default:
            return Offstage();
        }
      },
    );
  }

  Widget buildCallWaiting(BuildContext context) {
    return _IconMenuButton(
      assetName: "assets/call_wait.svg",
      tooltip: "Waiting",
      onPressed: () => bind.sessionCloseVoiceCall(sessionId: ffi.sessionId),
      color: _ToolbarTheme.redColor,
      hoverColor: _ToolbarTheme.hoverRedColor,
    );
  }
}

// TajDesk stage 12: live recording indicator.
// While a session is being recorded we draw a small red dot in the top-right
// corner of the rec button and pulse it with an opacity + glow loop so it's
// obvious from across the room that recording is active. When recording is
// off, the widget collapses to the original behaviour.
class _RecordMenu extends StatefulWidget {
  const _RecordMenu({Key? key}) : super(key: key);

  @override
  State<_RecordMenu> createState() => _RecordMenuState();
}

class _RecordMenuState extends State<_RecordMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var ffi = Provider.of<FfiModel>(context);
    var recordingModel = Provider.of<RecordingModel>(context);
    final visible =
        (recordingModel.start || ffi.permissions['recording'] != false);
    if (!visible) return Offstage();

    final isRecording = recordingModel.start;
    // Keep the pulse animation in sync with the recording state. We do this
    // in build (rather than didUpdateWidget) because the trigger comes from
    // the provider, not from a widget config change.
    if (isRecording) {
      if (!_pulse.isAnimating) {
        _pulse.repeat(reverse: true);
      }
    } else {
      if (_pulse.isAnimating) {
        _pulse.stop();
      }
      _pulse.value = 0.0;
    }

    final btn = _IconMenuButton(
      assetName: 'assets/rec.svg',
      tooltip: isRecording
          ? 'Stop session recording'
          : 'Start session recording',
      onPressed: () => recordingModel.toggle(),
      color: isRecording
          ? _ToolbarTheme.redColor
          : _ToolbarTheme.blueColor,
      hoverColor: isRecording
          ? _ToolbarTheme.hoverRedColor
          : _ToolbarTheme.hoverBlueColor,
    );

    if (!isRecording) return btn;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        btn,
        Positioned(
          top: 6,
          right: 4,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final t = _pulse.value;
                return Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                      const Color(0xFFFF5252).withOpacity(0.55),
                      const Color(0xFFFF1744),
                      t,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFFFF1744).withOpacity(0.25 + 0.40 * t),
                        blurRadius: 5 + 5 * t,
                        spreadRadius: 0.5 + 1.0 * t,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _CloseMenu extends StatelessWidget {
  final String id;
  final FFI ffi;
  const _CloseMenu({Key? key, required this.id, required this.ffi})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _IconMenuButton(
      assetName: 'assets/close.svg',
      tooltip: 'Close',
      onPressed: () async {
        if (await showConnEndAuditDialogCloseCanceled(ffi: ffi)) {
          return;
        }
        closeConnection(id: id);
      },
      color: _ToolbarTheme.redColor,
      hoverColor: _ToolbarTheme.hoverRedColor,
    );
  }
}

class _IconMenuButton extends StatefulWidget {
  final String? assetName;
  final Widget? icon;
  final String tooltip;
  final Color color;
  final Color hoverColor;
  final VoidCallback? onPressed;
  final double? hMargin;
  final double? vMargin;
  final bool topLevel;
  final double? width;
  const _IconMenuButton({
    Key? key,
    this.assetName,
    this.icon,
    required this.tooltip,
    required this.color,
    required this.hoverColor,
    required this.onPressed,
    this.hMargin,
    this.vMargin,
    this.topLevel = true,
    this.width,
  }) : super(key: key);

  @override
  State<_IconMenuButton> createState() => _IconMenuButtonState();
}

class _IconMenuButtonState extends State<_IconMenuButton> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    assert(widget.assetName != null || widget.icon != null);
    final icon = widget.icon ??
        SvgPicture.asset(
          widget.assetName!,
          colorFilter: ColorFilter.mode(Colors.white, BlendMode.srcIn),
          width: _ToolbarTheme.buttonSize,
          height: _ToolbarTheme.buttonSize,
        );
    var button = SizedBox(
      width: widget.width ?? _ToolbarTheme.buttonSize,
      height: _ToolbarTheme.buttonSize,
      child: MenuItemButton(
          style: ButtonStyle(
              backgroundColor: MaterialStatePropertyAll(Colors.transparent),
              padding: MaterialStatePropertyAll(EdgeInsets.zero),
              overlayColor: MaterialStatePropertyAll(Colors.transparent)),
          onHover: (value) => setState(() {
                hover = value;
              }),
          onPressed: widget.onPressed,
          child: Tooltip(
            message: translate(widget.tooltip),
            child: Material(
                type: MaterialType.transparency,
                child: Ink(
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(_ToolbarTheme.iconRadius),
                      color: hover ? widget.hoverColor : widget.color,
                    ),
                    child: icon)),
          )),
    ).marginSymmetric(
        horizontal: widget.hMargin ?? _ToolbarTheme.buttonHMargin,
        vertical: widget.vMargin ?? _ToolbarTheme.buttonVMargin);
    button = Tooltip(
      message: widget.tooltip,
      child: button,
    );
    if (widget.topLevel) {
      return MenuBar(children: [button]);
    } else {
      return button;
    }
  }
}

class _IconSubmenuButton extends StatefulWidget {
  final String tooltip;
  final String? svg;
  final Widget? icon;
  final Color color;
  final Color hoverColor;
  final List<Widget> Function(_IconSubmenuButtonState state) menuChildrenGetter;
  final MenuStyle? menuStyle;
  final FFI? ffi;
  final double? width;

  _IconSubmenuButton({
    Key? key,
    this.svg,
    this.icon,
    required this.tooltip,
    required this.color,
    required this.hoverColor,
    required this.menuChildrenGetter,
    this.ffi,
    this.menuStyle,
    this.width,
  }) : super(key: key);

  @override
  State<_IconSubmenuButton> createState() => _IconSubmenuButtonState();
}

class _IconSubmenuButtonState extends State<_IconSubmenuButton> {
  bool hover = false;

  @override // discard @protected
  void setState(VoidCallback fn) {
    super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.svg != null || widget.icon != null);
    final icon = widget.icon ??
        SvgPicture.asset(
          widget.svg!,
          colorFilter: ColorFilter.mode(Colors.white, BlendMode.srcIn),
          width: _ToolbarTheme.buttonSize,
          height: _ToolbarTheme.buttonSize,
        );
    final button = SizedBox(
        width: widget.width ?? _ToolbarTheme.buttonSize,
        height: _ToolbarTheme.buttonSize,
        child: SubmenuButton(
            menuStyle:
                widget.menuStyle ?? _ToolbarTheme.defaultMenuStyle(context),
            style: _ToolbarTheme.defaultMenuButtonStyle,
            onHover: (value) => setState(() {
                  hover = value;
                }),
            child: Tooltip(
                message: translate(widget.tooltip),
                child: Material(
                    type: MaterialType.transparency,
                    child: Ink(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(_ToolbarTheme.iconRadius),
                          color: hover ? widget.hoverColor : widget.color,
                        ),
                        child: icon))),
            menuChildren: widget
                .menuChildrenGetter(this)
                .map((e) => _buildPointerTrackWidget(e, widget.ffi))
                .toList()));
    return MenuBar(children: [
      button.marginSymmetric(
          horizontal: _ToolbarTheme.buttonHMargin,
          vertical: _ToolbarTheme.buttonVMargin)
    ]);
  }
}

class _SubmenuButton extends StatelessWidget {
  final List<Widget> menuChildren;
  final Widget? child;
  final FFI ffi;
  const _SubmenuButton({
    Key? key,
    required this.menuChildren,
    required this.child,
    required this.ffi,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SubmenuButton(
      key: key,
      child: child,
      menuChildren:
          menuChildren.map((e) => _buildPointerTrackWidget(e, ffi)).toList(),
      menuStyle: _ToolbarTheme.defaultMenuStyle(context),
    );
  }
}

class MenuButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget? trailingIcon;
  final Widget? child;
  final FFI? ffi;
  MenuButton(
      {Key? key,
      this.onPressed,
      this.trailingIcon,
      required this.child,
      this.ffi})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MenuItemButton(
        key: key,
        onPressed: onPressed != null
            ? () {
                if (ffi != null) {
                  _menuDismissCallback(ffi!);
                }
                onPressed?.call();
              }
            : null,
        trailingIcon: trailingIcon,
        child: child);
  }
}

class CkbMenuButton extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final Widget? child;
  final FFI? ffi;
  const CkbMenuButton(
      {Key? key,
      required this.value,
      required this.onChanged,
      required this.child,
      this.ffi})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CheckboxMenuButton(
      key: key,
      value: value,
      child: child,
      onChanged: onChanged != null
          ? (bool? value) {
              if (ffi != null) {
                _menuDismissCallback(ffi!);
              }
              onChanged?.call(value);
            }
          : null,
    );
  }
}

class RdoMenuButton<T> extends StatelessWidget {
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final Widget? child;
  final FFI? ffi;
  // When true, submenu will be dismissed on activate; when false, it stays open.
  final bool closeOnActivate;
  const RdoMenuButton({
    Key? key,
    required this.value,
    required this.groupValue,
    required this.child,
    this.ffi,
    this.onChanged,
    this.closeOnActivate = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RadioMenuButton(
      value: value,
      groupValue: groupValue,
      child: child,
      closeOnActivate: closeOnActivate,
      onChanged: onChanged != null
          ? (T? value) {
              if (ffi != null && closeOnActivate) {
                _menuDismissCallback(ffi!);
              }
              onChanged?.call(value);
            }
          : null,
    );
  }
}

class _DraggableShowHide extends StatefulWidget {
  final String id;
  final SessionID sessionId;
  final RxDouble fractionX;
  final RxBool dragging;
  final ToolbarState toolbarState;
  final BorderRadius borderRadius;

  final Function(bool) setFullscreen;
  final Function() setMinimize;

  const _DraggableShowHide({
    Key? key,
    required this.id,
    required this.sessionId,
    required this.fractionX,
    required this.dragging,
    required this.toolbarState,
    required this.setFullscreen,
    required this.setMinimize,
    required this.borderRadius,
  }) : super(key: key);

  @override
  State<_DraggableShowHide> createState() => _DraggableShowHideState();
}

class _DraggableShowHideState extends State<_DraggableShowHide> {
  Offset position = Offset.zero;
  Size size = Size.zero;
  double left = 0.0;
  double right = 1.0;

  RxBool get collapse => widget.toolbarState.collapse;

  @override
  initState() {
    super.initState();

    final confLeft = double.tryParse(
        bind.mainGetLocalOption(key: kOptionRemoteMenubarDragLeft));
    if (confLeft == null) {
      bind.mainSetLocalOption(
          key: kOptionRemoteMenubarDragLeft, value: left.toString());
    } else {
      left = confLeft;
    }
    final confRight = double.tryParse(
        bind.mainGetLocalOption(key: kOptionRemoteMenubarDragRight));
    if (confRight == null) {
      bind.mainSetLocalOption(
          key: kOptionRemoteMenubarDragRight, value: right.toString());
    } else {
      right = confRight;
    }
  }

  Widget _buildDraggable(BuildContext context) {
    // TajDesk stage 12: a more visible drag handle on the collapsed chip.
    // The stock Material `drag_indicator` glyph in the default theme colour
    // tends to disappear against the frosted-glass background, leaving
    // first-time users with no clue the chip can be dragged. We keep the
    // same 2×3 dot grid (familiar pattern from Notion / Linear) but force
    // a white tint with a clearly readable opacity, plus a touch of left
    // padding so it doesn't kiss the chip border.
    return Draggable(
      axis: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Icon(
          Icons.drag_indicator,
          size: 14,
          color: Colors.white.withOpacity(0.4),
        ),
      ),
      feedback: widget,
      onDragStarted: (() {
        final RenderObject? renderObj = context.findRenderObject();
        if (renderObj != null) {
          final RenderBox renderBox = renderObj as RenderBox;
          size = renderBox.size;
          position = renderBox.localToGlobal(Offset.zero);
        }
        widget.dragging.value = true;
      }),
      onDragEnd: (details) {
        // TajDesk stage 18: new _fractionX semantics — it now represents the
        // chip's centre as a fraction of the screen width (was: chip left
        // edge as a fraction of [0, screen - chip_w]). So the delta scales
        // by screenW directly, not by (screenW - chipW).
        //
        // Movement: pointer (and feedback) moved by `delta_x` pixels.
        // chip centre also moves by `delta_x` pixels → fraction moves by
        // delta_x / screenW.
        //
        // After updating, clamp so the chip's centre stays at least chipW/2
        // away from each screen edge — i.e., the whole chip stays visible.
        // The legacy `left` / `right` bounds from
        // kOptionRemoteMenubarDragLeft/Right are ignored here; the
        // on-screen clamp is enough and is always correct regardless of
        // user-set values.
        final mediaSize = MediaQueryData.fromView(View.of(context)).size;
        final screenW = mediaSize.width;
        final chipW = size.width > 0 ? size.width : 120.0;
        final deltaX = details.offset.dx - position.dx;

        var newFraction = widget.fractionX.value + deltaX / screenW;
        final minF = (chipW / 2) / screenW;
        final maxF = 1.0 - minF;
        if (newFraction < minF) newFraction = minF;
        if (newFraction > maxF) newFraction = maxF;
        widget.fractionX.value = newFraction;

        bind.sessionPeerOption(
          sessionId: widget.sessionId,
          name: 'remote-menubar-drag-x',
          value: widget.fractionX.value.toString(),
        );
        widget.dragging.value = false;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ButtonStyle buttonStyle = ButtonStyle(
      minimumSize: MaterialStateProperty.all(const Size(0, 0)),
      padding: MaterialStateProperty.all(EdgeInsets.zero),
    );
    final isFullscreen = stateGlobal.fullscreen;
    const double iconSize = 16;

    buttonWrapper(VoidCallback? onPressed, Widget child,
        {Color? hoverColor}) {
      final bgColor = buttonStyle.backgroundColor?.resolve({});
      final effectiveHover = hoverColor ?? _ToolbarTheme.blueColor;
      return TextButton(
        onPressed: onPressed,
        child: child,
        style: buttonStyle.copyWith(
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.hovered)) {
              return (bgColor ?? effectiveHover).withOpacity(0.15);
            }
            return bgColor;
          }),
        ),
      );
    }

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDraggable(context),
        Obx(() => buttonWrapper(
              () {
                widget.setFullscreen(!isFullscreen.value);
              },
              Tooltip(
                message: translate(
                    isFullscreen.isTrue ? 'Exit Fullscreen' : 'Fullscreen'),
                child: Icon(
                  isFullscreen.isTrue
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  size: iconSize,
                ),
              ),
            )),
        if (!isMacOS && !isWebDesktop)
          Obx(() => Offstage(
                offstage: isFullscreen.isFalse,
                child: buttonWrapper(
                  widget.setMinimize,
                  Tooltip(
                    message: translate('Minimize'),
                    child: Icon(
                      Icons.remove,
                      size: iconSize,
                    ),
                  ),
                ),
              )),
        buttonWrapper(
          () => setState(() {
            widget.toolbarState.switchCollapse(widget.sessionId);
          }),
          Obx((() => Tooltip(
                message: translate(
                    collapse.isFalse ? 'Hide Toolbar' : 'Show Toolbar'),
                child: Icon(
                  collapse.isFalse ? Icons.expand_less : Icons.expand_more,
                  size: iconSize,
                ),
              ))),
        ),
        if (isWebDesktop)
          Obx(() {
            if (collapse.isFalse) {
              return Offstage();
            } else {
              return buttonWrapper(
                () => closeConnection(id: widget.id),
                Tooltip(
                  message: translate('Close'),
                  child: Icon(
                    Icons.close,
                    size: iconSize,
                    color: _ToolbarTheme.redColor,
                  ),
                ),
                hoverColor: _ToolbarTheme.redColor,
              ).paddingOnly(left: iconSize / 2);
            }
          })
      ],
    );
    return TextButtonTheme(
      data: TextButtonThemeData(style: buttonStyle),
      // TajDesk: frosted-glass floating chip instead of solid container.
      child: ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 1,
              ),
              borderRadius:
                  widget.borderRadius ?? BorderRadius.circular(12),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SizedBox(
              height: 24,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class InputModeMenu {
  final String key;
  final String menu;

  InputModeMenu({required this.key, required this.menu});
}

_menuDismissCallback(FFI ffi) => ffi.inputModel.refreshMousePos();

Widget _buildPointerTrackWidget(Widget child, FFI? ffi) {
  return Listener(
    onPointerHover: (PointerHoverEvent e) => {
      if (ffi != null) {ffi.inputModel.lastMousePos = e.position}
    },
    child: MouseRegion(
      child: child,
    ),
  );
}

class EdgeThicknessControl extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final ColorScheme? colorScheme;

  const EdgeThicknessControl({
    Key? key,
    required this.value,
    this.onChanged,
    this.colorScheme,
  }) : super(key: key);

  static const double kMin = 20;
  static const double kMax = 150;

  @override
  Widget build(BuildContext context) {
    final colorScheme = this.colorScheme ?? Theme.of(context).colorScheme;

    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: colorScheme.primary,
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withOpacity(0.1),
        showValueIndicator: ShowValueIndicator.never,
        thumbShape: _RectValueThumbShape(
          min: EdgeThicknessControl.kMin,
          max: EdgeThicknessControl.kMax,
          width: 52,
          height: 24,
          radius: 4,
          unit: 'px',
        ),
      ),
      child: Semantics(
        value: value.toInt().toString(),
        child: Slider(
          value: value,
          min: EdgeThicknessControl.kMin,
          max: EdgeThicknessControl.kMax,
          divisions:
              (EdgeThicknessControl.kMax - EdgeThicknessControl.kMin).round(),
          semanticFormatterCallback: (double newValue) =>
              "${newValue.round()}px",
          onChanged: onChanged,
        ),
      ),
    );

    return slider;
  }
}

// TajDesk stage 18: tiny helper that reports the measured size of its
// child after every frame. Used by _RemoteToolbarState to track the real
// rendered widths of the toolbar panel and the chip, so the Stack +
// Positioned layout can centre them on the same pixel coordinate.
//
// Renders via SizedBox (no visual wrapping — SizedBox without explicit
// width/height just shrink-wraps to its child). A GlobalKey gives access
// to the rendered RenderBox in a post-frame callback. The callback is
// re-registered on every build so size changes from subsequent rebuilds
// are picked up too.
class _MeasureSize extends StatefulWidget {
  final Widget child;
  final ValueChanged<Size> onChange;

  const _MeasureSize({
    Key? key,
    required this.child,
    required this.onChange,
  }) : super(key: key);

  @override
  State<_MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<_MeasureSize> {
  final GlobalKey _key = GlobalKey();
  Size? _previousSize;

  void _schedulePostFrame() {
    WidgetsBinding.instance.addPostFrameCallback(_postFrame);
  }

  @override
  void initState() {
    super.initState();
    _schedulePostFrame();
  }

  @override
  void didUpdateWidget(_MeasureSize oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePostFrame();
  }

  void _postFrame(Duration _) {
    if (!mounted) return;
    final ctx = _key.currentContext;
    if (ctx == null) return;
    final size = ctx.size;
    if (size == null || size.isEmpty) return;
    if (size != _previousSize) {
      _previousSize = size;
      widget.onChange(size);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(key: _key, child: widget.child);
  }
}
