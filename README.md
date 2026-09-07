# MD Reader

A simple Flutter application for reading Markdown files on **Windows and macOS desktop**.
Pick a `.md` file from your system, view it rendered on screen, and close it to
go back to the empty state.

## Features

- 📂 Select a Markdown file through the native file picker, or drag and drop
  one onto the empty-state screen (`.md` only).
- 📖 Read and render the file as formatted, selectable, scrollable text.
- 🧜 Render ```` ```mermaid ```` fenced code blocks as native diagrams
  (flowchart, sequence, pie, gantt, timeline, kanban, radar and XY chart);
  unsupported or malformed diagrams fall back to a plain code block.
- ✖️ Close the open document to return to the empty state.

## Project Structure

```
md_reader/
├── lib/
│   ├── main.dart                       # App entry: MaterialApp + Repository/Bloc providers
│   └── reader/                         # Markdown reader feature (BLoC pattern)
│       ├── data/
│       │   ├── markdown_document.dart  # MarkdownDocument model
│       │   └── markdown_repository.dart# Data source: pick + read files
│       ├── bloc/
│       │   ├── reader_bloc.dart        # ReaderBloc (business logic)
│       │   ├── reader_event.dart       # Events: open file / close file / drop file
│       │   └── reader_state.dart       # States: empty / loading / loaded / failure
│       └── presentation/
│           ├── reader_page.dart        # Main screen (BlocBuilder / BlocConsumer)
│           └── widgets/
│               ├── markdown_view.dart      # Renders a loaded document
│               ├── mermaid_element_builder.dart # Renders ```mermaid blocks as diagrams
│               └── reader_empty_view.dart  # Empty-state placeholder, open button + drag-and-drop target
├── test/
│   └── widget_test.dart                # ReaderBloc + ReaderPage tests
├── windows/                            # Windows desktop runner
│   ├── flutter/                        # Flutter build glue (generated registrant, CMake)
│   ├── runner/                         # Native C++ runner
│   │   ├── resources/
│   │   │   └── app_icon.ico
│   │   ├── flutter_window.cpp / .h
│   │   ├── main.cpp
│   │   ├── utils.cpp / .h
│   │   ├── win32_window.cpp / .h
│   │   ├── resource.h
│   │   ├── Runner.rc
│   │   └── runner.exe.manifest
│   └── CMakeLists.txt
├── macos/                              # macOS desktop runner
│   ├── Flutter/                        # Flutter build glue (generated plugin registrant, xcconfigs)
│   ├── Runner/                         # Native Swift/AppKit runner
│   │   ├── AppDelegate.swift
│   │   ├── MainFlutterWindow.swift
│   │   ├── Base.lproj/MainMenu.xib
│   │   ├── Assets.xcassets/AppIcon.appiconset/
│   │   ├── Configs/                    # AppInfo / Debug / Release / Warnings xcconfigs
│   │   ├── Info.plist
│   │   ├── DebugProfile.entitlements   # App Sandbox + user-selected file read access
│   │   └── Release.entitlements        # App Sandbox + user-selected file read access
│   ├── RunnerTests/RunnerTests.swift
│   ├── Runner.xcodeproj/
│   └── Runner.xcworkspace/
├── installer/                          # MSI packaging (WiX v3 toolset)
│   ├── md_reader.wxs                   # WiX authoring: product, shortcut, upgrade rules
│   ├── build_msi.ps1                   # Build script: flutter build -> heat -> candle -> light
│   └── AppFiles.wxs                    # Payload harvested by heat (generated)
├── dist/                               # Output MSI (generated): md_reader-<version>-x64.msi
├── tools/                              # Local WiX v3 binaries (downloaded; not source)
├── analysis_options.yaml               # Lint rules (flutter_lints)
├── pubspec.yaml                        # Dependencies & project metadata
├── pubspec.lock                        # Resolved dependency versions
├── .metadata                           # Flutter project metadata
├── CLAUDE.md                           # Guidance for Claude Code
└── README.md
```

> **Note:** When new files are created, update this section so it reflects the current project structure.

## Architecture

State is managed with the **BLoC pattern** (`flutter_bloc`). Widgets only dispatch
events and render state; the `ReaderBloc` mediates between the UI and the
`MarkdownRepository`. Layering: `presentation` → `bloc` → `data`.

Key dependencies: [`flutter_bloc`](https://pub.dev/packages/flutter_bloc),
[`file_picker`](https://pub.dev/packages/file_picker),
[`desktop_drop`](https://pub.dev/packages/desktop_drop) (drag-and-drop file
target),
[`flutter_markdown`](https://pub.dev/packages/flutter_markdown),
[`flutter_mermaid`](https://pub.dev/packages/flutter_mermaid) (pure-Dart Mermaid
rendering, no WebView).

## Getting Started

### Prerequisites

- Flutter (stable channel) with the desktop toolchain for your platform.
- **Windows:** Developer Mode must be enabled — Flutter needs symlink support
  to build apps that use plugins (such as `file_picker`). Enable it once via
  *Settings → For developers*, or run:

  ```powershell
  start ms-settings:developers
  ```
- **macOS:** Xcode must be installed. The `macos/` runner is sandboxed
  (`com.apple.security.app-sandbox`); the `com.apple.security.files.user-selected.read-only`
  entitlement is already granted in both `DebugProfile.entitlements` and
  `Release.entitlements` so `file_picker` / `desktop_drop` can read
  user-chosen or dropped files.

### Run

```shell
flutter pub get          # install dependencies
flutter run -d windows   # launch the app on Windows
flutter run -d macos     # launch the app on macOS
```

### Develop

```shell
flutter analyze          # static analysis / lint
flutter test             # run all tests
dart format .            # format code
```

## Building a Windows installer (MSI)

The app is packaged into an MSI using the [WiX v3 toolset](https://github.com/wixtoolset/wix3).

1. **One-time setup:** download `wix314-binaries.zip` from the
   [WiX v3 releases](https://github.com/wixtoolset/wix3/releases) and extract it to
   `tools\wix` (so that `tools\wix\candle.exe`, `heat.exe` and `light.exe` exist).
2. **Build the installer:**

   ```powershell
   powershell -File installer\build_msi.ps1
   ```

   This builds the release, harvests the output with `heat`, and links
   `dist\md_reader-1.0.0-x64.msi`.

Install it by double-clicking the MSI: it requests admin rights, installs to
*Program Files\MD Reader*, and creates a Start Menu shortcut. The installer is
**not code-signed**, so Windows SmartScreen may show a warning on first run
(choose *More info → Run anyway*). To uninstall, use *Apps & features* or
*Add/Remove Programs*.
