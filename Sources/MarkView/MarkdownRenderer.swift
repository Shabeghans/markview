import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Converts Markdown to HTML with cmark-gfm (the parser GitHub uses).
enum MarkdownRenderer {
    private static let registerExtensions: Void = {
        cmark_gfm_core_extensions_ensure_registered()
    }()

    private static let extensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]

    static func html(from markdown: String) -> String {
        _ = registerExtensions
        let (frontMatter, body) = splitFrontMatter(markdown)

        // UNSAFE keeps inline HTML (like MacDown); the tagfilter extension still
        // neutralises <script>, <iframe>, <style> and friends.
        let options = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_VALIDATE_UTF8
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        var utf8 = Array(body.utf8)
        utf8.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buf.count) { ptr in
                cmark_parser_feed(parser, ptr, buf.count)
            }
        }
        guard let doc = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(doc) }

        guard let cString = cmark_render_html(doc, options, cmark_parser_get_syntax_extensions(parser)) else {
            return ""
        }
        defer { free(cString) }

        return (frontMatter.map(renderFrontMatter) ?? "") + String(cString: cString)
    }

    // MARK: - YAML front matter

    /// Splits a leading `---` … `---` block off the document.
    private static func splitFrontMatter(_ text: String) -> ([String]?, String) {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return (nil, text) }
        let lines = text.components(separatedBy: "\n")
        for i in 1..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "---" || line == "..." {
                let front = Array(lines[1..<i]).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
                let rest = lines[(i + 1)...].joined(separator: "\n")
                return (front, rest)
            }
        }
        return (nil, text)
    }

    /// Renders simple `key: value` front matter as a table, anything else as a code block.
    private static func renderFrontMatter(_ lines: [String]) -> String {
        var rows: [(String, String)] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if let first = line.first, first == " " || first == "\t" || first == "-" {
                guard !rows.isEmpty else { return frontMatterAsCode(lines) }
                rows[rows.count - 1].1 += (rows[rows.count - 1].1.isEmpty ? "" : "\n") + line
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { return frontMatterAsCode(lines) }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            rows.append((key, value))
        }
        guard !rows.isEmpty else { return "" }
        var html = "<table class=\"frontmatter\"><tbody>"
        for (key, value) in rows {
            html += "<tr><th>\(escape(key))</th><td>\(escape(value))</td></tr>"
        }
        return html + "</tbody></table>\n"
    }

    private static func frontMatterAsCode(_ lines: [String]) -> String {
        "<pre class=\"frontmatter\"><code class=\"language-yaml\">\(escape(lines.joined(separator: "\n")))</code></pre>\n"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
