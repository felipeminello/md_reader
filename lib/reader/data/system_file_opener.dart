import 'dart:async';

import 'package:flutter/services.dart';

/// Receives files that the operating system asks the app to open.
///
/// On macOS this covers double-clicking a `.md` file in Finder and picking the
/// app under *Abrir com* — the native side (`AppDelegate`) buffers the file the
/// app was launched with until Dart asks for it, and pushes later ones through
/// the same channel.
///
/// Part of the data layer: only [ReaderBloc] talks to it, never the widgets.
/// On platforms without the native counterpart (Windows, tests) every call is a
/// no-op.
class SystemFileOpener {
  SystemFileOpener({
    MethodChannel channel = const MethodChannel(channelName),
    List<String> launchArguments = const [],
  })  : _channel = channel,
        _launchArguments = launchArguments;

  /// Shared with `AppDelegate.fileOpenChannelName` on the macOS side.
  static const channelName = 'md_reader/system_file_open';

  final MethodChannel _channel;

  /// Command-line arguments of the process. On Windows, *Abrir com* and a
  /// double-click start the executable with the file path as an argument.
  final List<String> _launchArguments;
  final _files = StreamController<String>.broadcast();

  /// Files the OS asks the app to open while it is already running.
  Stream<String> get files => _files.stream;

  /// Starts listening and returns the file the app was launched with, or
  /// `null` when it was launched without one (or the platform has no support).
  Future<String?> start() async {
    _channel.setMethodCallHandler((call) async {
      final path = call.arguments;
      if (call.method == 'openFile' && path is String) {
        _files.add(path);
      }
      return null;
    });

    try {
      final initial = await _channel.invokeMethod<String>('getInitialFile');
      return initial ?? _fileFromArguments();
    } on MissingPluginException {
      // No native side on this platform: fall back to the command line.
      return _fileFromArguments();
    }
  }

  String? _fileFromArguments() {
    for (final arg in _launchArguments) {
      final lower = arg.toLowerCase();
      if (lower.endsWith('.md') || lower.endsWith('.markdown')) return arg;
    }
    return null;
  }
}
