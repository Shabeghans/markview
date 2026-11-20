# MarkView

A fast, native Markdown viewer for macOS (Apple Silicon) with a deliberately basic plain-text editor.
Built as a replacement for MacDown, which ships as an Intel-only binary and runs under Rosetta.

## Features

- Renders GitHub-flavoured Markdown with cmark-gfm: tables, footnotes, task lists, strikethrough, autolinks, and YAML front matter shown as a table
- **Live reload**: updates automatically when the file changes on disk, keeping your scroll position. ⌘R reloads by hand.
- Syntax-coloured code blocks with a Copy button on each block
- Mermaid diagrams (the library only loads for documents that contain one)
- Table of contents sidebar (⌥⌘T)
- **Find** (⌘F) in the preview: highlights every match, shows "3 of 12", ⌘G / ⇧⌘G or Return / ⇧Return to step, Esc to close. Matches can span formatting.
- Light/dark mode: follows the system by default. The toolbar sun/moon button switches it, and View > Appearance has System, Light (⌃⌘L) and Dark (⌃⌘D).
- **`md2pdf` command** for scripts and AI agents (see below)
- **Copy Markdown** toolbar button (⇧⌘C) copies the raw source
- **Export as PDF** (⇧⌘E) writes a paginated PDF to `~/Downloads`, always in light colors
- **Edit Markdown** (⌘E): plain-text editor with undo, find (⌘F) and save (⌘S)
- Print (⌘P), zoom (⌘+ / ⌘- / ⌘0), Open Recent, tabs

## Build

Requires Xcode (Swift 5.10+), macOS 13+.

```sh
./scripts/build.sh            # builds build/MarkView.app
./scripts/build.sh --install  # also installs to /Applications and registers it
```

## md2pdf (command line)

`build.sh --install` also installs `~/bin/md2pdf`, which converts Markdown to PDF headlessly with the same renderer and page settings as File > Export as PDF:

```sh
md2pdf notes.md                 # → ~/Downloads/notes.pdf (adds " 2", " 3"… instead of overwriting)
md2pdf notes.md out.pdf         # explicit file
md2pdf notes.md some/dir        # → some/dir/notes.pdf
pdf=$(md2pdf notes.md) && sendphone "$pdf"   # prints the PDF path on success
```

Exit code 0 on success, 1 on failure (message on stderr), 2 for bad usage. It's a wrapper around `MarkView --pdf`; no window or Dock icon appears.

## Layout

- `Sources/MarkView/`: the app (AppKit + WKWebView)
- `Resources/web/`: page script/styles plus vendored libraries
- `Resources/Info.plist`: bundle metadata and the `.md` document type
- `scripts/`: the build script and the icon generator

## Third-party

- [cmark-gfm](https://github.com/apple/swift-cmark) (BSD-2-Clause)
- [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) 5.8.1 (MIT)
- [highlight.js](https://highlightjs.org) 11.11.1 (BSD-3-Clause)
- [Mermaid](https://mermaid.js.org) 11.4.1 (MIT)
