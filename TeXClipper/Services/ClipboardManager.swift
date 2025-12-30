import Foundation
import AppKit
import PDFKit
import ApplicationServices

extension NSImage {
    var pngRepresentation: Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }
}

enum PasteContent {
    case text(String)
    case svg(String)
    case pdfWithSVG(pdfData: Data, svgString: String)
}

private struct PasteboardSnapshotItem {
    let dataByType: [String: Data]
}

private struct PasteboardSnapshot {
    let items: [PasteboardSnapshotItem]

    init(pasteboard: NSPasteboard) {
        self.items = pasteboard.pasteboardItems?.map { item in
            var payload: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    payload[type.rawValue] = data
                }
            }
            return PasteboardSnapshotItem(dataByType: payload)
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restoredItems: [NSPasteboardItem] = items.map { snapshot in
            let item = NSPasteboardItem()
            for (typeName, data) in snapshot.dataByType {
                item.setData(data, forType: NSPasteboard.PasteboardType(typeName))
            }
            return item
        }

        pasteboard.writeObjects(restoredItems)
    }
}

protocol LaTeXExtractionStrategy {
    func extract(from pasteboard: NSPasteboard, renderer: MathRenderer, pdfExtractor: (Data) -> String?) -> String?
}

struct RTFDExtractionStrategy: LaTeXExtractionStrategy {
    func extract(from pasteboard: NSPasteboard, renderer: MathRenderer, pdfExtractor: (Data) -> String?) -> String? {
        // Note: Returns nil here because RTFD needs special handling that returns NSAttributedString
        // This is handled separately in revertSVGToLatex
        return nil
    }
}

struct CustomSVGExtractionStrategy: LaTeXExtractionStrategy {
    func extract(from pasteboard: NSPasteboard, renderer: MathRenderer, pdfExtractor: (Data) -> String?) -> String? {
        guard let svgData = pasteboard.data(forType: NSPasteboard.PasteboardType("com.TeXClipper.svg")),
              let svgString = String(data: svgData, encoding: .utf8) else {
            return nil
        }
        print("Found TeXClipper SVG data, extracting LaTeX")
        return renderer.extractLatexFromSVG(svgString)
    }
}

struct PublicSVGExtractionStrategy: LaTeXExtractionStrategy {
    func extract(from pasteboard: NSPasteboard, renderer: MathRenderer, pdfExtractor: (Data) -> String?) -> String? {
        guard let svgData = pasteboard.data(forType: NSPasteboard.PasteboardType("public.svg-image")),
              let svgString = String(data: svgData, encoding: .utf8) else {
            return nil
        }
        print("Found public SVG data, extracting LaTeX")
        return renderer.extractLatexFromSVG(svgString)
    }
}

struct TextSVGExtractionStrategy: LaTeXExtractionStrategy {
    func extract(from pasteboard: NSPasteboard, renderer: MathRenderer, pdfExtractor: (Data) -> String?) -> String? {
        guard let text = pasteboard.string(forType: .string) else {
            return nil
        }
        print("Checking if text contains SVG")
        return renderer.extractLatexFromSVG(text)
    }
}

struct PDFExtractionStrategy: LaTeXExtractionStrategy {
    func extract(from pasteboard: NSPasteboard, renderer: MathRenderer, pdfExtractor: (Data) -> String?) -> String? {
        guard let pdfData = pasteboard.data(forType: .pdf) else {
            return nil
        }
        print("Found PDF data on clipboard, extracting PDF data")
        return pdfExtractor(pdfData)
    }
}

@MainActor
class ClipboardManager {
    private let renderer = MathRenderer.shared

    init() {
        checkAccessibilityPermissions()
    }

    private func checkAccessibilityPermissions() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("⚠️ WARNING: Accessibility permissions not granted!")
            print("Go to System Settings > Privacy & Security > Accessibility")
            print("Add TeXClipper to the list and enable it")

