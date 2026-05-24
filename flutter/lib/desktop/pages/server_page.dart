// original cm window in Sciter version.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/cm_file_model.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/file_model.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';

class DesktopServerPage extends StatefulWidget {
  const DesktopServerPage({Key? key}) : super(key: key);

  @override
  State<DesktopServerPage> createState() => _DesktopServerPageState();
}

class _DesktopServerPageState extends State<DesktopServerPage>
    with WindowListener, AutomaticKeepAliveClientMixin {
  final tabController = gFFI.serverModel.tabController;

  _DesktopServerPageState() {
    gFFI.ffiModel.updateEventListener(gFFI.sessionId, "");
    Get.put<DesktopTabController>(tabController);
    tabController.onRemoved = (_, id) {
      onRemoveId(id);
    };
  }

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    Future.wait([gFFI.serverModel.closeAll(), gFFI.close()]).then((_) {
      if (isMacOS) {
        RdPlatformChannel.instance.terminate();
      } else {
        windowManager.setPreventClose(false);
        windowManager.close();
      }
    });
    super.onWindowClose();
  }

  void onRemoveId(String id) {
    if (tabController.state.value.tabs.isEmpty) {
      windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gFFI.serverModel),
        ChangeNotifierProvider.value(value: gFFI.chatModel),
      ],
      child: Consumer<ServerModel>(
        builder: (context, serverModel, child) {
          final body = Scaffold(
            backgroundColor: Theme.of(context).colorScheme.background,
            body: ConnectionManager(),
          );
          return isLinux
              ? buildVirtualWindowFrame(context, body)
              : workaroundWindowBorder(
                  context,
                  Container(
                    decoration: BoxDecoration(
                        border:
                            Border.all(color: MyTheme.color(context).border!)),
                    child: body,
                  ));
        },
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class ConnectionManager extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => ConnectionManagerState();
}

