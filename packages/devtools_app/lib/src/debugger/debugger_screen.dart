// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:codicon/codicon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Stack;
import 'package:provider/provider.dart';
import 'package:vm_service/vm_service.dart';

import '../analytics/analytics.dart' as ga;
import '../analytics/constants.dart' as analytics_constants;
import '../auto_dispose_mixin.dart';
import '../common_widgets.dart';
import '../flex_split_column.dart';
import '../globals.dart';
import '../listenable.dart';
import '../screen.dart';
import '../split.dart';
import '../theme.dart';
import '../ui/icons.dart';
import 'breakpoints.dart';
import 'call_stack.dart';
import 'codeview.dart';
import 'controls.dart';
import 'debugger_controller.dart';
import 'debugger_model.dart';
import 'key_sets.dart';
import 'program_explorer.dart';
import 'variables.dart';

class DebuggerScreen extends Screen {
  const DebuggerScreen()
      : super.conditional(
          id: id,
          requiresDebugBuild: true,
          title: 'Debugger',
          icon: Octicons.bug,
          showFloatingDebuggerControls: false,
        );

  static const id = 'debugger';

  @override
  bool showConsole(bool embed) => true;

  @override
  String get docPageId => screenId;

  @override
  ValueListenable<bool> get showIsolateSelector =>
      const FixedValueListenable<bool>(true);

  @override
  Widget build(BuildContext context) => const DebuggerScreenBody();

  @override
  Widget buildStatus(BuildContext context, TextTheme textTheme) {
    final controller = Provider.of<DebuggerController>(context);
    return DebuggerStatus(controller: controller);
  }
}

class DebuggerScreenBody extends StatefulWidget {
  const DebuggerScreenBody();

  static final codeViewKey = GlobalKey(debugLabel: 'codeViewKey');
  static final scriptViewKey = GlobalKey(debugLabel: 'scriptViewKey');
  static const callStackCopyButtonKey =
      Key('debugger_call_stack_copy_to_clipboard_button');

  @override
  DebuggerScreenBodyState createState() => DebuggerScreenBodyState();
}

