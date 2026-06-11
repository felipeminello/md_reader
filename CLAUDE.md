# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

This is a Flutter **Markdown reader** for Windows desktop. The user picks a `.md` file through the native file picker; the app reads it and renders it on screen, with an action to close the document and return to an empty state. The original `flutter create` counter boilerplate has been replaced by the reader feature.

Only the **Windows desktop** platform is configured (see [windows/](windows/) and `.metadata`). There are no `android/`, `ios/`, `web/`, `linux/`, or `macos/` runner directories, so `flutter run` / `flutter build` target Windows. Add platforms with `flutter create --platforms=<name> .` before targeting them.

## Architecture standard

This project **must follow the BLoC (Business Logic Component) pattern** for state management. All new feature work should adhere to it:

- Keep business logic out of widgets. UI widgets only dispatch events and render state.
- Each feature has a Bloc (or Cubit) with explicit **State** classes and, for Blocs, explicit **Event** classes.
- Use the `flutter_bloc` package (`BlocProvider`, `BlocBuilder`, `BlocListener`, `context.read`/`context.watch`). Add it with `flutter pub add flutter_bloc` — it is not yet a dependency.
- Suggested layering: `presentation` (widgets) → `bloc` (blocs/cubits, events, states) → `domain`/`data` (repositories, models). Widgets never call repositories directly; the Bloc mediates.
- The reader feature lives under [lib/reader/](lib/reader/), split into `presentation/` (`ReaderPage` + view widgets), `bloc/` (`ReaderBloc` with `ReaderEvent`/`ReaderState`), and `data/` (`MarkdownRepository`, `MarkdownDocument`). [lib/main.dart](lib/main.dart) wires them together with `RepositoryProvider` + `BlocProvider`. New features should follow the same layering.

## Commands

```powershell
flutter pub get                 # install/sync dependencies (run after editing pubspec.yaml)
flutter run -d windows          # run the app on Windows desktop with hot reload
flutter analyze                 # static analysis / lint (rules from flutter_lints, see analysis_options.yaml)
flutter test                    # run all tests
flutter test test/widget_test.dart                              # run a single test file
flutter test --plain-name "Counter increments smoke test"       # run a single test by name
flutter build windows           # build a release Windows executable
dart format .                   # format code
```

## Notes

- **Whenever new files are created, update [README.md](README.md) with the current project structure** so it always reflects the files and directories that exist in the repo.
- Dart SDK constraint is `>=3.4.4 <4.0.0` (`pubspec.yaml`). Flutter channel is `stable`.
- Non-SDK dependencies: `flutter_bloc` (state management), `file_picker` (native file dialog), `flutter_markdown` (rendering), `flutter_mermaid` (pure-Dart Mermaid diagram rendering), `markdown` (AST types used by the custom element builder), plus the original `cupertino_icons`. Add new packages via `flutter pub add <name>` so `pubspec.yaml` and `pubspec.lock` stay in sync.
- `flutter_markdown` is officially discontinued (recommended replacement: `flutter_markdown_plus`). It still works and is fine for now, but is the natural migration target if rendering needs grow.
- Running on Windows requires **Developer Mode** enabled — Flutter needs symlink support to assemble the plugin symlinks for `file_picker`. Enable it once via Settings → *For developers*, or run `start ms-settings:developers`. Without it, `flutter run`/`flutter build windows` fail (but `flutter test` and `flutter analyze` still work).
- [test/widget_test.dart](test/widget_test.dart) covers the `ReaderBloc` (driven by a fake repository) and the `ReaderPage` widget (empty state, document render, close). It no longer references the removed counter.
- A Windows **MSI installer** is authored under [installer/](installer/) using the WiX v3 toolset. Run `powershell -File installer\build_msi.ps1` to produce `dist\md_reader-<version>-x64.msi` (see [README.md](README.md) for the one-time WiX setup). The MSI installs to *Program Files\MD Reader* with a Start Menu shortcut and is currently **unsigned**.
- Generated / not hand-edited: `build/`, `windows/flutter/ephemeral/`, `dist/` (output MSI), `tools/` (downloaded WiX binaries), `installer/obj/`, and `installer/AppFiles.wxs` (harvested by `heat`).
