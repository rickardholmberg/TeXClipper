import Foundation
import AppKit
import PDFKit

extension NSImage {
    var pngRepresentation: Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }
}

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

            await replaceSelectionWithPDFAndSVG(pdfData: pdfData, svgString: svgString)

            print("Successfully converted LaTeX to PDF vector (displayMode: \(displayMode))")
        } catch {
            print("Error rendering LaTeX: \(error)")
        }
    }

    func revertSVGToLatex() async {
        await MainActor.run {
            let pasteboard = NSPasteboard.general

            // First try to get the currently selected item by copying it
            let oldChangeCount = pasteboard.changeCount
            let oldContents = pasteboard.string(forType: .string)

            // Clear and copy selection
            //pasteboard.clearContents()

            let source = CGEventSource(stateID: .combinedSessionState)
            guard let source = source else {
                print("Failed to create CGEventSource for revert")
                return
            }

            // Simulate Cmd+C
            if let cmdCDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
               let cmdCUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) {
                cmdCDown.flags = .maskCommand
                cmdCDown.post(tap: .cghidEventTap)
                cmdCUp.post(tap: .cghidEventTap)
            }

            Thread.sleep(forTimeInterval: 0.3)

            // Try to get SVG or PDF data with embedded LaTeX
            var latex: String?

            // Check for our custom SVG format first (most reliable)
            if let svgData = pasteboard.data(forType: NSPasteboard.PasteboardType("com.TeXClipper.svg")) {
                if let svgString = String(data: svgData, encoding: .utf8) {
                    print("Found TeXClipper SVG data, extracting LaTeX")
                    latex = renderer.extractLatexFromSVG(svgString)
                }
            }

            // Check for standard SVG data
            if latex == nil, let svgData = pasteboard.data(forType: NSPasteboard.PasteboardType("public.svg-image")) {
                if let svgString = String(data: svgData, encoding: .utf8) {
                    print("Found public SVG data, extracting LaTeX")
                    latex = renderer.extractLatexFromSVG(svgString)
                }
            }

            // Check for text (maybe it's SVG as text)
            if latex == nil, let text = pasteboard.string(forType: .string) {
                print("Checking if text contains SVG")
                latex = renderer.extractLatexFromSVG(text)
            }

            // Check for RTFD data (rich text with attachments)
            if latex == nil, let rtfdData = pasteboard.data(forType: .rtfd) {
                print("Found RTFD data on clipboard, extracting attachments")
                latex = extractLatexFromRTFD(rtfdData)
            }

            // If still no luck, check PDF directly
            if latex == nil, let pdfData = pasteboard.data(forType: .pdf) {
                print("Found PDF data on clipboard, extracting PDF data")
                latex = extractLatexFromPDF(pdfData)
            }

            if let latex = latex {
                print("Extracted LaTeX: \(latex)")
                // Replace selection with LaTeX
                pasteboard.clearContents()
                pasteboard.setString(latex, forType: .string)

                // Paste it
                if let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
                   let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
                    cmdVDown.flags = .maskCommand
                    cmdVDown.post(tap: .cghidEventTap)
                    cmdVUp.post(tap: .cghidEventTap)
                }

                Thread.sleep(forTimeInterval: 0.2)
                print("Successfully reverted to LaTeX")
            } else {
                print("Could not extract LaTeX from clipboard - no SVG metadata found")
            }

            // Restore old clipboard
            pasteboard.clearContents()
            if let oldContents = oldContents {
                pasteboard.setString(oldContents, forType: .string)
            }
        }
    }

    private func getSelectedText() async -> String {
        return await MainActor.run {
            // Use clipboard method (more reliable than Accessibility API for text selection)
            let pasteboard = NSPasteboard.general

            // Save current clipboard
            let oldChangeCount = pasteboard.changeCount
            let oldContents = pasteboard.string(forType: .string)

            print("Old clipboard contents: \(oldContents ?? "nil")")
            print("Old change count: \(oldChangeCount)")

            // DON'T clear clipboard before copying - let the app handle it
            // pasteboard.clearContents()
            print("Current change count: \(pasteboard.changeCount)")

            // Create and post Cmd+C event
            let source = CGEventSource(stateID: .combinedSessionState)

            guard let source = source else {
                print("Failed to create CGEventSource")
                return ""
            }

            // Create key events
            guard let cmdCDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
                  let cmdCUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else {
                print("Failed to create CGEvent")
                return ""
            }

            cmdCDown.flags = .maskCommand
            cmdCUp.flags = []

            // Post to HID event tap
            cmdCDown.post(tap: .cghidEventTap)
            cmdCUp.post(tap: .cghidEventTap)

            print("Posted Cmd+C event")

            // Wait for clipboard to update
            Thread.sleep(forTimeInterval: 0.3)

            print("After wait, change count: \(pasteboard.changeCount)")

            let selectedText = pasteboard.string(forType: .string) ?? ""
            print("Captured text: '\(selectedText)' (length: \(selectedText.count))")

            // Check if clipboard actually changed
            if pasteboard.changeCount > oldChangeCount {
                print("Clipboard was updated (changeCount: \(oldChangeCount) -> \(pasteboard.changeCount))")
            } else {
                print("WARNING: Clipboard may not have been updated properly")
            }

            // Restore old clipboard contents
            pasteboard.clearContents()
            if let oldContents = oldContents {
                pasteboard.setString(oldContents, forType: .string)
            }

            return selectedText
        }
    }

    private func replaceSelection(with text: String) async {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            let oldContents = pasteboard.string(forType: .string)

            print("Replacing selection with: '\(text.prefix(100))...'")

            // Set new content to clipboard
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

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

            print("Posted Cmd+V event")

            // Wait for paste to complete
            Thread.sleep(forTimeInterval: 0.2)

            // Restore old clipboard contents
            if let oldContents = oldContents {
                pasteboard.clearContents()
                pasteboard.setString(oldContents, forType: .string)
            }

            print("Selection replaced")
        }
    }

    private func replaceSelectionWithSVG(_ svgString: String) async {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            let oldContents = pasteboard.string(forType: .string)

            print("Replacing selection with SVG (vector)")

            guard let svgData = svgString.data(using: .utf8) else {
                print("Failed to convert SVG string to data")
                return
            }

            // Clear pasteboard
            pasteboard.clearContents()

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

            print("Posted Cmd+V event for SVG")

            // Wait for paste to complete
            Thread.sleep(forTimeInterval: 0.2)

            // Restore old clipboard contents
            if let oldContents = oldContents {
                pasteboard.clearContents()
                pasteboard.setString(oldContents, forType: .string)
            }

            print("SVG pasted")
        }
    }

    private func replaceSelectionWithPDFAndSVG(pdfData: Data, svgString: String) async {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            let oldContents = pasteboard.string(forType: .string)

            print("Replacing selection with PDF + SVG metadata (vector)")

            guard let svgData = svgString.data(using: .utf8) else {
                print("Failed to convert SVG to data")
                return
            }

            // Clear and set multiple data types
            pasteboard.clearContents()

            // 1. PDF for display (primary format most apps will use)
            pasteboard.setData(pdfData, forType: .pdf)

            // 2. SVG with LaTeX metadata for revert functionality
            pasteboard.setData(svgData, forType: NSPasteboard.PasteboardType("public.svg-image"))

            // 3. Also add as custom type for guaranteed retrieval
            pasteboard.setData(svgData, forType: NSPasteboard.PasteboardType("com.TeXClipper.svg"))

            print("PDF and SVG added to pasteboard")

            // Create and post Cmd+V event
            let source = CGEventSource(stateID: .hidSystemState)

            if let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) {
                cmdVDown.flags = .maskCommand
                cmdVDown.post(tap: .cghidEventTap)
            }

            if let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
                cmdVUp.post(tap: .cghidEventTap)
            }

            print("Posted Cmd+V event for PDF+SVG")

            Thread.sleep(forTimeInterval: 0.2)

            // Restore old clipboard contents
            if let oldContents = oldContents {
                pasteboard.clearContents()
                pasteboard.setString(oldContents, forType: .string)
            }

            print("PDF+SVG pasted")
        }
    }

    private func replaceSelectionWithPDF(_ pdfData: Data) async {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            let oldContents = pasteboard.string(forType: .string)

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
            Thread.sleep(forTimeInterval: 0.2)

            // Restore old clipboard contents
            if let oldContents = oldContents {
                pasteboard.clearContents()
                pasteboard.setString(oldContents, forType: .string)
            }

            print("PDF pasted")
        }
    }

    private func extractLatexFromRTFD(_ rtfdData: Data) -> String? {
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
}