class ConnectionManagerState extends State<ConnectionManager>
    with WidgetsBindingObserver {
  final RxBool _controlPageBlock = false.obs;
  final RxBool _sidePageBlock = false.obs;

  ConnectionManagerState() {
    gFFI.serverModel.tabController.onSelected = (client_id_str) {
      final client_id = int.tryParse(client_id_str);
      if (client_id != null) {
        final client =
            gFFI.serverModel.clients.firstWhereOrNull((e) => e.id == client_id);
        if (client != null) {
          gFFI.chatModel.changeCurrentKey(MessageKey(client.peerId, client.id));
          if (client.unreadChatMessageCount.value > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              client.unreadChatMessageCount.value = 0;
              gFFI.chatModel.showChatPage(MessageKey(client.peerId, client.id));
            });
          }
          windowManager.setTitle(getWindowNameWithId(client.peerId));
          gFFI.cmFileModel.updateCurrentClientId(client.id);
        }
      }
    };
    gFFI.chatModel.isConnManager = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (!allowRemoteCMModification()) {
        shouldBeBlocked(_controlPageBlock, null);
        shouldBeBlocked(_sidePageBlock, null);
      }
    }
  }

  @override
  void initState() {
    gFFI.serverModel.updateClientState();
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    pointerHandler(PointerEvent e) {
      if (serverModel.cmHiddenTimer != null) {
        serverModel.cmHiddenTimer!.cancel();
        serverModel.cmHiddenTimer = null;
        debugPrint("CM hidden timer has been canceled");
      }
    }

    return serverModel.clients.isEmpty
        ? Column(
            children: [
              buildTitleBar(),
              Expanded(
                child: Center(
                  child: Text(translate("Waiting")),
                ),
              ),
            ],
          )
        : Listener(
            onPointerDown: pointerHandler,
            onPointerMove: pointerHandler,
            child: DesktopTab(
              showTitle: false,
              showMaximize: false,
              showMinimize: true,
              showClose: true,
              onWindowCloseButton: handleWindowCloseButton,
              controller: serverModel.tabController,
              selectedBorderColor: MyTheme.accent,
              maxLabelWidth: 100,
              tail: null, //buildScrollJumper(),
              tabBuilder: (key, icon, label, themeConf) {
                final client = serverModel.clients
                    .firstWhereOrNull((client) => client.id.toString() == key);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Tooltip(
                        message: key,
                        waitDuration: Duration(seconds: 1),
                        child: label),
                    unreadMessageCountBuilder(client?.unreadChatMessageCount)
                        .marginOnly(left: 4),
                  ],
                );
              },
              pageViewBuilder: (pageView) => LayoutBuilder(
                builder: (context, constrains) {
                  // TajDesk stage 43: the chat side-panel is only shown AFTER
                  // the connection is authorized. Before the user accepts, a
                  // chat makes no sense (the peer isn't connected yet) and just
                  // left an empty pane when the window was widened. So even if
                  // the window is wide, we hide chat until `authorized`.
                  final selIdx = serverModel.tabController.state.value.selected;
                  final selClient = (selIdx >= 0 &&
                          selIdx < serverModel.clients.length)
                      ? serverModel.clients[selIdx]
                      : null;
                  final chatAuthorized = selClient?.authorized ?? false;
                  final wantChat = chatAuthorized &&
                      constrains.maxWidth >
                          kConnectionManagerWindowSizeClosedChat.width;
                  var borderWidth = 0.0;
                  if (constrains.maxWidth >
                      kConnectionManagerWindowSizeClosedChat.width) {
                    borderWidth = kConnectionManagerWindowSizeOpenChat.width -
                        constrains.maxWidth;
                  } else {
                    borderWidth = kConnectionManagerWindowSizeClosedChat.width -
                        constrains.maxWidth;
                  }
                  if (borderWidth < 0 || borderWidth > 50) {
                    borderWidth = 0;
                  }
                  // When chat is hidden, the control page takes the full width.
                  final realClosedWidth = wantChat
                      ? kConnectionManagerWindowSizeClosedChat.width -
                          borderWidth
                      : constrains.maxWidth;
                  final realChatPageWidth =
                      constrains.maxWidth - realClosedWidth;
                  final row = Row(children: [
                    if (wantChat)
                      Consumer<ChatModel>(
                          builder: (_, model, child) => SizedBox(
                                width: realChatPageWidth,
                                child: allowRemoteCMModification()
                                    ? buildSidePage()
                                    : buildRemoteBlock(
                                        child: buildSidePage(),
                                        block: _sidePageBlock,
                                        mask: true),
                              )),
                    SizedBox(
                        width: realClosedWidth,
                        child: SizedBox(
                            width: realClosedWidth,
                            child: allowRemoteCMModification()
                                ? pageView
                                : buildRemoteBlock(
                                    child: _buildKeyEventBlock(pageView),
                                    block: _controlPageBlock,
                                    mask: false,
                                  ))),
                  ]);
                  return Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: row,
                  );
                },
              ),
            ),
          );
  }

  Widget buildSidePage() {
    final selected = gFFI.serverModel.tabController.state.value.selected;
    if (selected < 0 || selected >= gFFI.serverModel.clients.length) {
      return Offstage();
    }
    final clientType = gFFI.serverModel.clients[selected].type_();
    if (clientType == ClientType.file) {
      return _FileTransferLogPage();
    } else {
      return ChatPage(type: ChatPageType.desktopCM);
    }
  }

  Widget _buildKeyEventBlock(Widget child) {
    return ExcludeFocus(child: child, excluding: true);
  }

  Widget buildTitleBar() {
    return SizedBox(
      height: kDesktopRemoteTabBarHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _AppIcon(),
          Expanded(
            child: GestureDetector(
              onPanStart: (d) {
                windowManager.startDragging();
              },
              child: Container(
                color: Theme.of(context).colorScheme.background,
              ),
            ),
          ),
          const SizedBox(
            width: 4.0,
          ),
          const _CloseButton()
        ],
      ),
    );
  }

  Widget buildScrollJumper() {
    final offstage = gFFI.serverModel.clients.length < 2;
    final sc = gFFI.serverModel.tabController.state.value.scrollController;
    return Offstage(
        offstage: offstage,
        child: Row(
          children: [
            ActionIcon(
                icon: Icons.arrow_left, iconSize: 22, onTap: sc.backward),
            ActionIcon(
                icon: Icons.arrow_right, iconSize: 22, onTap: sc.forward),
          ],
        ));
  }

  Future<bool> handleWindowCloseButton() async {
    var tabController = gFFI.serverModel.tabController;
    final connLength = tabController.length;
    if (connLength <= 1) {
      windowManager.close();
      return true;
    } else {
      final bool res;
      if (!option2bool(kOptionEnableConfirmClosingTabs,
          bind.mainGetLocalOption(key: kOptionEnableConfirmClosingTabs))) {
        res = true;
      } else {
        res = await closeConfirmDialog();
      }
      if (res) {
        windowManager.close();
      }
      return res;
    }
  }
}

