import Foundation

enum PageTemplate {
    static var webDirectory: URL {
        Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
    }

    private static func asset(_ name: String) -> String {
        LocalSchemeHandler.url(for: webDirectory.appendingPathComponent(name)).absoluteString
    }

    static func page(body: String, showTOC: Bool) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <link rel="stylesheet" href="\(asset("github-markdown.css"))">
        <link rel="stylesheet" href="\(asset("hljs-light.css"))" media="(prefers-color-scheme: light)">
        <link rel="stylesheet" href="\(asset("hljs-dark.css"))" media="(prefers-color-scheme: dark)">
        <link rel="stylesheet" href="\(asset("app.css"))">
        </head>
        <body class="\(showTOC ? "toc-open" : "")" data-mermaid-src="\(asset("mermaid.min.js"))">
        <nav id="toc" aria-label="Table of contents"></nav>
        <main id="content" class="markdown-body">\(body)</main>
        <script src="\(asset("highlight.min.js"))"></script>
        <script src="\(asset("app.js"))"></script>
        </body>
        </html>
        """
    }
}
