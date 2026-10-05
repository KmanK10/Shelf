import Foundation

/// Wraps HTML from `GET /api/Book/{chapterId}/book-page` for WKWebView.
///
/// Kavita returns a scoped fragment and rewrites images to protocol-relative
/// `/api/Book/{chapterId}/book-resources?apiKey=…` URLs. A web view loaded from
/// a string has no scheme for those URLs, so Shelf pins them to the server scheme.
public enum EpubHTML {
    public static func document(from fragment: String, scheme: String) -> String {
        let rewritten = rewriteProtocolRelativeURLs(fragment, scheme: scheme)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta name="color-scheme" content="light dark">
        <style>
          :root { color-scheme: light dark; }
          html, body { margin: 0; padding: 0; background: transparent; color: CanvasText; }
          body { font: -apple-system-body; line-height: 1.45; }
          .book-content { padding: 20px 18px 48px; }
          img, svg, video { max-width: 100%; height: auto; }
          a { color: LinkText; }
        </style>
        </head>
        <body>
        <div class="book-content">
        \(rewritten)
        </div>
        <script>
        document.addEventListener('click', function (event) {
          var node = event.target;
          while (node && node !== document) {
            if (node.getAttribute && node.getAttribute('kavita-page') != null) {
              event.preventDefault();
              window.webkit.messageHandlers.shelf.postMessage(node.getAttribute('kavita-page'));
              return;
            }
            node = node.parentNode;
          }
        }, true);
        function shelfScrollTo(xpath) {
          try {
            var found = document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
            if (found && found.scrollIntoView) found.scrollIntoView({block: 'start'});
          } catch (error) {}
        }
        </script>
        </body>
        </html>
        """
    }

    public static func rewriteProtocolRelativeURLs(_ html: String, scheme: String) -> String {
        var result = html
        let replacements = [
            "src=\"//": "src=\"\(scheme)://",
            "href=\"//": "href=\"\(scheme)://",
            "src='//": "src='\(scheme)://",
            "href='//": "href='\(scheme)://",
            "url(//": "url(\(scheme)://",
            "url(\"//": "url(\"\(scheme)://"
        ]
        for (needle, replacement) in replacements {
            result = result.replacingOccurrences(of: needle, with: replacement)
        }
        return result
    }
}