            // Prompt for permission
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
        } else {
            print("✓ Accessibility permissions granted")
        }
    }

    /// Perform a copy operation by posting a copy event
    private func performCopy() {
        // Create a copy event (Cmd+C) using CGEvent
        let copyEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: true) // 'C' key
        copyEvent?.flags = .maskCommand
        copyEvent?.post(tap: .cghidEventTap)

        let copyEventUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: false)
        copyEventUp?.post(tap: .cghidEventTap)

        print("Posted copy event")
    }

    /// Perform a paste operation by posting a paste event
    private func performPaste() {
        // Create a paste event (Cmd+V) using CGEvent
        let pasteEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true) // 'V' key
        pasteEvent?.flags = .maskCommand
        pasteEvent?.post(tap: .cghidEventTap)

        let pasteEventUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        pasteEventUp?.post(tap: .cghidEventTap)

        print("Posted paste event")
    }

    /// Execute an operation with automatic clipboard state restoration
    private func withClipboardRestore<T>(_ operation: (NSPasteboard) async throws -> T) async rethrows -> T {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        defer { snapshot.restore(to: pasteboard) }
        return try await operation(pasteboard)
    }

    func convertSelectionToSVG(displayMode: Bool = true) async {
        let selectedText = await getSelectedText()

        guard !selectedText.isEmpty else {
            print("No text selected")
            return
        }

        do {
            // Render to SVG first (contains LaTeX metadata)
            let svgString = try await renderer.renderToSVGDirect(latex: selectedText, displayMode: displayMode)

            // Also create PDF for better compatibility
            let pdfData = try await renderer.renderToPDF(latex: selectedText, displayMode: displayMode)

            await replaceSelection(with: .pdfWithSVG(pdfData: pdfData, svgString: svgString))

            print("Successfully converted LaTeX to PDF vector (displayMode: \(displayMode))")
        } catch {
            print("Error rendering LaTeX: \(error)")
        }
    }

    func revertSVGToLatex() async {
        await withClipboardRestore { pasteboard in
            let oldChangeCount = pasteboard.changeCount
            
            // Copy selection to clipboard
            performCopy()

            // Wait for clipboard to update
            _ = await waitForClipboardChange(oldChangeCount: oldChangeCount)

            // Try to extract LaTeX from all images in the selection
            var resultAttributedString: NSAttributedString?
            var resultText: String?

            // First check for RTFD data (rich text with attachments) - this can contain multiple images
            if let rtfdData = pasteboard.data(forType: .rtfd) {
                print("Found RTFD data on clipboard, extracting all LaTeX from attachments")
                resultAttributedString = extractAllLatexFromRTFD(rtfdData)
            }

            // If no RTFD, try single image formats using extraction strategies
            if resultAttributedString == nil {
                resultText = tryExtractionStrategies(from: pasteboard)
            }

            // Paste the result (either RTFD or plain text)
            if let resultAttributedString = resultAttributedString {
                print("Pasting RTFD with \(resultAttributedString.length) characters")
                // Replace selection with attributed string (preserves non-LaTeX images)
                pasteboard.clearContents()

                // Convert to RTFD data for pasting
                if let rtfdData = try? resultAttributedString.data(from: NSRange(location: 0, length: resultAttributedString.length),
                                                                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) {
                    pasteboard.setData(rtfdData, forType: .rtfd)

                    // Paste it
                    performPaste()

                    await sleep(milliseconds: 200)
                    print("Successfully reverted to LaTeX (RTFD)")
                }
            } else if let resultText = resultText {
                print("Extracted LaTeX: \(resultText)")
                // Replace selection with LaTeX (plain text)
                pasteboard.clearContents()
                pasteboard.setString(resultText, forType: .string)

                // Paste it
                performPaste()

                await sleep(milliseconds: 200)
                print("Successfully reverted to LaTeX (plain text)")
            } else {
                print("Could not extract LaTeX from clipboard - no SVG metadata found")
            }
        }
    }

    private func tryExtractionStrategies(from pasteboard: NSPasteboard) -> String? {
        let strategies: [LaTeXExtractionStrategy] = [
            CustomSVGExtractionStrategy(),
            PublicSVGExtractionStrategy(),
            TextSVGExtractionStrategy(),
            PDFExtractionStrategy()
        ]

        for strategy in strategies {
            if let latex = strategy.extract(from: pasteboard, renderer: renderer, pdfExtractor: extractLatexFromPDF) {
                return latex
            }
        }

        return nil
    }

    private func getSelectedText() async -> String {
        await withClipboardRestore { pasteboard in
            // Save current clipboard state for comparison
            let oldChangeCount = pasteboard.changeCount
            let oldContents = pasteboard.string(forType: .string)

            let previousClipboard = oldContents ?? "nil"
            print("Old clipboard contents: \(previousClipboard)")
            print("Old change count: \(oldChangeCount)")

            // Copy selection to clipboard
            performCopy()

            // Wait for clipboard to update
            let changed = await waitForClipboardChange(oldChangeCount: oldChangeCount)
            
            if changed {
                print("Clipboard updated (changeCount: \(oldChangeCount) -> \(pasteboard.changeCount))")
            } else {
                print("WARNING: Clipboard did not update within timeout")
            }

            let selectedText = pasteboard.string(forType: .string) ?? ""
            print("Captured text length: \(selectedText.count)")

            return selectedText
        }
    }

    private func replaceSelection(with content: PasteContent) async {
        await withClipboardRestore { pasteboard in
            pasteboard.clearContents()

            switch content {
            case .text(let text):
                print("Replacing selection with text (length: \(text.count))")
                pasteboard.setString(text, forType: .string)

            case .svg(let svgString):
                print("Replacing selection with SVG (vector)")
                guard let svgData = svgString.data(using: .utf8) else {
                    print("Failed to convert SVG string to data")
                    return
                }

                // Try multiple formats for maximum compatibility
                // 1. SVG as image data (for apps that support SVG)
                pasteboard.setData(svgData, forType: NSPasteboard.PasteboardType("public.svg-image"))

                // 2. Create NSImage from SVG for apps that don't support SVG directly
                if let image = NSImage(data: svgData) {
                    // Set TIFF representation which preserves vector data when possible
                    if let tiffData = image.tiffRepresentation {
                        pasteboard.setData(tiffData, forType: .tiff)
                    }
                }
                print("SVG added to pasteboard")

            case .pdfWithSVG(let pdfData, let svgString):
                print("Replacing selection with PDF + SVG metadata (vector)")
                guard let svgData = svgString.data(using: .utf8) else {
                    print("Failed to convert SVG to data")
                    return
                }

                // 1. PDF for display (primary format most apps will use)
                pasteboard.setData(pdfData, forType: .pdf)

                // 2. SVG with LaTeX metadata for revert functionality
                pasteboard.setData(svgData, forType: NSPasteboard.PasteboardType("public.svg-image"))

                // 3. Also add as custom type for guaranteed retrieval
                pasteboard.setData(svgData, forType: NSPasteboard.PasteboardType("com.TeXClipper.svg"))
                print("PDF and SVG added to pasteboard")
            }

            // Paste the content
            performPaste()
            await sleep(milliseconds: 200)

            print("Selection replaced")
        }
    }

    private func replaceSelectionWithPDF(_ pdfData: Data) async {
        await withClipboardRestore { pasteboard in
            print("Replacing selection with PDF (vector)")

            // Clear and set PDF data
            pasteboard.clearContents()

            // Write PDF to pasteboard - it's vector and will scale perfectly
            pasteboard.setData(pdfData, forType: .pdf)
            print("PDF added to pasteboard")

            // Create and post Cmd+V event
            let source = CGEventSource(stateID: .hidSystemState)

            // Key down
            if let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) {
                cmdVDown.flags = .maskCommand
                cmdVDown.post(tap: .cghidEventTap)
            }

            // Key up
            if let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
                cmdVUp.post(tap: .cghidEventTap)
            }

            print("Posted Cmd+V event for PDF")

            // Wait for paste to complete
            await sleep(milliseconds: 200)

            print("PDF pasted")
        }
    }

    func extractAllLatexFromRTFD(_ rtfdData: Data) -> NSAttributedString? {
        // RTFD is a wrapper format that can contain file attachments
        // Try to parse it as an NSAttributedString to access attachments
        guard let attributedString = try? NSAttributedString(data: rtfdData,
                                                              options: [.documentType: NSAttributedString.DocumentType.rtfd],
                                                              documentAttributes: nil) else {
            print("Failed to parse RTFD data")
            return nil
        }

        print("Processing RTFD with \(attributedString.length) characters")

        // Collect all attachments
        let attachmentRanges = collectAttachments(from: attributedString)
        print("Found \(attachmentRanges.count) attachments")

        // Build result string by processing each attachment
        let result = buildResultString(from: attributedString, attachments: attachmentRanges)

        print("Final result has \(result.length) characters")
        return result.length > 0 ? result : nil
    }

    private func collectAttachments(from attributedString: NSAttributedString) -> [(range: NSRange, attachment: NSTextAttachment)] {
        var attachmentRanges: [(range: NSRange, attachment: NSTextAttachment)] = []
        attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedString.length), options: []) { value, range, stop in
            if let attachment = value as? NSTextAttachment {
                attachmentRanges.append((range: range, attachment: attachment))
            }
        }
        return attachmentRanges
    }

    private func buildResultString(from attributedString: NSAttributedString, attachments: [(range: NSRange, attachment: NSTextAttachment)]) -> NSMutableAttributedString {
        let mutableResult = NSMutableAttributedString()
        var currentIndex = 0

        for (range, attachment) in attachments {
            // Add text before this attachment
            if range.location > currentIndex {
                let textRange = NSRange(location: currentIndex, length: range.location - currentIndex)
                let textBefore = attributedString.attributedSubstring(from: textRange)
                print("Adding text before attachment at \(range.location): '\(textBefore.string)'")
                mutableResult.append(textBefore)
            }

            // Try to extract LaTeX from this attachment
            let latex = extractLatexFromAttachment(attachment)

            // Add the extracted LaTeX or preserve the original attachment
            if let latex = latex {
                print("Extracted LaTeX from attachment: \(latex)")
                mutableResult.append(NSAttributedString(string: latex))
            } else {
                print("Could not extract LaTeX from attachment, preserving original attachment")
                let originalSubstring = attributedString.attributedSubstring(from: range)
                print("Original substring length: \(originalSubstring.length), string: '\(originalSubstring.string)'")
                mutableResult.append(originalSubstring)
            }

            currentIndex = range.location + range.length
        }

        // Add any remaining text after the last attachment
        if currentIndex < attributedString.length {
            let textRange = NSRange(location: currentIndex, length: attributedString.length - currentIndex)
            let textAfter = attributedString.attributedSubstring(from: textRange)
            print("Adding text after last attachment: '\(textAfter.string)'")
            mutableResult.append(textAfter)
        }

        return mutableResult
    }

    private func extractLatexFromAttachment(_ attachment: NSTextAttachment) -> String? {
        // Try file wrapper first
        if let fileWrapper = attachment.fileWrapper {
            print("Found file attachment in RTFD: \(fileWrapper.preferredFilename ?? "unknown")")

            // Check if it's an SVG file
            if let filename = fileWrapper.preferredFilename, filename.hasSuffix(".svg"),
               let data = fileWrapper.regularFileContents,
               let svgString = String(data: data, encoding: .utf8),
               let latex = renderer.extractLatexFromSVG(svgString) {
                print("Found SVG attachment, extracting LaTeX")
                return latex
            }

            // Check for PDF attachments
            if let filename = fileWrapper.preferredFilename, filename.hasSuffix(".pdf"),
               let data = fileWrapper.regularFileContents,
               let latex = extractLatexFromPDF(data) {
                print("Found PDF attachment in RTFD (size: \(data.count) bytes)")
                return latex
            }
        }

        // Try attachment contents
        if let imageData = attachment.contents {
            print("Found attachment with contents (size: \(imageData.count) bytes)")

            // Try to parse as SVG
            if let svgString = String(data: imageData, encoding: .utf8),
               let latex = renderer.extractLatexFromSVG(svgString) {
                print("  Successfully extracted LaTeX from SVG")
                return latex
            }

            // Try to parse as PDF
            if let latex = extractLatexFromPDF(imageData) {
                print("  Successfully extracted LaTeX from PDF")
                return latex
            } else {
                print("  Could not extract LaTeX from PDF - this is likely a non-LaTeX image")
            }
        }

        return nil
    }

    private func extractLatexFromRTFD(_ rtfdData: Data) -> String? {
        // Single-image version for backward compatibility
        // RTFD is a wrapper format that can contain file attachments
        // Try to parse it as an NSAttributedString to access attachments
        guard let attributedString = try? NSAttributedString(data: rtfdData,
                                                              options: [.documentType: NSAttributedString.DocumentType.rtfd],
                                                              documentAttributes: nil) else {
            print("Failed to parse RTFD data")
            return nil
        }

        // Enumerate through the attributes looking for attachments
        var foundLatex: String?
        attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedString.length), options: []) { value, range, stop in
            guard let attachment = value as? NSTextAttachment else { return }

            // Check if the attachment has file wrapper (contains the actual data)
            if let fileWrapper = attachment.fileWrapper {
                print("Found file attachment in RTFD: \(fileWrapper.preferredFilename ?? "unknown")")

                // Check if it's an SVG file
                if let filename = fileWrapper.preferredFilename, filename.hasSuffix(".svg"),
                   let data = fileWrapper.regularFileContents,
                   let svgString = String(data: data, encoding: .utf8) {
                    print("Found SVG attachment, extracting LaTeX")
                    if let latex = renderer.extractLatexFromSVG(svgString) {
                        foundLatex = latex
                        stop.pointee = true
                    }
                }

                // Also check for PDF attachments
                if let filename = fileWrapper.preferredFilename, filename.hasSuffix(".pdf"),
                   let data = fileWrapper.regularFileContents {
                    print("Found PDF attachment in RTFD (size: \(data.count) bytes)")
                    if let latex = extractLatexFromPDF(data) {
                        foundLatex = latex
                        stop.pointee = true
                    }
                }
            }

            // Also try to get image data from the attachment
            if let imageData = attachment.contents {
                print("Found attachment with contents (size: \(imageData.count) bytes)")

                // Try to parse as SVG
                if let svgString = String(data: imageData, encoding: .utf8) {
                    if let latex = renderer.extractLatexFromSVG(svgString) {
                        foundLatex = latex
                        stop.pointee = true
                    }
                }
            }
        }

        return foundLatex
    }

    private func extractLatexFromPDF(_ pdfData: Data) -> String? {
        // Create a PDF document from the data
        guard let pdfDocument = PDFDocument(data: pdfData) else {
            print("Failed to create PDF document from data")
            return nil
        }

        print("PDF has \(pdfDocument.pageCount) page(s)")

        // Try to extract LaTeX from PDF metadata
        // Check document attributes first
        if let attributes = pdfDocument.documentAttributes {
            print("PDF attributes: \(attributes.keys)")

            // Check for custom metadata that might contain LaTeX
            if let subject = attributes["Subject"] as? String {
                print("PDF Subject: \(subject)")
                if subject.hasPrefix("TeXClipper:") {
                    let latex = String(subject.dropFirst("TeXClipper:".count))
                    print("Found LaTeX in Subject metadata: \(latex)")
                    return latex
                }
            }

            if let keywords = attributes["Keywords"] as? String {
                print("PDF Keywords: \(keywords)")
                if keywords.hasPrefix("TeXClipper:") {
                    let latex = String(keywords.dropFirst("TeXClipper:".count))
                    print("Found LaTeX in Keywords metadata: \(latex)")
                    return latex
                }
            }
        }

        // Try to extract text from the PDF (looking for embedded SVG or LaTeX)
        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            // Get the page's data representation and look for embedded SVG
            if let pageData = page.dataRepresentation {
                if let pageString = String(data: pageData, encoding: .utf8) {
                    // Look for SVG embedded in the PDF stream
                    if let latex = renderer.extractLatexFromSVG(pageString) {
                        print("Found LaTeX in embedded SVG on page \(pageIndex)")
                        return latex
                    }
                }
            }

            // Also check annotations
            for annotation in page.annotations {
                if let contents = annotation.contents {
                    print("PDF annotation contents: \(contents)")
                    if contents.hasPrefix("TeXClipper:") {
                        let latex = String(contents.dropFirst("TeXClipper:".count))
                        print("Found LaTeX in annotation: \(latex)")
                        return latex
                    }
                }
            }
        }

        print("Could not extract LaTeX from PDF")
        return nil
    }

    private func sleep(milliseconds: UInt64) async {
        let nanoseconds = milliseconds * 1_000_000
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    private func waitForClipboardChange(oldChangeCount: Int, timeout: TimeInterval = 1.0) async -> Bool {
        let startTime = Date()
        let pasteboard = NSPasteboard.general

        while Date().timeIntervalSince(startTime) < timeout {
            if pasteboard.changeCount != oldChangeCount {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        return false
    }
}

