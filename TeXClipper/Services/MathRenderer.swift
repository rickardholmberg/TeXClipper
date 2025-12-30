import Foundation
import WebKit
import ObjectiveC
import PDFKit

// Helper class to wrap a closure as a WKScriptMessageHandler
private class WKScriptMessageHandlerWrapper: NSObject, WKScriptMessageHandler {
    private let handler: (WKScriptMessage) -> Void

    init(handler: @escaping (WKScriptMessage) -> Void) {
        self.handler = handler
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        handler(message)
    }
}

class MathRenderer: NSObject {
    static let shared = MathRenderer()

    private var webView: WKWebView?
    private var isReady = false
    private var pendingRenders: [(latex: String, callback: (Result<String, Error>) -> Void)] = []
    private var messageHandlers: [String: WKScriptMessageHandlerWrapper] = [:]

    override init() {
        super.init()
        setupWebView()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        
        // Security: Disable features we don't need
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // Register message handler for ready callback
        config.userContentController.add(self, name: "ready")

        // Enable JavaScript console logging (DEBUG builds only for security)
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self
        webView?.uiDelegate = self
        
        // Security: Disallow navigation to any other URL
        webView?.allowsBackForwardNavigationGestures = false

        print("WebView created, about to load MathJax...")
        loadMathJax()
    }

