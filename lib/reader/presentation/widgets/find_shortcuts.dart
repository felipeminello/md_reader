import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/find_bloc.dart';
import '../../bloc/find_event.dart';
import '../../bloc/find_state.dart';
import '../../bloc/reader_bloc.dart';
import '../../bloc/reader_state.dart';

/// Opens *Localizar* with Cmd+F on macOS or Ctrl+F elsewhere, wherever the
/// focus is inside [child], while a document is open.
class FindShortcuts extends StatefulWidget {
  const FindShortcuts({super.key, required this.child});

  final Widget child;

  /// The shortcut as shown to the user, e.g. in a tooltip.
  static String get label => _isMacOS ? '⌘F' : 'Ctrl+F';

  static bool get _isMacOS => defaultTargetPlatform == TargetPlatform.macOS;

  @override
  State<FindShortcuts> createState() => _FindShortcutsState();
}

class _FindShortcutsState extends State<FindShortcuts> {
  /// Holds the focus when nothing below it does, so the shortcut still fires
  /// before the user clicks anywhere and after the find bar closes.
  final FocusNode _focusNode = FocusNode(debugLabel: 'FindShortcuts');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _openFind() {
    if (context.read<ReaderBloc>().state is! ReaderLoaded) return;
    context.read<FindBloc>().add(const FindOpened());
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<FindBloc, FindState>(
      listenWhen: (previous, current) => previous.isOpen && !current.isOpen,
      // The find bar's field is gone with the focus; take it back.
      listener: (context, state) => _focusNode.requestFocus(),
      child: CallbackShortcuts(
        bindings: {
          SingleActivator(
            LogicalKeyboardKey.keyF,
            meta: FindShortcuts._isMacOS,
            control: !FindShortcuts._isMacOS,
          ): _openFind,
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: widget.child,
        ),
      ),
    );
  }
}
