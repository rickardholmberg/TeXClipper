import XCTest
import PDFKit
@testable import TeXClipper

@MainActor
final class PDFMetadataTests: XCTestCase {
    
    var clipboardManager: ClipboardManager!
    
    override func setUp() {
        clipboardManager = ClipboardManager()
    }
    
    func testExtractLatexFromSubject() {
        let latex = "x^2 + y^2"
        let pdfData = createPDFWithMetadata(subject: "TeXClipper:\(latex)", keywords: nil)
        
        // Create RTFD with this PDF
        let rtfdData = createRTFDWithAttachment(data: pdfData, type: "com.adobe.pdf", filename: "test.pdf")
        
        let result = clipboardManager.extractAllLatexFromRTFD(rtfdData)
        
        XCTAssertNotNil(result)
        if let (extractedString, hasChanges) = result {
            XCTAssertTrue(hasChanges)
            // The RTFD creation adds a space or attachment char.
            // Our createRTFDWithAttachment creates an attributed string with just the attachment.
            // extractAllLatexFromRTFD should replace the attachment with the latex.
            XCTAssertEqual(extractedString.string, latex)
        }
    }
    
    func testExtractLatexFromKeywordsString() {
        let latex = "\\int e^x dx"
        let pdfData = createPDFWithMetadata(subject: nil, keywords: ["TeXClipper:\(latex)"])
        
        // Note: PDFDocumentAttribute.keywordsAttribute expects [String], but we handle String too in ClipboardManager.
        // But createPDFWithMetadata sets it as [String].
        // Let's verify if ClipboardManager handles [String] correctly.
        
        let rtfdData = createRTFDWithAttachment(data: pdfData, type: "com.adobe.pdf", filename: "test.pdf")
        
        let result = clipboardManager.extractAllLatexFromRTFD(rtfdData)
        
        XCTAssertNotNil(result)
        if let (extractedString, hasChanges) = result {
            XCTAssertTrue(hasChanges)
            XCTAssertEqual(extractedString.string, latex)
        }
    }
    
    func createPDFWithMetadata(subject: String?, keywords: [String]?) -> Data {
        let pdfPage = PDFPage()
        let pdfDoc = PDFDocument()
        pdfDoc.insert(pdfPage, at: 0)
        
        var attributes = pdfDoc.documentAttributes ?? [:]
        if let subject = subject {
            attributes[PDFDocumentAttribute.subjectAttribute] = subject
        }
        if let keywords = keywords {
            attributes[PDFDocumentAttribute.keywordsAttribute] = keywords
        }
        pdfDoc.documentAttributes = attributes
        return pdfDoc.dataRepresentation()!
    }
    
    func createRTFDWithAttachment(data: Data, type: String, filename: String) -> Data {
        let attachment = NSTextAttachment(data: data, ofType: type)
        attachment.fileWrapper?.filename = filename
        let attrString = NSAttributedString(attachment: attachment)
        return try! attrString.data(from: NSRange(location: 0, length: attrString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
    }
}