    private func loadMathJax() {
        // Try to find the resource in the bundle where this class is defined, or main bundle
        var mathjaxPath = Bundle(for: MathRenderer.self).path(forResource: "mathjax-tex-svg", ofType: "js") 
            ?? Bundle.main.path(forResource: "mathjax-tex-svg", ofType: "js")
            
        // Fallback for tests: Look in the source directory
        if mathjaxPath == nil {
            let currentDir = FileManager.default.currentDirectoryPath
            let localPath = currentDir + "/TeXClipper/Resources/mathjax-tex-svg.js"
            if FileManager.default.fileExists(atPath: localPath) {
                mathjaxPath = localPath
                print("Found MathJax at local path: \(localPath)")
            }
        }

        guard let path = mathjaxPath else {
            print("Error: Could not find MathJax file in bundle")
            return
        }

        guard let mathjaxJS = try? String(contentsOfFile: path) else {
            print("Error: Could not read MathJax file")
            return
        }

        print("Successfully loaded MathJax")
        print("  JS size: \(mathjaxJS.count) bytes")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <script>
            window.MathJax = {
                startup: {
                    ready: () => {
                        MathJax.startup.defaultReady();
                        window.webkit.messageHandlers.ready.postMessage('ready');
                    }
                },
                svg: {
                    fontCache: 'none'  // This makes MathJax use paths instead of font references
                }
            };
            </script>
            <script>\(mathjaxJS)</script>
        </head>
        <body>
            <div id="output"></div>
            <script>
                window.renderToSVG = async function(latex, displayMode) {
                    try {
                        console.log('renderToSVG called with:', latex, displayMode);

                        // Clear output
                        const output = document.getElementById('output');
                        output.innerHTML = '';

                        // Wrap in appropriate delimiters
                        const wrappedLatex = displayMode ? '\\\\[' + latex + '\\\\]' : '\\\\(' + latex + '\\\\)';
                        console.log('Wrapped latex:', wrappedLatex);

                        // Create a container for MathJax to render into
                        const container = document.createElement('div');
                        container.textContent = wrappedLatex;
                        output.appendChild(container);

                        // Typeset the math - await the Promise
                        console.log('Calling MathJax.typesetPromise...');
                        await MathJax.typesetPromise([container]);
                        console.log('MathJax.typesetPromise completed');

                        // Get the rendered SVG
                        const svgElement = output.querySelector('svg');
                        console.log('SVG element:', svgElement);
                        if (!svgElement) {
                            throw new Error('No SVG generated');
                        }

                        // Clone and add metadata with original LaTeX
                        const svgClone = svgElement.cloneNode(true);
                        const metadata = document.createElementNS('http://www.w3.org/2000/svg', 'metadata');
                        metadata.textContent = JSON.stringify({ latex: latex });
                        svgClone.insertBefore(metadata, svgClone.firstChild);

                        // Serialize to string
                        const serializer = new XMLSerializer();
                        const result = serializer.serializeToString(svgClone);
                        console.log('Returning SVG string of length:', result.length);
                        return result;
                    } catch (e) {
                        console.error('MathJax render error:', e);
                        throw new Error('MathJax render error: ' + e.message);
                    }
                };
            </script>
        </body>
        </html>
        """

        print("Loading HTML into WebView...")
        webView?.loadHTMLString(html, baseURL: nil)
        print("loadHTMLString called")
    }

    @MainActor
    func renderToSVG(latex: String) async throws -> String {
        // Strip leading and trailing whitespace from LaTeX
        let trimmedLatex = latex.trimmingCharacters(in: .whitespacesAndNewlines)

        return try await withCheckedThrowingContinuation { continuation in
            let callback: (Result<String, Error>) -> Void = { result in
                continuation.resume(with: result)
            }

            if !self.isReady {
                print("WebView not ready yet, queueing render for: \(trimmedLatex)")
                self.pendingRenders.append((latex: trimmedLatex, callback: callback))
                return
            }

            self.executeRender(latex: trimmedLatex, completion: callback)
        }
    }

    @MainActor
    func renderToSVGDirect(latex: String, displayMode: Bool = true) async throws -> String {
        // Strip leading and trailing whitespace from LaTeX
        let trimmedLatex = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        // Render to SVG using MathJax
        return try await renderToSVGInternal(latex: trimmedLatex, displayMode: displayMode)
    }

    @MainActor
    func renderToPDF(latex: String, displayMode: Bool = true) async throws -> Data {
        // Strip leading and trailing whitespace from LaTeX
        let trimmedLatex = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        // Render to SVG using MathJax, then convert SVG to PDF using WebKit
        let svgString = try await renderToSVGInternal(latex: trimmedLatex, displayMode: displayMode)

        // Use WebKit to render SVG to PDF (preserves vector graphics)
        return try await convertSVGToPDFWithWebKit(svgString: svgString, latex: trimmedLatex)
    }

    @MainActor
    private func renderToSVGInternal(latex: String, displayMode: Bool) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            // Use JSON encoding for safe parameter passing (prevents JavaScript injection)
            guard let latexData = try? JSONEncoder().encode(latex),
                  let latexJSON = String(data: latexData, encoding: .utf8) else {
                continuation.resume(throwing: NSError(domain: "MathRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode LaTeX as JSON"]))
                return
            }

            // Create a unique callback name for this render
            let callbackName = "callback_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"

            // Create a completion handler that will be called from JavaScript
            let messageHandler = WKScriptMessageHandlerWrapper { [weak self] message in
                guard let self = self else { return }

                if let payload = message.body as? [String: Any],
                   let kind = payload["kind"] as? String {
                    switch kind {
                    case "success":
                        if let svgString = payload["svg"] as? String {
                            print("Received SVG from JavaScript, length: \(svgString.count)")
                            continuation.resume(returning: svgString)
                        } else {
                            continuation.resume(throwing: NSError(domain: "MathRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing SVG payload"]))
                        }
                    case "error":
                        let errorMessage = payload["message"] as? String ?? "Unknown rendering error"
                        continuation.resume(throwing: NSError(domain: "MathRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
                    default:
                        continuation.resume(throwing: NSError(domain: "MathRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected message kind: \(kind)"]))
                    }
                } else {
                    continuation.resume(throwing: NSError(domain: "MathRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid result from JavaScript"]))
                }
                // Remove the handler after use
                self.webView?.configuration.userContentController.removeScriptMessageHandler(forName: callbackName)
                self.messageHandlers.removeValue(forKey: callbackName)
            }

            // Store the wrapper to keep it alive
            messageHandlers[callbackName] = messageHandler
            webView?.configuration.userContentController.add(messageHandler, name: callbackName)

            // Call the async function and send result back through the message handler
            // latexJSON is already a properly escaped JSON string literal, so we can use it directly
            let js = """
            (async function() {
                try {
                    const latex = \(latexJSON);
                    const result = await renderToSVG(latex, \(displayMode));
                    window.webkit.messageHandlers.\(callbackName).postMessage({ kind: 'success', svg: result });
                } catch (e) {
                    const errorMessage = (e && e.message) ? e.message : 'Unknown rendering error';
                    window.webkit.messageHandlers.\(callbackName).postMessage({ kind: 'error', message: errorMessage });
                }
            })();
            """

            webView?.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("JavaScript evaluation error (may be spurious for async code): \(error)")
                    // Note: evaluateJavaScript may report an error for async code that returns a Promise
                    // We rely on the message handler to get the actual result
                }
            }

            // Add a timeout in case the message handler is never called
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                guard let self = self else { return }
                if self.messageHandlers[callbackName] != nil {
                    print("Timeout waiting for JavaScript result")
                    self.webView?.configuration.userContentController.removeScriptMessageHandler(forName: callbackName)
                    self.messageHandlers.removeValue(forKey: callbackName)
                    continuation.resume(throwing: NSError(domain: "MathRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout waiting for rendering"]))
                }
            }
        }
    }

    @MainActor
    private func convertSVGToPDFWithWebKit(svgString: String, latex: String) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            // Create a temporary WKWebView for PDF rendering
            let config = WKWebViewConfiguration()
            let pdfWebView = WKWebView(frame: .zero, configuration: config)

            // Create HTML wrapper for the SVG
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <style>
                    body { margin: 0; padding: 0; }
                    svg { display: block; }
                </style>
            </head>
            <body>
            \(svgString)
            </body>
            </html>
            """

            // Load the HTML
            pdfWebView.loadHTMLString(html, baseURL: nil)

            // Wait for load to complete, then create PDF
            class PDFDelegate: NSObject, WKNavigationDelegate {
                let continuation: CheckedContinuation<Data, Error>
                let webView: WKWebView
                let latex: String

                init(continuation: CheckedContinuation<Data, Error>, webView: WKWebView, latex: String) {
                    self.continuation = continuation
                    self.webView = webView
                    self.latex = latex
                    super.init()
                }

                func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
                    // Wait a moment for rendering to complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // Get the actual content size
                        webView.evaluateJavaScript("document.body.scrollWidth") { width, _ in
                            webView.evaluateJavaScript("document.body.scrollHeight") { height, _ in
                                let w = (width as? CGFloat) ?? 800
                                let h = (height as? CGFloat) ?? 600

                                print("WebView content size: \(w) x \(h)")

                                // Create PDF from the WebView with proper size
                                let config = WKPDFConfiguration()
                                config.rect = CGRect(x: 0, y: 0, width: w, height: h)

                                webView.createPDF(configuration: config) { result in
                                    switch result {
                                    case .success(let pdfData):
                                        print("PDF created successfully, size: \(pdfData.count) bytes")

                                        // Add annotation with LaTeX metadata
                                        guard let pdfDocument = PDFDocument(data: pdfData),
                                              let firstPage = pdfDocument.page(at: 0) else {
                                            print("Failed to parse created PDF")
                                            self.continuation.resume(returning: pdfData)
                                            return
                                        }

                                        // Create an annotation with the LaTeX content
                                        let annotation = PDFAnnotation(bounds: CGRect.zero, forType: .text, withProperties: nil)
                                        annotation.contents = "TeXClipper:\(self.latex)"
                                        firstPage.addAnnotation(annotation)

                                        // Return the modified PDF
                                        if let annotatedPDFData = pdfDocument.dataRepresentation() {
                                            print("Added LaTeX annotation to PDF")
                                            self.continuation.resume(returning: annotatedPDFData)
                                        } else {
                                            print("Failed to get data representation of annotated PDF")
                                            self.continuation.resume(returning: pdfData)
                                        }

                                    case .failure(let error):
                                        print("PDF creation failed: \(error)")
                                        self.continuation.resume(throwing: error)
                                    }
                                }
                            }
                        }
                    }
                }

