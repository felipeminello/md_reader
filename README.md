# MD Reader

A simple Flutter application for reading Markdown files on the **Windows desktop**.
Pick a `.md` file from your system, view it rendered on screen, and close it to
go back to the empty state.

## Features

- 📂 Select a Markdown file through the native Windows file picker
  (`.md`, `.markdown`, `.mdown`, `.mkd`, `.txt`).
- 📖 Read and render the file as formatted, selectable, scrollable text.
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
│       │   ├── reader_event.dart       # Events: open file / close file
│       │   └── reader_state.dart       # States: empty / loading / loaded / failure
│       └── presentation/
│           ├── reader_page.dart        # Main screen (BlocBuilder / BlocConsumer)
│           └── widgets/
│               ├── markdown_view.dart      # Renders a loaded document
│               └── reader_empty_view.dart  # Empty-state placeholder + open button
├── test/
│   └── widget_test.dart                # ReaderBloc + ReaderPage tests
├── windows/                            # Windows desktop runner (only configured platform)
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
[`flutter_markdown`](https://pub.dev/packages/flutter_markdown).

## Getting Started

### Prerequisites

- Flutter (stable channel) with the Windows desktop toolchain.
- **Windows Developer Mode must be enabled** — Flutter needs symlink support to
  build apps that use plugins (such as `file_picker`). Enable it once via
  *Settings → For developers*, or run:

  ```powershell
  start ms-settings:developers
  ```

### Run

```powershell
flutter pub get          # install dependencies
flutter run -d windows   # launch the app
```

### Develop

```powershell
flutter analyze          # static analysis / lint
flutter test             # run all tests
dart format .            # format code
```