Widget buildConnectionCard(Client client) {
  return Consumer<ServerModel>(
    builder: (context, value, child) {
      // TajDesk stage 21: three-zone layout so the request stays usable in a
      // small window:
      //   1. header  — pinned at the top, never scrolls
      //   2. permissions — the only flexible zone; scrolls when it doesn't fit
      //   3. control bar — pinned at the bottom (sticky), so Accept / Reject
      //      are ALWAYS reachable regardless of how many permission rows there
      //      are or how short the window is.
      final showPrivilege = !(client.type_() == ClientType.file ||
          client.type_() == ClientType.portForward ||
          client.type_() == ClientType.terminal ||
          client.disconnected);
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        key: ValueKey(client.id),
        children: [
          _CmHeader(client: client),
          // Flexible middle zone. When there are permissions we let them
          // scroll inside the remaining space; otherwise an empty Spacer keeps
          // the control bar pinned to the bottom.
          if (showPrivilege)
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: _PrivilegeBoard(client: client),
              ),
            )
          else
            const Spacer(),
          // Sticky bottom control bar.
          _CmStickyBar(child: _CmControlPanel(client: client)),
        ],
      ).paddingSymmetric(vertical: 4.0, horizontal: 8.0);
    },
  );
}

// TajDesk stage 21: thin wrapper that pins the control buttons to the bottom
// of the window with a soft top hairline + shadow, so the scrolling permission
// list visually slides *under* it rather than colliding with the buttons.
class _CmStickyBar extends StatelessWidget {
  final Widget child;
  const _CmStickyBar({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.06)
                : Colors.black.withOpacity(0.06),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.only(top: 6),
      child: child,
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.0),
      child: loadIcon(30),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        windowManager.close();
      },
      icon: const Icon(
        IconFont.close,
        size: 18,
      ),
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
    );
  }
}

class _CmHeader extends StatefulWidget {
  final Client client;

  const _CmHeader({Key? key, required this.client}) : super(key: key);

  @override
  State<_CmHeader> createState() => _CmHeaderState();
}