                func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
                    self.continuation.resume(throwing: error)
                }
            }

            let delegate = PDFDelegate(continuation: continuation, webView: pdfWebView, latex: latex)
            pdfWebView.navigationDelegate = delegate

            // Keep delegate alive with associated object
            objc_setAssociatedObject(pdfWebView, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private func executeRender(latex: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Use JSON encoding for safe parameter passing (prevents JavaScript injection)
        guard let latexData = try? JSONEncoder().encode(latex),
              let latexJSON = String(data: latexData, encoding: .utf8) else {
            completion(.failure(NSError(domain: "MathRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode LaTeX as JSON"])))
            return
        }

        // MathJax renderToSVG returns a Promise, so we need to handle it asynchronously
        // latexJSON is already a properly escaped JSON string literal, so we can use it directly
        let js = "(async function() { const latex = \(latexJSON); return await renderToSVG(latex, true); })()"

        // Must call evaluateJavaScript on main thread - already on main thread from caller
        self.webView?.evaluateJavaScript(js) { result, error in
            if let error = error {
                completion(.failure(error))
            } else if let svg = result as? String {
                completion(.success(svg))
            } else {
                completion(.failure(NSError(domain: "MathRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid result from renderer"])))
            }
        }
    }

    func extractLatexFromSVG(_ svg: String) -> String? {
        guard let metadataRange = svg.range(of: "<metadata>.*?</metadata>", options: .regularExpression) else {
            return nil
        }

        let metadata = String(svg[metadataRange])
        guard let contentRange = metadata.range(of: "(?<=<metadata>).*?(?=</metadata>)", options: .regularExpression) else {
            return nil
        }

        let jsonString = String(metadata[contentRange])
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let latex = dict["latex"] else {
            return nil
        }

        return latex
    }
}

extension MathRenderer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("MathJax WebView loaded successfully")
        isReady = true
        print("Pending renders count: \(pendingRenders.count)")

        // Execute any pending renders that were queued before webview was ready
        for pending in pendingRenders {
            executeRender(latex: pending.latex, completion: pending.callback)
        }
        pendingRenders.removeAll()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("WebView navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("WebView provisional navigation failed: \(error.localizedDescription)")
    }
}

extension MathRenderer: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("Script message received: \(message.name) = \(message.body)")
        if message.name == "ready" {
            print("Ready message received, setting isReady = true")
            isReady = true
        }
    }
}

extension MathRenderer: WKUIDelegate {
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        print("[JS Alert] \(message)")
        completionHandler()
    }

}
