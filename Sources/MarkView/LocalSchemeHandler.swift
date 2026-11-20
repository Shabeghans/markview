import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves local files (bundled CSS/JS and images next to the Markdown file)
/// to the web view under a custom scheme, so relative image paths work.
final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mvlocal"

    /// `mvlocal:///absolute/path` for a file URL.
    static func url(for fileURL: URL) -> URL {
        let path = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileURL.path
        return URL(string: "\(scheme)://\(path)")!
    }

    /// The file URL a `mvlocal:` URL points at.
    static func fileURL(for url: URL) -> URL {
        URL(fileURLWithPath: url.path)
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let path = url.path
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let ext = (path as NSString).pathExtension
            let type = UTType(filenameExtension: ext)
            let mime = type?.preferredMIMEType ?? "application/octet-stream"
            let isText = type?.conforms(to: .text) ?? false
            let response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count,
                                       textEncodingName: isText ? "utf-8" : nil)
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        } catch {
            task.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
