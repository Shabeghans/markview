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
- Follows system light/dark mode
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
