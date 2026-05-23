import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';

class InstallPage extends StatefulWidget {
  const InstallPage({Key? key}) : super(key: key);

  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);

  _InstallPageState() {
    Get.put<DesktopTabController>(tabController);
    const label = "install";
    tabController.add(TabInfo(
        key: label,
        label: label,
        closable: false,
        page: _InstallPageBody(
          key: const ValueKey(label),
        )));
  }

  @override
  void dispose() {
    super.dispose();
    Get.delete<DesktopTabController>();
  }

  @override
  Widget build(BuildContext context) {
    return DragToResizeArea(
      resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
      enableResizeEdges: windowManagerEnableResizeEdges,
      child: Container(
        child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.background,
            body: DesktopTab(controller: tabController)),
      ),
    );
  }
}

class _InstallPageBody extends StatefulWidget {
  const _InstallPageBody({Key? key}) : super(key: key);

  @override
  State<_InstallPageBody> createState() => _InstallPageBodyState();
}

class _InstallPageBodyState extends State<_InstallPageBody>
    with WindowListener {
  late final TextEditingController controller;
  final RxBool startmenu = true.obs;
  final RxBool desktopicon = true.obs;
  final RxBool printer = true.obs;
  final RxBool showProgress = false.obs;
  final RxBool btnEnabled = true.obs;

  // todo move to theme.
  final buttonStyle = OutlinedButton.styleFrom(
    textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
    padding: EdgeInsets.symmetric(vertical: 15, horizontal: 12),
  );

  _InstallPageBodyState() {
    controller = TextEditingController(text: bind.installInstallPath());
    final installOptions = jsonDecode(bind.installInstallOptions());
    startmenu.value = installOptions['STARTMENUSHORTCUTS'] != '0';
    desktopicon.value = installOptions['DESKTOPSHORTCUTS'] != '0';
    printer.value = installOptions['PRINTER'] != '0';
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
    gFFI.close();
    super.onWindowClose();
    windowManager.setPreventClose(false);
    windowManager.close();
  }

  // TajDesk stage 39: accent rounded checkbox option (replaces stock Checkbox).
  Widget Option(RxBool option, {String label = ''}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => btnEnabled.value ? option.value = !option.value : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: Row(
          children: [
            Obx(
              () => Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: option.value ? MyTheme.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: option.value
                        ? MyTheme.accent
                        : Theme.of(context)
                            .textTheme
                            .titleLarge!
                            .color!
                            .withOpacity(0.35),
                    width: 1.5,
                  ),
                ),
                child: option.value
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(translate(label),
                  style: const TextStyle(fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double em = 13;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final labelColor = textColor?.withOpacity(0.5);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? const Color(0xFF1E2638) : Colors.white;
    Widget sectionLabel(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 2),
          child: Text(
            translate(t).toUpperCase(),
            style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: labelColor),
          ),
        );
    return Scaffold(
        backgroundColor: null,
        body: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: 3 * em, vertical: 2.5 * em),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ---- Brand header ----
                    Center(
                      child: Column(
                        children: [
                          SizedBox(
                              width: 56, height: 56, child: loadLogo()),
                          const SizedBox(height: 12),
                          Text(
                            '${translate('Installation')} $appName',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: textColor),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 2.2 * em),
                    // ---- Install path ----
                    sectionLabel('Installation Path'),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: fieldBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: MyTheme.accent.withOpacity(0.25)),
                            ),
                            child: TextField(
                              controller: controller,
                              readOnly: true,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(0.85 * em),
                              ),
                            ).workaroundFreezeLinuxMint(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Obx(
                          () => OutlinedButton.icon(
                            icon:
                                const Icon(Icons.folder_outlined, size: 16),
                            onPressed: btnEnabled.value
                                ? selectInstallPath
                                : null,
                            style: buttonStyle,
                            label: Text(translate('Change Path')),
                          ),
                        )
                      ],
                    ),
                    SizedBox(height: 1.6 * em),
                    // ---- Options ----
                    sectionLabel('Options'),
                    Option(startmenu,
                        label: 'Create start menu shortcuts'),
                    Option(desktopicon, label: 'Create desktop icon'),
                    Option(printer, label: 'Install {$appName} Printer'),
                    SizedBox(height: 1.4 * em),
                    // ---- Agreement ----
                    Container(
                      decoration: BoxDecoration(
                        color: fieldBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border(
                          left: BorderSide(color: MyTheme.accent, width: 3),
                          top: BorderSide(
                              color: MyTheme.accent.withOpacity(0.15)),
                          right: BorderSide(
                              color: MyTheme.accent.withOpacity(0.15)),
                          bottom: BorderSide(
                              color: MyTheme.accent.withOpacity(0.15)),
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 18, color: MyTheme.accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(translate('agreement_tip'),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            textColor?.withOpacity(0.75),
                                        height: 1.4)),
                                const SizedBox(height: 6),
                                InkWell(
                                  hoverColor: Colors.transparent,
                                  onTap: () => launchUrlString(
                                      'https://tajdesk.tj/privacy'),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.launch_outlined,
                                          size: 14,
                                          color: MyTheme.accent),
                                      const SizedBox(width: 5),
                                      Text(
                                        translate(
                                            'End-user license agreement'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: MyTheme.accent,
                                          decoration:
                                              TextDecoration.underline,
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                    SizedBox(height: 1.8 * em),
                    // ---- Progress ----
                    Obx(() => showProgress.value
                        ? const LinearProgressIndicator()
                            .marginOnly(bottom: 12)
                        : const Offstage()),
                    // ---- Actions ----
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Offstage(
                          offstage: bind.installShowRunWithoutInstall(),
                          child: Obx(
                            () => TextButton(
                              onPressed: btnEnabled.value
                                  ? () => bind.installRunWithoutInstall()
                                  : null,
                              child:
                                  Text(translate('Run without install')),
                            ).marginOnly(right: 8),
                          ),
                        ),
                        Obx(
                          () => OutlinedButton(
                            onPressed: btnEnabled.value
                                ? () => windowManager.close()
                                : null,
                            style: buttonStyle,
                            child: Text(translate('Cancel')),
                          ).marginOnly(right: 10),
                        ),
                        Obx(
                          () => ElevatedButton.icon(
                            icon: const Icon(Icons.done_rounded, size: 16),
                            label: Text(translate('Accept and Install')),
                            onPressed: btnEnabled.value ? install : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: MyTheme.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 15, horizontal: 18),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        ));
  }

  void install() {
    do_install() {
      btnEnabled.value = false;
      showProgress.value = true;
      String args = '';
      if (startmenu.value) args += ' startmenu';
      if (desktopicon.value) args += ' desktopicon';
      if (printer.value) args += ' printer';
      bind.installInstallMe(options: args, path: controller.text);
    }

    do_install();
  }

  void selectInstallPath() async {
    String? install_path = await FilePicker.platform
        .getDirectoryPath(initialDirectory: controller.text);
    if (install_path != null) {
      controller.text = join(install_path, await bind.mainGetAppName());
    }
  }
}
