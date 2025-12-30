import XCTest
import PDFKit
@testable import TeXClipper

@MainActor
final class PDFHiddenTextTests: XCTestCase {
    
    var clipboardManager: ClipboardManager!
    var renderer: MathRenderer!
    
    override func setUp() async throws {
        clipboardManager = ClipboardManager()
        renderer = MathRenderer.shared
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }
    
    func testExtractLatexFromHiddenText() async throws {
        let latex = "x^2 + y^2 = z^2"
        // Render to PDF which should now include the hidden text
        let pdfData = try await renderer.renderToPDF(latex: latex, displayMode: true)
        
        // Verify PDF contains the text
        guard let pdfDocument = PDFDocument(data: pdfData),
              let page = pdfDocument.page(at: 0) else {
            XCTFail("Failed to create PDF document")
            return
        }
        
        let text = page.string ?? ""
        print("Extracted PDF Text: '\(text)'")
        XCTAssertTrue(text.contains("TeXClipperStart:"), "PDF should contain hidden text marker")
        XCTAssertTrue(text.contains(latex), "PDF should contain latex source")
        
        // Now test extraction via ClipboardManager
        // We need to access extractLatexFromPDF which is internal/private.
        // But we can use extractAllLatexFromRTFD if we wrap it in RTFD.
        
        let attachment = NSTextAttachment(data: pdfData, ofType: "com.adobe.pdf")
        attachment.fileWrapper?.filename = "equation.pdf"
        let attrString = NSAttributedString(attachment: attachment)
        let rtfdData = try! attrString.data(from: NSRange(location: 0, length: attrString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        
        let result = clipboardManager.extractAllLatexFromRTFD(rtfdData)
        
        XCTAssertNotNil(result)
        if let (extractedString, hasChanges) = result {
            XCTAssertTrue(hasChanges)
            XCTAssertEqual(extractedString.string, latex)
        }
    }
}
