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
}
