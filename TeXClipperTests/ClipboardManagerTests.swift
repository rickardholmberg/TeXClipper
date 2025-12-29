import XCTest
import AppKit
import PDFKit
@testable import TeXClipper

@MainActor
final class ClipboardManagerTests: XCTestCase {

    var clipboardManager: ClipboardManager!
    var renderer: MathRenderer!

    override func setUp() async throws {
        clipboardManager = ClipboardManager()
        renderer = MathRenderer.shared
        // Give WebView time to initialize
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    override func tearDown() {
        // Clear clipboard after each test
        NSPasteboard.general.clearContents()
    }

    // MARK: - PDF Data Tests

    func testPDFDataContainsValidPDF() async throws {
        let latex = "x^2 + y^2 = z^2"
        let pdfData = try await renderer.renderToPDF(latex: latex, displayMode: true)

        // Verify it's valid PDF data
        let header = String(data: pdfData.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF", "Should have valid PDF header")

        // Verify we can create a PDFDocument from it
        let pdfDocument = PDFDocument(data: pdfData)
        XCTAssertNotNil(pdfDocument, "Should be able to create PDFDocument from data")
        XCTAssertGreaterThan(pdfDocument!.pageCount, 0, "PDF should have at least one page")
    }

    func testPDFContainsLatexAnnotation() async throws {
        let latex = "\\int_0^\\infty e^{-x^2} dx"
        let pdfData = try await renderer.renderToPDF(latex: latex, displayMode: true)

        guard let pdfDocument = PDFDocument(data: pdfData),
              let firstPage = pdfDocument.page(at: 0) else {
            XCTFail("Failed to create PDF document")
            return
        }

        let annotations = firstPage.annotations
        XCTAssertGreaterThan(annotations.count, 0, "PDF should have annotations")

        // Look for our LaTeX annotation
        let latexAnnotations = annotations.filter { annotation in
            annotation.contents?.hasPrefix("TeXClipper:") ?? false
        }

        XCTAssertGreaterThan(latexAnnotations.count, 0, "Should have TeXClipper annotation")

        if let annotation = latexAnnotations.first,
           let contents = annotation.contents {
            let extractedLatex = contents.replacingOccurrences(of: "TeXClipper:", with: "")
            XCTAssertEqual(extractedLatex, latex, "Should preserve original LaTeX in annotation")
        }
    }

    // MARK: - SVG Metadata Tests

    func testSVGContainsMetadata() async throws {
        let latex = "E = mc^2"
        let svg = try await renderer.renderToSVGDirect(latex: latex, displayMode: true)

        XCTAssertTrue(svg.contains("<metadata>"), "SVG should contain metadata tag")

        let extracted = renderer.extractLatexFromSVG(svg)
        XCTAssertEqual(extracted, latex, "Should extract correct LaTeX from metadata")
    }

    // MARK: - LaTeX Extraction Tests

    func testExtractLatexFromPDF() async throws {
        let originalLatex = "\\sum_{n=1}^\\infty \\frac{1}{n^2}"
        let pdfData = try await renderer.renderToPDF(latex: originalLatex, displayMode: true)

        guard let pdfDocument = PDFDocument(data: pdfData),
              let firstPage = pdfDocument.page(at: 0) else {
            XCTFail("Failed to create PDF document")
            return
        }

        // Find the annotation
        let annotations = firstPage.annotations
        let latexAnnotations = annotations.filter { annotation in
            annotation.contents?.hasPrefix("TeXClipper:") ?? false
        }

        XCTAssertGreaterThan(latexAnnotations.count, 0, "Should have TeXClipper annotation")

        if let annotation = latexAnnotations.first,
           let contents = annotation.contents {
            let extractedLatex = contents.replacingOccurrences(of: "TeXClipper:", with: "")
            XCTAssertEqual(extractedLatex, originalLatex, "Extracted LaTeX should match original")
        }
    }

    // MARK: - Edge Cases

    func testRenderLatexWithSpecialCharacters() async throws {
        let latex = "x'\\prime + y\"\\dprime"
        let pdfData = try await renderer.renderToPDF(latex: latex, displayMode: true)

        guard let pdfDocument = PDFDocument(data: pdfData),
              let firstPage = pdfDocument.page(at: 0) else {
            XCTFail("Failed to create PDF document")
            return
        }

        let annotations = firstPage.annotations
        let latexAnnotations = annotations.filter { annotation in
            annotation.contents?.hasPrefix("TeXClipper:") ?? false
        }

        if let annotation = latexAnnotations.first,
           let contents = annotation.contents {
            let extractedLatex = contents.replacingOccurrences(of: "TeXClipper:", with: "")
            XCTAssertEqual(extractedLatex, latex, "Should preserve quotes and special characters")
        }
    }

    func testRenderComplexLatex() async throws {
        let latex = """
        \\begin{align}
        \\nabla \\times \\mathbf{E} &= -\\frac{\\partial \\mathbf{B}}{\\partial t} \\\\
        \\nabla \\times \\mathbf{B} &= \\mu_0 \\mathbf{J} + \\mu_0 \\epsilon_0 \\frac{\\partial \\mathbf{E}}{\\partial t}
        \\end{align}
        """

        let pdfData = try await renderer.renderToPDF(latex: latex, displayMode: true)

        XCTAssertFalse(pdfData.isEmpty, "Should render complex LaTeX")

        guard let pdfDocument = PDFDocument(data: pdfData) else {
            XCTFail("Failed to create PDF document")
            return
        }

        XCTAssertGreaterThan(pdfDocument.pageCount, 0, "PDF should have pages")
    }

    // MARK: - NSImage Extension Tests

    func testPNGRepresentation() {
        // Create a simple test image
        let size = NSSize(width: 100, height: 100)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let pngData = image.pngRepresentation
        XCTAssertNotNil(pngData, "Should generate PNG data")

        if let pngData = pngData {
            XCTAssertGreaterThan(pngData.count, 0, "PNG data should not be empty")

            // Verify it's valid PNG data
            let header = pngData.prefix(8)
            let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            XCTAssertEqual(Array(header), pngHeader, "Should have valid PNG header")
        }
    }

    // MARK: - Integration Tests

    func testRoundTripLatexToPDFAndBack() async throws {
        let originalLatex = "\\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}"

        // Render to PDF
        let pdfData = try await renderer.renderToPDF(latex: originalLatex, displayMode: true)

        // Extract LaTeX from PDF
        guard let pdfDocument = PDFDocument(data: pdfData),
              let firstPage = pdfDocument.page(at: 0) else {
            XCTFail("Failed to create PDF document")
            return
        }

        let annotations = firstPage.annotations
        let latexAnnotations = annotations.filter { annotation in
            annotation.contents?.hasPrefix("TeXClipper:") ?? false
        }

        XCTAssertGreaterThan(latexAnnotations.count, 0, "Should have annotation")

        if let annotation = latexAnnotations.first,
           let contents = annotation.contents {
            let extractedLatex = contents.replacingOccurrences(of: "TeXClipper:", with: "")
            XCTAssertEqual(extractedLatex, originalLatex, "Round-trip should preserve LaTeX exactly")
        }
    }

    func testRoundTripLatexToSVGAndBack() async throws {
        let originalLatex = "\\sqrt{a^2 + b^2}"

        // Render to SVG
        let svg = try await renderer.renderToSVGDirect(latex: originalLatex, displayMode: true)

        // Extract LaTeX from SVG
        let extractedLatex = renderer.extractLatexFromSVG(svg)

        XCTAssertNotNil(extractedLatex, "Should extract LaTeX from SVG")
        XCTAssertEqual(extractedLatex, originalLatex, "Round-trip should preserve LaTeX exactly")
    }

    // MARK: - Multiple Image Revert Tests

    func testMultipleImagesWithNonLatexImageContents() async throws {
        // This test replicates the bug using attachment.contents instead of fileWrapper
        // Some apps might paste images without file wrappers

        let firstLatex = "x^2 + y^2 = z^2"
        let secondLatex = "\\int_0^\\infty e^{-x} dx"

        // Render both LaTeX expressions to PDF
        let firstPDF = try await renderer.renderToPDF(latex: firstLatex, displayMode: true)
        let secondPDF = try await renderer.renderToPDF(latex: secondLatex, displayMode: true)

        // Create a non-LaTeX image (simple red square "duck")
        let duckSize = NSSize(width: 100, height: 100)
        let duckImage = NSImage(size: duckSize)
        duckImage.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: duckSize).fill()
        duckImage.unlockFocus()

        // Convert duck to PNG data
        guard let duckPNG = duckImage.pngRepresentation else {
            XCTFail("Failed to create duck PNG")
            return
        }

        // Build an attributed string with multiple attachments:
        // [LaTeX PDF] [Duck PNG via contents] [Text] [LaTeX PDF]
        let attributedString = NSMutableAttributedString()

        // Add first LaTeX attachment
        let firstAttachment = NSTextAttachment()
        let firstWrapper = FileWrapper(regularFileWithContents: firstPDF)
        firstWrapper.preferredFilename = "math1.pdf"
        firstAttachment.fileWrapper = firstWrapper
        attributedString.append(NSAttributedString(attachment: firstAttachment))

        // Add duck attachment using contents instead of fileWrapper
        // Note: RTFD format requires fileWrapper for proper serialization
        // But we want to test the case where contents is used (as some apps might do this)
        let duckAttachment = NSTextAttachment()
        duckAttachment.contents = duckPNG
        // Also set fileWrapper so it serializes to RTFD properly
        let duckWrapper = FileWrapper(regularFileWithContents: duckPNG)
        duckWrapper.preferredFilename = "duck.png"
        duckAttachment.fileWrapper = duckWrapper
        attributedString.append(NSAttributedString(attachment: duckAttachment))

        // Add some text
        attributedString.append(NSAttributedString(string: " some text "))

        // Add second LaTeX attachment
        let secondAttachment = NSTextAttachment()
        let secondWrapper = FileWrapper(regularFileWithContents: secondPDF)
        secondWrapper.preferredFilename = "math2.pdf"
        secondAttachment.fileWrapper = secondWrapper
        attributedString.append(NSAttributedString(attachment: secondAttachment))

        // Convert to RTFD data
        guard let rtfdData = try? attributedString.data(from: NSRange(location: 0, length: attributedString.length),
                                                        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) else {
            XCTFail("Failed to create RTFD data")
            return
        }

        // Extract all LaTeX from the RTFD
        guard let resultAttributedString = clipboardManager.extractAllLatexFromRTFD(rtfdData) else {
            XCTFail("Failed to extract LaTeX from RTFD")
            return
        }

        let result = resultAttributedString.string

        // Debug: Print detailed result info
        print("=== RESULT ANALYSIS ===")
        print("Result: \(result)")
        print("Result length: \(result.count)")
        print("First LaTeX (\(firstLatex)): contains = \(result.contains(firstLatex))")
        print("Second LaTeX (\(secondLatex)): contains = \(result.contains(secondLatex))")
        print("Text ' some text ': contains = \(result.contains(" some text "))")

        let objectReplacementChar = "\u{FFFC}"
        let duckCount = result.components(separatedBy: objectReplacementChar).count - 1
        let firstLatexCount = result.components(separatedBy: firstLatex).count - 1

        print("Object replacement character count: \(duckCount)")
        print("First LaTeX occurrence count: \(firstLatexCount)")

        // Check if the duck attachment is preserved in the attributed string
        var hasNonLatexAttachment = false
        resultAttributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: resultAttributedString.length), options: []) { value, range, stop in
            if let _ = value as? NSTextAttachment {
                hasNonLatexAttachment = true
                print("Found preserved attachment at range \(range)")
            }
        }
        print("Has non-LaTeX attachment preserved: \(hasNonLatexAttachment)")
        print("=== END ANALYSIS ===")