class DebuggerScreenBodyState extends State<DebuggerScreenBody>
    with AutoDisposeMixin {
  static const callStackTitle = 'Call Stack';
  static const variablesTitle = 'Variables';
  static const breakpointsTitle = 'Breakpoints';

  DebuggerController controller;

  bool _shownFirstScript;

  @override
  void initState() {
    super.initState();
    ga.screen(DebuggerScreen.id);
    ga.timeStart(DebuggerScreen.id, analytics_constants.pageReady);
    _shownFirstScript = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final newController = Provider.of<DebuggerController>(context);
    if (newController == controller) return;
    controller = newController;
  }

  void _onLocationSelected(ScriptLocation location) {
    if (location != null) {
      controller.showScriptLocation(
        location,
        centerLocation: location.location == null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final codeView = ValueListenableBuilder(
      valueListenable: controller.currentScriptRef,
      builder: (context, scriptRef, _) {
        return ValueListenableBuilder(
          valueListenable: controller.currentParsedScript,
          builder: (context, parsedScript, _) {
            if (scriptRef != null &&
                parsedScript != null &&
                !_shownFirstScript) {
              ga.timeEnd(DebuggerScreen.id, analytics_constants.pageReady);
              serviceManager.sendDwdsEvent(
                screen: DebuggerScreen.id,
                action: analytics_constants.pageReady,
              );
              _shownFirstScript = true;
            }
            return CodeView(
              key: DebuggerScreenBody.codeViewKey,
              controller: controller,
              scriptRef: scriptRef,
              parsedScript: parsedScript,
              onSelected: controller.toggleBreakpoint,
            );
          },
        );
      },
    );

    final codeArea = ValueListenableBuilder(
      valueListenable: controller.fileExplorerVisible,
      builder: (context, visible, _) {
        if (visible) {
          // TODO(devoncarew): Animate this opening and closing.
          return Split(
            axis: Axis.horizontal,
            initialFractions: const [0.70, 0.30],
            children: [
              codeView,
              ProgramExplorer(
                debugController: controller,
                onSelected: _onLocationSelected,
              ),
            ],
          );
        } else {
          return codeView;
        }
      },
    );

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        goToLineNumberKeySet: GoToLineNumberIntent(context, controller),
        searchInFileKeySet: SearchInFileIntent(controller),
        escapeKeySet: EscapeIntent(controller),
        openFileKeySet: OpenFileIntent(controller),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          GoToLineNumberIntent: GoToLineNumberAction(),
          SearchInFileIntent: SearchInFileAction(),
          EscapeIntent: EscapeAction(),
          OpenFileIntent: OpenFileAction(),
        },
        child: Split(
          axis: Axis.horizontal,
          initialFractions: const [0.25, 0.75],
          children: [
            OutlineDecoration(child: debuggerPanes()),
            Column(
              children: [
                const DebuggingControls(),
                const SizedBox(height: denseRowSpacing),
                Expanded(
                  child: codeArea,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget debuggerPanes() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FlexSplitColumn(
          totalHeight: constraints.maxHeight,
          initialFractions: const [0.40, 0.40, 0.20],
          minSizes: const [0.0, 0.0, 0.0],
          headers: <PreferredSizeWidget>[
            AreaPaneHeader(
              title: const Text(callStackTitle),
              rightActions: [
                CopyToClipboardControl(
                  dataProvider: () {
                    final List<String> callStackList = controller
                        .stackFramesWithLocation.value
                        .map((frame) => frame.callStackDisplay)
                        .toList();
                    for (var i = 0; i < callStackList.length; i++) {
                      callStackList[i] = '#$i ${callStackList[i]}';
                    }
                    return callStackList.join('\n') ?? '';
                  },
                  buttonKey: DebuggerScreenBody.callStackCopyButtonKey,
                ),
              ],
              needsTopBorder: false,
            ),
            const AreaPaneHeader(title: Text(variablesTitle)),
            AreaPaneHeader(
              title: const Text(breakpointsTitle),
              rightActions: [
                _breakpointsRightChild(),
              ],
              rightPadding: 0.0,
            ),
          ],
          children: const [
            CallStack(),
            Variables(),
            Breakpoints(),
          ],
        );
      },
    );
  }

  Widget _breakpointsRightChild() {
    return ValueListenableBuilder(
      valueListenable: controller.breakpointsWithLocation,
      builder: (context, breakpoints, _) {
        return Row(children: [
          BreakpointsCountBadge(breakpoints: breakpoints),
          DevToolsTooltip(
            child: ToolbarAction(
              icon: Icons.delete,
              onPressed:
                  breakpoints.isNotEmpty ? controller.clearBreakpoints : null,
            ),
            tooltip: 'Remove all breakpoints',
          ),
        ]);
      },
    );
  }
}

class GoToLineNumberIntent extends Intent {
  const GoToLineNumberIntent(this._context, this._controller);

  final BuildContext _context;
  final DebuggerController _controller;
}

class GoToLineNumberAction extends Action<GoToLineNumberIntent> {
  @override
  void invoke(GoToLineNumberIntent intent) {
    showGoToLineDialog(intent._context, intent._controller);
    intent._controller.toggleFileOpenerVisibility(false);
    intent._controller.toggleSearchInFileVisibility(false);
  }
}

class SearchInFileIntent extends Intent {
  const SearchInFileIntent(this._controller);

  final DebuggerController _controller;
}

class SearchInFileAction extends Action<SearchInFileIntent> {
  @override
  void invoke(SearchInFileIntent intent) {
    intent._controller.toggleSearchInFileVisibility(true);
    intent._controller.toggleFileOpenerVisibility(false);
  }
}

class EscapeIntent extends Intent {
  const EscapeIntent(this._controller);

  final DebuggerController _controller;
}

class EscapeAction extends Action<EscapeIntent> {
  @override
  void invoke(EscapeIntent intent) {
    intent._controller.toggleSearchInFileVisibility(false);
    intent._controller.toggleFileOpenerVisibility(false);
  }
}

class OpenFileIntent extends Intent {
  const OpenFileIntent(this._controller);

  final DebuggerController _controller;
}

class OpenFileAction extends Action<OpenFileIntent> {
  @override
  void invoke(OpenFileIntent intent) {
    intent._controller.toggleFileOpenerVisibility(true);
    intent._controller.toggleSearchInFileVisibility(false);
  }
}

class DebuggerStatus extends StatefulWidget {
  const DebuggerStatus({
    Key key,
    @required this.controller,
  }) : super(key: key);

  final DebuggerController controller;

  @override
  _DebuggerStatusState createState() => _DebuggerStatusState();
}

class _DebuggerStatusState extends State<DebuggerStatus> with AutoDisposeMixin {
  String _status;

  @override
  void initState() {
    super.initState();

    addAutoDisposeListener(widget.controller.isPaused, _updateStatus);

    _status = '';
    _updateStatus();
  }

  @override
  void didUpdateWidget(DebuggerStatus oldWidget) {
    super.didUpdateWidget(oldWidget);

    // todo: should we check that widget.controller != oldWidget.controller?
    addAutoDisposeListener(widget.controller.isPaused, _updateStatus);
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _status,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  void _updateStatus() async {
    final status = await _computeStatus();
    if (status != _status) {
      setState(() {
        _status = status;
      });
    }
  }

  Future<String> _computeStatus() async {
    final paused = widget.controller.isPaused.value;

    if (!paused) {
      return 'running';
    }

    final event = widget.controller.lastEvent;
    final frame = event.topFrame;
    final reason =
        event.kind == EventKind.kPauseException ? ' on exception' : '';

    if (frame == null) {
      return 'paused$reason';
    }

    final fileName = ' at ' + frame.location.script.uri.split('/').last;
    final script = await widget.controller.getScript(frame.location.script);
    final pos =
        SourcePosition.calculatePosition(script, frame.location.tokenPos);

    return 'paused$reason$fileName $pos';
  }
}

class FloatingDebuggerControls extends StatefulWidget {
  @override
  _FloatingDebuggerControlsState createState() =>
      _FloatingDebuggerControlsState();
}

class _FloatingDebuggerControlsState extends State<FloatingDebuggerControls>
    with AutoDisposeMixin {
  DebuggerController controller;

  bool paused;

  double controlHeight;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller = Provider.of<DebuggerController>(context);
    paused = controller.isPaused.value;
    controlHeight = paused ? defaultButtonHeight : 0.0;
    addAutoDisposeListener(controller.isPaused, () {
      setState(() {
        paused = controller.isPaused.value;
        if (paused) {
          controlHeight = defaultButtonHeight;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: paused ? 1.0 : 0.0,
      duration: longDuration,
      onEnd: () {
        if (!paused) {
          setState(() {
            controlHeight = 0.0;
          });
        }
      },
      child: Container(
        color: devtoolsWarning,
        height: controlHeight,
        child: OutlinedRowGroup(
          // Default focus color for the light theme - since the background
          // color of the controls [devtoolsWarning] is the same for both
          // themes, we will use the same border color.
          borderColor: Colors.black.withOpacity(0.12),
          children: [
            Container(
              height: defaultButtonHeight,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(
                horizontal: defaultSpacing,
              ),
              child: const Text(
                'Main isolate is paused in the debugger',
                style: TextStyle(color: Colors.black),
              ),
            ),
            DevToolsTooltip(
              tooltip: 'Resume',
              child: TextButton(
                onPressed: controller.resume,
                child: Icon(
                  Codicons.debugContinue,
                  color: Colors.green,
                  size: defaultIconSize,
                ),
              ),
            ),
            DevToolsTooltip(
              tooltip: 'Step over',
              child: TextButton(
                onPressed: controller.stepOver,
                child: Icon(
                  Codicons.debugStepOver,
                  color: Colors.black,
                  size: defaultIconSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
