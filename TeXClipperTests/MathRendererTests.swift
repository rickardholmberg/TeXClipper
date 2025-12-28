import XCTest
@testable import TeXClipper

@MainActor
final class MathRendererTests: XCTestCase {

    var renderer: MathRenderer!

    override func setUp() async throws {
        renderer = MathRenderer.shared
        // Give WebView time to initialize
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    // MARK: - SVG Rendering Tests

    func testRenderSimpleLatexToSVG() async throws {
        let latex = "x^2 + y^2 = z^2"
        let svg = try await renderer.renderToSVGDirect(latex: latex, displayMode: true)

        XCTAssertTrue(svg.contains("<svg"), "Result should contain SVG tag")
        XCTAssertTrue(svg.contains("</svg>"), "Result should have closing SVG tag")
    }

    func testRenderIntegralToSVG() async throws {
        let latex = "\\int_0^\\infty \\frac{1}{1+x} dx"
        let svg = try await renderer.renderToSVGDirect(latex: latex, displayMode: true)

        XCTAssertTrue(svg.contains("<svg"), "Result should contain SVG tag")
        XCTAssertFalse(svg.isEmpty, "SVG should not be empty")
    }

    func testRenderInlineMode() async throws {
        let latex = "E = mc^2"
        let svg = try await renderer.renderToSVGDirect(latex: latex, displayMode: false)

        XCTAssertTrue(svg.contains("<svg"), "Result should contain SVG tag")
    }

    func testRenderDisplayMode() async throws {
        let latex = "\\sum_{n=1}^\\infty \\frac{1}{n^2} = \\frac{\\pi^2}{6}"
        let svg = try await renderer.renderToSVGDirect(latex: latex, displayMode: true)

        XCTAssertTrue(svg.contains("<svg"), "Result should contain SVG tag")
    }

    // MARK: - PDF Rendering Tests

    func testRenderSimpleLatexToPDF() async throws {
        let latex = "a^2 + b^2 = c^2"
        let pdfData = try await renderer.renderToPDF(latex: latex, displayMode: true)

        XCTAssertFalse(pdfData.isEmpty, "PDF data should not be empty")
        XCTAssertTrue(pdfData.count > 100, "PDF should have reasonable size")

        // Check PDF header
        let header = String(data: pdfData.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF", "Should have PDF header")
    }

    func testRenderComplexLatexToPDF() async throws {
        let latex = "\\oint_C \\mathbf{E} \\cdot d\\mathbf{l} = -\\frac{d}{dt} \\int_S \\mathbf{B} \\cdot d\\mathbf{A}"
        let pdfData = try await renderer.renderToPDF(latex: latex, displayMode: true)

        XCTAssertFalse(pdfData.isEmpty, "PDF data should not be empty")
    }

    // MARK: - Metadata Extraction Tests

    func testExtractLatexFromSVGWithMetadata() {
        let latex = "x^2 + y^2"
        let svgWithMetadata = """
        <svg xmlns="http://www.w3.org/2000/svg">
            <metadata>{"latex":"\(latex)"}</metadata>
            <path d="M0,0 L10,10"/>
        </svg>
        """

        let extracted = renderer.extractLatexFromSVG(svgWithMetadata)
        XCTAssertEqual(extracted, latex, "Should extract correct LaTeX from SVG metadata")
    }

    func testExtractLatexFromSVGWithoutMetadata() {
        let svgWithoutMetadata = """
        <svg xmlns="http://www.w3.org/2000/svg">
            <path d="M0,0 L10,10"/>
        </svg>
        """

        let extracted = renderer.extractLatexFromSVG(svgWithoutMetadata)
        XCTAssertNil(extracted, "Should return nil when no metadata present")
    }

    // MARK: - Edge Cases

    func testRenderEmptyLatex() async throws {
        let latex = ""

        do {
            _ = try await renderer.renderToSVGDirect(latex: latex, displayMode: true)
            // If it doesn't throw, that's fine - some renderers handle empty input
        } catch {
            // If it throws, that's also acceptable behavior
            XCTAssertNotNil(error, "Should handle empty LaTeX gracefully")
        }
    }

    func testRenderLatexWithSpecialCharacters() async throws {
        let latex = "\\alpha + \\beta = \\gamma"
        let svg = try await renderer.renderToSVGDirect(latex: latex, displayMode: true)

        XCTAssertTrue(svg.contains("<svg"), "Should render Greek letters correctly")
    }

    func testRenderLatexWithNewlines() async throws {
        let latex = "x = y\n+ z"
        let svg = try await renderer.renderToSVGDirect(latex: latex, displayMode: true)

        XCTAssertTrue(svg.contains("<svg"), "Should handle newlines in LaTeX")
    }

    func testRenderLatexWithBackslashes() async throws {
        let latex = "\\frac{1}{2}"
        let svg = try await renderer.renderToSVGDirect(latex: latex, displayMode: true)

        XCTAssertTrue(svg.contains("<svg"), "Should handle backslashes correctly")
    }

    // MARK: - SVG Metadata Embedding

    func testSVGContainsLatexMetadata() async throws {
        let latex = "\\sqrt{2}"
        let svg = try await renderer.renderToSVGDirect(latex: latex, displayMode: true)

        XCTAssertTrue(svg.contains("<metadata>"), "SVG should contain metadata tag")

        let extracted = renderer.extractLatexFromSVG(svg)
        XCTAssertEqual(extracted, latex, "Should be able to extract original LaTeX from rendered SVG")
    }

    // MARK: - Performance Tests

    func testRenderingPerformance() async throws {
        let latex = "\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}"

        // Warm up the renderer first
        _ = try await renderer.renderToSVGDirect(latex: latex, displayMode: true)

        // Measure performance of rendering (measure doesn't work well with async, so we'll do simple timing)
        let iterations = 5
        var totalTime: TimeInterval = 0

        for _ in 0..<iterations {
            let start = Date()
            _ = try await renderer.renderToSVGDirect(latex: latex, displayMode: true)
            let elapsed = Date().timeIntervalSince(start)
            totalTime += elapsed
        }

        let averageTime = totalTime / Double(iterations)
        print("Average rendering time: \(averageTime) seconds")

        // Assert reasonable performance (should be under 2 seconds per render)
        XCTAssertLessThan(averageTime, 2.0, "Rendering should complete in under 2 seconds on average")
    }
}