        // The result should contain both LaTeX expressions
        XCTAssertTrue(result.contains(firstLatex), "Should contain first LaTeX: \(firstLatex). Result: \(result)")
        XCTAssertTrue(result.contains(secondLatex), "Should contain second LaTeX: \(secondLatex). Result: \(result)")
        XCTAssertTrue(result.contains(" some text "), "Should preserve text between images. Result: \(result)")

        // The duck should be preserved as an attachment (U+FFFC in the string)
        XCTAssertEqual(duckCount, 1, "Should have exactly one object replacement character for the duck image. Found \(duckCount). Result: \(result)")
        XCTAssertTrue(hasNonLatexAttachment, "Should preserve the non-LaTeX attachment in the attributed string")

        // The first LaTeX should NOT appear twice (bug check)
        XCTAssertEqual(firstLatexCount, 1, "First LaTeX should appear exactly once, not replace the duck image. Found \(firstLatexCount) times. Result: \(result)")
    }

    func testMultipleImagesWithNonLatexImage() async throws {
        // This test replicates the bug where:
        // - Document has: [LaTeX image, Duck image, text, LaTeX image]
        // - Reverting should convert LaTeX images to source but preserve duck image
        // - Bug: Duck image gets replaced with first LaTeX image's source

        let firstLatex = "x^2 + y^2 = z^2"
        let secondLatex = "\\int_0^\\infty e^{-x} dx"

        // Render both LaTeX expressions to PDF
        let firstPDF = try await renderer.renderToPDF(latex: firstLatex, displayMode: true)
        let secondPDF = try await renderer.renderToPDF(latex: secondLatex, displayMode: true)

        // Create a non-LaTeX image (simple red square "duck")
        let duckSize = NSSize(width: 100, height: 100)
        let duckImage = NSImage(size: duckSize)
        duckImage.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: duckSize).fill()
        duckImage.unlockFocus()

        // Convert duck to PNG data
        guard let duckPNG = duckImage.pngRepresentation else {
            XCTFail("Failed to create duck PNG")
            return
        }

        // Build an attributed string with multiple attachments:
        // [LaTeX PDF] [Duck PNG] [Text] [LaTeX PDF]
        let attributedString = NSMutableAttributedString()

        // Add first LaTeX attachment
        let firstAttachment = NSTextAttachment()
        let firstWrapper = FileWrapper(regularFileWithContents: firstPDF)
        firstWrapper.preferredFilename = "math1.pdf"
        firstAttachment.fileWrapper = firstWrapper
        attributedString.append(NSAttributedString(attachment: firstAttachment))

        // Add duck attachment (non-LaTeX image)
        let duckAttachment = NSTextAttachment()
        let duckWrapper = FileWrapper(regularFileWithContents: duckPNG)
        duckWrapper.preferredFilename = "duck.png"
        duckAttachment.fileWrapper = duckWrapper
        attributedString.append(NSAttributedString(attachment: duckAttachment))

        // Add some text
        attributedString.append(NSAttributedString(string: " some text "))

        // Add second LaTeX attachment
        let secondAttachment = NSTextAttachment()
        let secondWrapper = FileWrapper(regularFileWithContents: secondPDF)
        secondWrapper.preferredFilename = "math2.pdf"
        secondAttachment.fileWrapper = secondWrapper
        attributedString.append(NSAttributedString(attachment: secondAttachment))

        // Convert to RTFD data
        guard let rtfdData = try? attributedString.data(from: NSRange(location: 0, length: attributedString.length),
                                                        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) else {
            XCTFail("Failed to create RTFD data")
            return
        }

        // Extract all LaTeX from the RTFD
        // This should:
        // 1. Replace first attachment with "x^2 + y^2 = z^2"
        // 2. Preserve duck image as object replacement character (U+FFFC) with attachment
        // 3. Preserve text " some text "
        // 4. Replace second attachment with "\\int_0^\\infty e^{-x} dx"
        guard let resultAttributedString = clipboardManager.extractAllLatexFromRTFD(rtfdData) else {
            XCTFail("Failed to extract LaTeX from RTFD")
            return
        }

        let result = resultAttributedString.string

        print("Result from extractAllLatexFromRTFD: \(result)")
        print("Result bytes: \(Array(result.utf8))")
        print("Result characters:")
        for (index, char) in result.enumerated() {
            print("  [\(index)]: '\(char)' (U+\(String(format: "%04X", char.unicodeScalars.first?.value ?? 0)))")
        }

        // The result should contain:
        // - First LaTeX source
        // - Object replacement character for duck (U+FFFC)
        // - The text
        // - Second LaTeX source
        XCTAssertTrue(result.contains(firstLatex), "Should contain first LaTeX: \(firstLatex)")
        XCTAssertTrue(result.contains(secondLatex), "Should contain second LaTeX: \(secondLatex)")
        XCTAssertTrue(result.contains(" some text "), "Should preserve text between images")

        // The duck should be represented as object replacement character (U+FFFC)
        let objectReplacementChar = "\u{FFFC}"
        let duckCount = result.components(separatedBy: objectReplacementChar).count - 1
        XCTAssertEqual(duckCount, 1, "Should have exactly one object replacement character for the duck image")

        // Check that the duck attachment is actually preserved
        var hasNonLatexAttachment = false
        resultAttributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: resultAttributedString.length), options: []) { value, range, stop in
            if let _ = value as? NSTextAttachment {
                hasNonLatexAttachment = true
            }
        }
        XCTAssertTrue(hasNonLatexAttachment, "Should preserve the duck image attachment")

        // The first LaTeX should NOT appear twice (bug check)
        let firstLatexCount = result.components(separatedBy: firstLatex).count - 1
        XCTAssertEqual(firstLatexCount, 1, "First LaTeX should appear exactly once, not replace the duck image")

        // Check exact structure: firstLatex + ORC + text + secondLatex
        let expected = firstLatex + objectReplacementChar + " some text " + secondLatex
        XCTAssertEqual(result, expected, "Result should match exact expected structure")
    }
}