class _CmHeaderState extends State<_CmHeader>
    with AutomaticKeepAliveClientMixin {
  Client get client => widget.client;

  final _time = 0.obs;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      if (client.authorized && !client.disconnected) {
        _time.value = _time.value + 1;
      }
    });
    // Call onSelected in post frame callback, since we cannot guarantee that the callback will not call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gFFI.serverModel.tabController.onSelected?.call(client.id.toString());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // TajDesk stage 19: replaced the screaming cyan-blue gradient header with
    // a quiet graphite card that picks up our brand accent only as a thin
    // top-edge highlight. Premium-app feel (think macOS / Linear) instead of
    // consumer-app cheerfulness. The status line below shows a small coloured
    // dot for at-a-glance state (orange = pending request, green = connected,
    // grey = disconnected).
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        isDark ? const Color(0xFF1A1E2A) : const Color(0xFFF5F6F9);
    final primaryText =
        isDark ? Colors.white : const Color(0xFF1A1E2A);
    final secondaryText = isDark
        ? Colors.white.withOpacity(0.55)
        : Colors.black.withOpacity(0.55);
    final accent = MyTheme.accent;
    final statusColor = client.authorized
        ? (client.disconnected
            ? const Color(0xFF8C95A4) // grey
            : const Color(0xFF22C55E)) // green
        : const Color(0xFFF59E0B); // amber — pending request
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14.0),
        color: cardColor,
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // TajDesk stage 21: tighter margins/padding to reclaim vertical space
      // for the permission list in a small window.
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thin accent highlight strip at the top — only colour intrusion.
          Container(
            height: 2,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withOpacity(0.0),
                  accent.withOpacity(0.85),
                  accent.withOpacity(0.0),
                ],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildClientAvatar().marginOnly(right: 12.0),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                        child: Text(
                      client.name,
                      style: TextStyle(
                        color: primaryText,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        letterSpacing: -0.2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      maxLines: 1,
                    )),
                    const SizedBox(height: 2),
                    FittedBox(
                      child: Text(
                        "ID ${client.peerId}",
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    if (client.type_() == ClientType.terminal)
                      FittedBox(
                        child: Text(
                          translate("Terminal"),
                          style: TextStyle(color: secondaryText, fontSize: 12),
                        ),
                      ),
                    if (client.type_() == ClientType.file)
                      FittedBox(
                        child: Text(
                          translate("File Transfer"),
                          style: TextStyle(color: secondaryText, fontSize: 12),
                        ),
                      ),
                    if (client.type_() == ClientType.camera)
                      FittedBox(
                        child: Text(
                          translate("View Camera"),
                          style: TextStyle(color: secondaryText, fontSize: 12),
                        ),
                      ),
                    if (client.portForward.isNotEmpty)
                      FittedBox(
                        child: Text(
                          "Port Forward: ${client.portForward}",
                          style: TextStyle(color: secondaryText, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 8.0),
                    FittedBox(
                        child: Row(
                      children: [
                        // Status dot
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: statusColor.withOpacity(0.5),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          client.authorized
                              ? client.disconnected
                                  ? translate("Disconnected")
                                  : translate("Connected")
                              : "${translate("Request access to your device")}…",
                          style: TextStyle(
                            color: primaryText.withOpacity(0.85),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ).marginOnly(right: 8.0),
                        if (client.authorized)
                          Obx(
                            () => Text(
                              formatDurationToTime(
                                Duration(seconds: _time.value),
                              ),
                              style: TextStyle(
                                color: secondaryText,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                          )
                      ],
                    ))
                  ],
                ),
              ),
              Offstage(
                offstage: !client.authorized ||
                    (client.type_() != ClientType.remote &&
                        client.type_() != ClientType.file &&
                        client.type_() != ClientType.camera),
                child: IconButton(
                  onPressed: () => checkClickTime(client.id, () {
                    if (client.type_() == ClientType.file) {
                      gFFI.chatModel.toggleCMFilePage();
                    } else {
                      gFFI.chatModel.toggleCMChatPage(
                          MessageKey(client.peerId, client.id));
                    }
                  }),
                  icon: SvgPicture.asset(client.type_() == ClientType.file
                      ? 'assets/file_transfer.svg'
                      : 'assets/chat2.svg'),
                  splashRadius: kDesktopIconButtonSplashRadius,
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  Widget _buildClientAvatar() {
    return buildAvatarWidget(
          avatar: client.avatar,
          // TajDesk stage 21: avatar shrunk from 56 to 44 to give the
          // permission list more vertical room in a small window.
          size: 44,
          borderRadius: 11,
          fallback: _buildInitialAvatar(),
        ) ??
        _buildInitialAvatar();
  }

  Widget _buildInitialAvatar() {
    // TajDesk stage 19: avatar block restyled to look like a single quiet
    // tile in the card — soft tinted background derived from the user's
    // name colour, smaller corner radius matching the card, thin top
    // highlight for depth, single big initial letter at modest weight
    // (was: blaring 55px bold initial in a saturated solid block).
    final base = str2color(client.name);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withOpacity(0.85),
            HSLColor.fromColor(base)
                .withLightness(
                    (HSLColor.fromColor(base).lightness * 0.7).clamp(0.0, 1.0))
                .toColor(),
          ],
        ),
        borderRadius: BorderRadius.circular(11.0),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: base.withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        client.name.isNotEmpty ? client.name[0].toUpperCase() : '?',
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.white,
          fontSize: 22,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

class _PrivilegeBoard extends StatefulWidget {
  final Client client;

  const _PrivilegeBoard({Key? key, required this.client}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _PrivilegeBoardState();
}

class _PrivilegeBoardState extends State<_PrivilegeBoard> {
  late final client = widget.client;
  Widget buildPermissionIcon(bool enabled, IconData iconData,
      Function(bool)? onTap, String tooltipText,
      {required bool canModify}) {
    return Tooltip(
      message: "$tooltipText: ${enabled ? "ON" : "OFF"}",
      waitDuration: Duration.zero,
      child: Container(
        decoration: BoxDecoration(
          color: enabled
              ? (canModify ? MyTheme.accent : MyTheme.accent.withOpacity(0.6))
              : Colors.grey[700],
          borderRadius: BorderRadius.circular(10.0),
        ),
        padding: EdgeInsets.all(8.0),
        child: InkWell(
          onTap: canModify
              ? () =>
                  checkClickTime(widget.client.id, () => onTap?.call(!enabled))
              : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Expanded(
                child: Icon(
                  iconData,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // TajDesk stage 19: new vertical-list row for each permission. Replaces
  // the 4×2 grid of unlabelled blue tiles. Each row reads like an iOS / macOS
  // settings entry — small icon in a tinted circle, full permission label,
  // platform Switch on the right. Far more legible (no need to hover for
  // tooltips), less consumer-app feel.
  Widget buildPermissionRow(
    bool enabled,
    IconData iconData,
    Function(bool)? onTap,
    String label, {
    required bool canModify,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = MyTheme.accent;
    final iconBg = enabled
        ? accent.withOpacity(0.18)
        : (isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.black.withOpacity(0.05));
    final iconColor = enabled
        ? accent
        : (isDark
            ? Colors.white.withOpacity(0.55)
            : Colors.black.withOpacity(0.45));
    final labelColor = canModify
        ? (isDark ? Colors.white : const Color(0xFF1A1E2A))
        : (isDark
            ? Colors.white.withOpacity(0.40)
            : Colors.black.withOpacity(0.40));
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: canModify
          ? () => checkClickTime(widget.client.id, () => onTap?.call(!enabled))
          : null,
      child: Padding(
        // TajDesk stage 21: vertical padding 9 -> 6 to pack more rows in.
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(iconData, size: 16, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Compact platform-style toggle.
            Transform.scale(
              scale: 0.78,
              child: Switch(
                value: enabled,
                onChanged: canModify
                    ? (v) => checkClickTime(
                        widget.client.id, () => onTap?.call(v))
                    : null,
                activeColor: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canModifyPermission =
        bind.mainGetBuildinOption(key: kOptionEnablePermChangeInAcceptWindow) !=
            'N';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        isDark ? const Color(0xFF1A1E2A) : const Color(0xFFF5F6F9);

    // Build the permission row list depending on connection type.
    final List<Widget> rows = [];
    if (client.type_() == ClientType.camera) {
      rows.add(buildPermissionRow(
        client.audio,
        Icons.volume_up_rounded,
        (enabled) {
          bind.cmSwitchPermission(
              connId: client.id, name: "audio", enabled: enabled);
          setState(() => client.audio = enabled);
        },
        translate('Enable audio'),
        canModify: canModifyPermission,
      ));
      rows.add(buildPermissionRow(
        client.recording,
        Icons.videocam_rounded,
        (enabled) {
          bind.cmSwitchPermission(
              connId: client.id, name: "recording", enabled: enabled);
          setState(() => client.recording = enabled);
        },
        translate('Enable recording session'),
        canModify: canModifyPermission,
      ));
    } else {
      rows.add(buildPermissionRow(
        client.keyboard,
        Icons.keyboard_outlined,
        (enabled) {
          bind.cmSwitchPermission(
              connId: client.id, name: "keyboard", enabled: enabled);
          setState(() => client.keyboard = enabled);
        },
        translate('Enable keyboard/mouse'),
        canModify: canModifyPermission,
      ));
      rows.add(buildPermissionRow(
        client.clipboard,
        Icons.assignment_outlined,
        (enabled) {
          bind.cmSwitchPermission(
              connId: client.id, name: "clipboard", enabled: enabled);
          setState(() => client.clipboard = enabled);
        },
        translate('Enable clipboard'),
        canModify: canModifyPermission,
      ));
      rows.add(buildPermissionRow(
        client.audio,
        Icons.volume_up_outlined,
        (enabled) {
          bind.cmSwitchPermission(
              connId: client.id, name: "audio", enabled: enabled);
          setState(() => client.audio = enabled);
        },
        translate('Enable audio'),
        canModify: canModifyPermission,
      ));
      rows.add(buildPermissionRow(
        client.file,
        Icons.folder_outlined,
        (enabled) {
          bind.cmSwitchPermission(
              connId: client.id, name: "file", enabled: enabled);
          setState(() => client.file = enabled);
        },
        translate('Enable file copy and paste'),
        canModify: canModifyPermission,
      ));
      rows.add(buildPermissionRow(
        client.restart,
        Icons.restart_alt_outlined,
        (enabled) {
          bind.cmSwitchPermission(
              connId: client.id, name: "restart", enabled: enabled);
          setState(() => client.restart = enabled);
        },
        translate('Enable remote restart'),
        canModify: canModifyPermission,
      ));
      rows.add(buildPermissionRow(
        client.recording,
        Icons.videocam_outlined,
        (enabled) {
          bind.cmSwitchPermission(
              connId: client.id, name: "recording", enabled: enabled);
          setState(() => client.recording = enabled);
        },
        translate('Enable recording session'),
        canModify: canModifyPermission,
      ));
      if (isWindows) {
        rows.add(buildPermissionRow(
          client.blockInput,
          Icons.block_outlined,
          (enabled) {
            bind.cmSwitchPermission(
                connId: client.id, name: "block_input", enabled: enabled);
            setState(() => client.blockInput = enabled);
          },
          translate('Enable blocking user input'),
          canModify: canModifyPermission,
        ));
      }
      if (bind.mainSupportedPrivacyModeImpls() != '[]') {
        rows.add(buildPermissionRow(
          client.privacyMode,
          Icons.visibility_off_outlined,
          (enabled) {
            bind.cmSwitchPermission(
                connId: client.id, name: "privacy_mode", enabled: enabled);
            setState(() => client.privacyMode = enabled);
          },
          translate('Enable privacy mode'),
          canModify: canModifyPermission,
        ));
      }
    }

    // Interleave thin separators between rows.
    final List<Widget> children = [];
    for (int i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(Container(
          height: 1,
          margin: const EdgeInsets.only(left: 52, right: 12),
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.05),
        ));
      }
      children.add(rows[i]);
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14.0),
        color: cardColor,
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.20 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Text(
              translate("Permissions").toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
                color: isDark
                    ? Colors.white.withOpacity(0.55)
                    : Colors.black.withOpacity(0.55),
              ),
            ),
          ),
          ...children,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

const double buttonBottomMargin = 8;

class _CmControlPanel extends StatelessWidget {
  final Client client;

  const _CmControlPanel({Key? key, required this.client}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return client.authorized
        ? client.disconnected
            ? buildDisconnected(context)
            : buildAuthorized(context)
        : buildUnAuthorized(context);
  }

  buildAuthorized(BuildContext context) {
    final bool canElevate = bind.cmCanElevate();
    final model = Provider.of<ServerModel>(context);
    final showElevation = canElevate &&
        model.showElevation &&
        client.type_() == ClientType.remote;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Offstage(
          offstage: !client.inVoiceCall,
          child: Row(
            children: [
              Expanded(
                child: buildButton(context,
                    color: MyTheme.accent,
                    onClick: null, onTapDown: (details) async {
                  final devicesInfo =
                      await AudioInput.getDevicesInfo(true, true);
                  List<String> devices = devicesInfo['devices'] as List<String>;
                  if (devices.isEmpty) {
                    msgBox(
                      gFFI.sessionId,
                      'custom-nocancel-info',
                      'Prompt',
                      'no_audio_input_device_tip',
                      '',
                      gFFI.dialogManager,
                    );
                    return;
                  }

                  String currentDevice = devicesInfo['current'] as String;
                  final x = details.globalPosition.dx;
                  final y = details.globalPosition.dy;
                  final position = RelativeRect.fromLTRB(x, y, x, y);
                  showMenu(
                    context: context,
                    position: position,
                    items: devices
                        .map((d) => PopupMenuItem<String>(
                              value: d,
                              height: 18,
                              padding: EdgeInsets.zero,
                              onTap: () => AudioInput.setDevice(d, true, true),
                              child: IgnorePointer(
                                  child: RadioMenuButton(
                                value: d,
                                groupValue: currentDevice,
                                onChanged: (v) {
                                  if (v != null)
                                    AudioInput.setDevice(v, true, true);
                                },
                                child: Container(
                                  child: Text(
                                    d,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  constraints: BoxConstraints(
                                      maxWidth:
                                          kConnectionManagerWindowSizeClosedChat
                                                  .width -
                                              80),
                                ),
                              )),
                            ))
                        .toList(),
                  );
                },
                    icon: Icon(
                      Icons.call_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    text: "Audio input",
                    textColor: Colors.white),
              ),
              Expanded(
                child: buildButton(
                  context,
                  color: Colors.red,
                  onClick: () => closeVoiceCall(),
                  icon: Icon(
                    Icons.call_end_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  text: "Stop voice call",
                  textColor: Colors.white,
                ),
              )
            ],
          ),
        ),
        Offstage(
          offstage: !client.incomingVoiceCall,
          child: Row(
            children: [
              Expanded(
                child: buildButton(context,
                    color: MyTheme.accent,
                    onClick: () => handleVoiceCall(true),
                    icon: Icon(
                      Icons.call_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    text: "Accept",
                    textColor: Colors.white),
              ),
              Expanded(
                child: buildButton(
                  context,
                  color: Colors.red,
                  onClick: () => handleVoiceCall(false),
                  icon: Icon(
                    Icons.phone_disabled_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  text: "Dismiss",
                  textColor: Colors.white,
                ),
              )
            ],
          ),
        ),
        Offstage(
          offstage: !client.fromSwitch,
          child: buildButton(context,
              color: Colors.purple,
              onClick: () => handleSwitchBack(context),
              icon: Icon(Icons.reply, color: Colors.white),
              text: "Switch Sides",
              textColor: Colors.white),
        ),
        Offstage(
          offstage: !showElevation,
          child: buildButton(
            context,
            color: MyTheme.accent,
            onClick: () {
              handleElevate(context);
              windowManager.minimize();
            },
            icon: Icon(
              Icons.security_rounded,
              color: Colors.white,
              size: 14,
            ),
            text: 'Elevate',
            textColor: Colors.white,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: buildButton(context,
                  color: Colors.redAccent,
                  onClick: handleDisconnect,
                  text: 'Disconnect',
                  icon: Icon(
                    Icons.link_off_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  textColor: Colors.white),
            ),
          ],
        )
      ],
    ).marginOnly(bottom: buttonBottomMargin);
  }

  buildDisconnected(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
            child: buildButton(context,
                color: MyTheme.accent,
                onClick: handleClose,
                text: 'Close',
                textColor: Colors.white)),
      ],
    ).marginOnly(bottom: buttonBottomMargin);
  }

  buildUnAuthorized(BuildContext context) {
    final bool canElevate = bind.cmCanElevate();
    final model = Provider.of<ServerModel>(context);
    final showElevation = canElevate &&
        model.showElevation &&
        client.type_() == ClientType.remote;
    final showAccept = model.approveMode != 'password';
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Offstage(
          offstage: !showElevation || !showAccept,
          child: buildButton(context, color: Colors.green[700], onClick: () {
            handleAccept(context);
            handleElevate(context);
            windowManager.minimize();
          },
              text: 'Accept and Elevate',
              icon: Icon(
                Icons.security_rounded,
                color: Colors.white,
                size: 14,
              ),
              textColor: Colors.white,
              tooltip: 'accept_and_elevate_btn_tooltip'),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showAccept)
              Expanded(
                child: Column(
                  children: [
                    buildButton(
                      context,
                      color: MyTheme.accent,
                      onClick: () {
                        handleAccept(context);
                        windowManager.minimize();
                      },
                      text: 'Accept',
                      textColor: Colors.white,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: buildButton(
                context,
                color: Colors.transparent,
                // TajDesk stage 19: subtler border that matches our card
                // borders instead of the stock grey rectangle.
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withOpacity(0.20)
                      : Colors.black.withOpacity(0.18),
                  width: 1,
                ),
                onClick: handleDisconnect,
                text: 'Cancel',
                textColor: null,
              ),
            ),
          ],
        ),
      ],
    ).marginOnly(bottom: buttonBottomMargin);
  }

  Widget buildButton(BuildContext context,
      {required Color? color,
      GestureTapCallback? onClick,
      Widget? icon,
      BoxBorder? border,
      required String text,
      required Color? textColor,
      String? tooltip,
      GestureTapDownCallback? onTapDown}) {
    assert(!(onClick == null && onTapDown == null));
    // TajDesk stage 19: more substantial premium-style buttons.
    //   * Taller (height 38 vs 28) — comfortable click targets.
    //   * Slightly rounder (radius 9), softer.
    //   * Outlined (Cancel) gets a subtle hover effect via Material.
    //   * Filled (Accept) gets w600 text, bigger.
    //   * Internal margins increased so the button row breathes.
    Widget textWidget;
    if (icon != null) {
      textWidget = Text(
        translate(text),
        style: TextStyle(
          color: textColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        textAlign: TextAlign.center,
      );
    } else {
      textWidget = Expanded(
        child: Text(
          translate(text),
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    final borderRadius = BorderRadius.circular(9.0);
    final btn = Material(
      color: color,
      borderRadius: borderRadius,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: border,
        ),
        child: InkWell(
          borderRadius: borderRadius,
          onTap: () {
            if (onClick == null) return;
            checkClickTime(client.id, onClick);
          },
          onTapDown: (details) {
            if (onTapDown == null) return;
            checkClickTime(client.id, () {
              onTapDown.call(details);
            });
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Offstage(offstage: icon == null, child: icon).marginOnly(right: 6),
              textWidget,
            ],
          ),
        ),
      ),
    );
    return (tooltip != null
            ? Tooltip(
                message: translate(tooltip),
                child: btn,
              )
            : btn)
        .marginAll(6);
  }

  void handleDisconnect() {
    bind.cmCloseConnection(connId: client.id);
  }

  void handleAccept(BuildContext context) {
    final model = Provider.of<ServerModel>(context, listen: false);
    model.sendLoginResponse(client, true);
  }

  void handleElevate(BuildContext context) {
    final model = Provider.of<ServerModel>(context, listen: false);
    model.setShowElevation(false);
    bind.cmElevatePortable(connId: client.id);
  }

  void handleClose() async {
    await bind.cmRemoveDisconnectedConnection(connId: client.id);
    if (await bind.cmGetClientsLength() == 0) {
      windowManager.close();
    }
  }

  void handleSwitchBack(BuildContext context) {
    bind.cmSwitchBack(connId: client.id);
  }

  void handleVoiceCall(bool accept) {
    bind.cmHandleIncomingVoiceCall(id: client.id, accept: accept);
  }

  void closeVoiceCall() {
    bind.cmCloseVoiceCall(id: client.id);
  }
}

void checkClickTime(int id, Function() callback) async {
  if (allowRemoteCMModification()) {
    callback();
    return;
  }
  var clickCallbackTime = DateTime.now().millisecondsSinceEpoch;
  await bind.cmCheckClickTime(connId: id);
  Timer(const Duration(milliseconds: 120), () async {
    var d = clickCallbackTime - await bind.cmGetClickTime();
    if (d > 120) callback();
  });
}

bool allowRemoteCMModification() {
  return option2bool(kOptionAllowRemoteCmModification,
      bind.mainGetLocalOption(key: kOptionAllowRemoteCmModification));
}

class _FileTransferLogPage extends StatefulWidget {
  _FileTransferLogPage({Key? key}) : super(key: key);

  @override
  State<_FileTransferLogPage> createState() => __FileTransferLogPageState();
}

class __FileTransferLogPageState extends State<_FileTransferLogPage> {
  @override
  Widget build(BuildContext context) {
    return statusList();
  }

  Widget generateCard(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.all(
          Radius.circular(15.0),
        ),
      ),
      child: child,
    );
  }

  iconLabel(CmFileLog item) {
    switch (item.action) {
      case CmFileAction.none:
        return Container();
      case CmFileAction.localToRemote:
      case CmFileAction.remoteToLocal:
        return Column(
          children: [
            Transform.rotate(
              angle: item.action == CmFileAction.remoteToLocal ? 0 : pi,
              child: SvgPicture.asset(
                "assets/arrow.svg",
                colorFilter: svgColor(Theme.of(context).tabBarTheme.labelColor),
              ),
            ),
            Text(item.action == CmFileAction.remoteToLocal
                ? translate('Send')
                : translate('Receive'))
          ],
        );
      case CmFileAction.remove:
        return Column(
          children: [
            Icon(
              Icons.delete,
              color: Theme.of(context).tabBarTheme.labelColor,
            ),
            Text(translate('Delete'))
          ],
        );
      case CmFileAction.createDir:
        return Column(
          children: [
            Icon(
              Icons.create_new_folder,
              color: Theme.of(context).tabBarTheme.labelColor,
            ),
            Text(translate('Create Folder'))
          ],
        );
      case CmFileAction.rename:
        return Column(
          children: [
            Icon(
              Icons.drive_file_move_outlined,
              color: Theme.of(context).tabBarTheme.labelColor,
            ),
            Text(translate('Rename'))
          ],
        );
    }
  }

  Widget statusList() {
    return PreferredSize(
      preferredSize: const Size(200, double.infinity),
      child: Container(
          padding: const EdgeInsets.all(12.0),
          child: Obx(
            () {
              final jobTable = gFFI.cmFileModel.currentJobTable;
              statusListView(List<CmFileLog> jobs) => ListView.builder(
                    controller: ScrollController(),
                    itemBuilder: (BuildContext context, int index) {
                      final item = jobs[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: generateCard(
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 50,
                                    child: iconLabel(item),
                                  ).paddingOnly(left: 15),
                                  const SizedBox(
                                    width: 16.0,
                                  ),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.fileName,
                                        ).paddingSymmetric(vertical: 10),
                                        if (item.totalSize > 0)
                                          Text(
                                            '${translate("Total")} ${readableFileSize(item.totalSize.toDouble())}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: MyTheme.darkGray,
                                            ),
                                          ),
                                        if (item.totalSize > 0)
                                          Offstage(
                                            offstage: item.state !=
                                                JobState.inProgress,
                                            child: Text(
                                              '${translate("Speed")} ${readableFileSize(item.speed)}/s',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: MyTheme.darkGray,
                                              ),
                                            ),
                                          ),
                                        Offstage(
                                          offstage: !(item.isTransfer() &&
                                              item.state !=
                                                  JobState.inProgress),
                                          child: Text(
                                            translate(
                                              item.display(),
                                            ),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: MyTheme.darkGray,
                                            ),
                                          ),
                                        ),
                                        if (item.totalSize > 0)
                                          Offstage(
                                            offstage: item.state !=
                                                JobState.inProgress,
                                            child: LinearPercentIndicator(
                                              padding:
                                                  EdgeInsets.only(right: 15),
                                              animateFromLastPercent: true,
                                              center: Text(
                                                '${(item.finishedSize / item.totalSize * 100).toStringAsFixed(0)}%',
                                              ),
                                              barRadius: Radius.circular(15),
                                              percent: item.finishedSize /
                                                  item.totalSize,
                                              progressColor: MyTheme.accent,
                                              backgroundColor:
                                                  Theme.of(context).hoverColor,
                                              lineHeight:
                                                  kDesktopFileTransferRowHeight,
                                            ).paddingSymmetric(vertical: 15),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [],
                                  ),
                                ],
                              ),
                            ],
                          ).paddingSymmetric(vertical: 10),
                        ),
                      );
                    },
                    itemCount: jobTable.length,
                  );

              return jobTable.isEmpty
                  ? generateCard(
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgPicture.asset(
                              "assets/transfer.svg",
                              colorFilter: svgColor(
                                  Theme.of(context).tabBarTheme.labelColor),
                              height: 40,
                            ).paddingOnly(bottom: 10),
                            Text(
                              translate("No transfers in progress"),
                              textAlign: TextAlign.center,
                              textScaler: TextScaler.linear(1.20),
                              style: TextStyle(
                                  color:
                                      Theme.of(context).tabBarTheme.labelColor),
                            ),
                          ],
                        ),
                      ),
                    )
                  : statusListView(jobTable);
            },
          )),
    );
  }
}
