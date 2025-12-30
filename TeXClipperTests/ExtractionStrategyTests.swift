import XCTest
import AppKit
@testable import TeXClipper

@MainActor
final class ExtractionStrategyTests: XCTestCase {
    
    var renderer: MathRenderer!
    var pasteboard: NSPasteboard!
    
    override func setUp() {
        super.setUp()
        renderer = MathRenderer.shared
        // Use a unique pasteboard for each test to avoid interference
        pasteboard = NSPasteboard.withUniqueName()
    }
    
    override func tearDown() {
        pasteboard = nil
        super.tearDown()
    }
    
    // Mock PDF extractor that just returns the string "EXTRACTED_PDF_LATEX"
    // if the data is valid, to verify the strategy calls it.
    let mockPDFExtractor: (Data) -> String? = { data in
        if let str = String(data: data, encoding: .utf8), str == "VALID_PDF" {
            return "EXTRACTED_PDF_LATEX"
        }
        return nil
    }
    
    private func createSVG(latex: String) -> String {
        let metadata = ["latex": latex]
        let jsonData = try! JSONEncoder().encode(metadata)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        return """
        <svg><metadata>\(jsonString)</metadata></svg>
        """
    }
    
    func testCustomSVGExtractionStrategy() {
        let strategy = CustomSVGExtractionStrategy()
        let latex = "x^2"
        let svg = createSVG(latex: latex)
        
        // 1. Test with valid data
        pasteboard.clearContents()
        pasteboard.setData(svg.data(using: .utf8)!, forType: NSPasteboard.PasteboardType("com.TeXClipper.svg"))
        
        let result = strategy.extract(from: pasteboard, renderer: renderer, pdfExtractor: mockPDFExtractor)
        XCTAssertEqual(result, latex)
        
        // 2. Test with missing data
        pasteboard.clearContents()
        let nilResult = strategy.extract(from: pasteboard, renderer: renderer, pdfExtractor: mockPDFExtractor)
        XCTAssertNil(nilResult)
        
        // 3. Test with invalid SVG (no metadata)
        pasteboard.clearContents()
        pasteboard.setData("<svg></svg>".data(using: .utf8)!, forType: NSPasteboard.PasteboardType("com.TeXClipper.svg"))
        let invalidResult = strategy.extract(from: pasteboard, renderer: renderer, pdfExtractor: mockPDFExtractor)
        XCTAssertNil(invalidResult)
    }
    
    func testPublicSVGExtractionStrategy() {
        let strategy = PublicSVGExtractionStrategy()
        let latex = "\\alpha"
        let svg = createSVG(latex: latex)
        
        // 1. Test with valid data
        pasteboard.clearContents()
        pasteboard.setData(svg.data(using: .utf8)!, forType: NSPasteboard.PasteboardType("public.svg-image"))
        
        let result = strategy.extract(from: pasteboard, renderer: renderer, pdfExtractor: mockPDFExtractor)
        XCTAssertEqual(result, latex)
        
        // 2. Test with missing data
        pasteboard.clearContents()
        let nilResult = strategy.extract(from: pasteboard, renderer: renderer, pdfExtractor: mockPDFExtractor)
        XCTAssertNil(nilResult)
    }
    
    func testTextSVGExtractionStrategy() {
        let strategy = TextSVGExtractionStrategy()
        let latex = "\\beta"
        let svg = createSVG(latex: latex)
        
        // 1. Test with valid text containing SVG
        pasteboard.clearContents()
        pasteboard.setString(svg, forType: .string)
        
        let result = strategy.extract(from: pasteboard, renderer: renderer, pdfExtractor: mockPDFExtractor)
        XCTAssertEqual(result, latex)
        
        // 2. Test with plain text (no SVG)
        pasteboard.clearContents()
        pasteboard.setString("Just some text", forType: .string)
        let nilResult = strategy.extract(from: pasteboard, renderer: renderer, pdfExtractor: mockPDFExtractor)
        XCTAssertNil(nilResult)
    }
    
    func testPDFExtractionStrategy() {
        let strategy = PDFExtractionStrategy()
        
        // 1. Test with valid PDF data (mocked)
        pasteboard.clearContents()
        pasteboard.setData("VALID_PDF".data(using: .utf8)!, forType: .pdf)
        
        let result = strategy.extract(from: pasteboard, renderer: renderer, pdfExtractor: mockPDFExtractor)
        XCTAssertEqual(result, "EXTRACTED_PDF_LATEX")
        
        // 2. Test with invalid PDF data
        pasteboard.clearContents()
        pasteboard.setData("INVALID_PDF".data(using: .utf8)!, forType: .pdf)
        
        let invalidResult = strategy.extract(from: pasteboard, renderer: renderer, pdfExtractor: mockPDFExtractor)
        XCTAssertNil(invalidResult)
        
        // 3. Test with missing data
        pasteboard.clearContents()
        let nilResult = strategy.extract(from: pasteboard, renderer: renderer, pdfExtractor: mockPDFExtractor)
        XCTAssertNil(nilResult)
    }
    
    func testRTFDExtractionStrategy() {
        let strategy = RTFDExtractionStrategy()
        
        // RTFD strategy should always return nil as it's handled separately
        pasteboard.clearContents()
        let result = strategy.extract(from: pasteboard, renderer: renderer, pdfExtractor: mockPDFExtractor)
        XCTAssertNil(result)
    }
}
