import XCTest
import PDFKit
@testable import TeXClipper

@MainActor
final class MixedContentTests: XCTestCase {
    
    var clipboardManager: ClipboardManager!
    var renderer: MathRenderer!
    
    override func setUp() async throws {
        clipboardManager = ClipboardManager()
        renderer = MathRenderer.shared
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }
    
    func testMixedContentWithPDFFallback() async throws {
        let latex1 = "x^2"
        let latex2 = "y^2"
        
        // 1. Create attachments with proper names
        let att1 = createDummyAttachment(filename: "unknown")
        let att2 = createDummyAttachment(filename: "unknown.png")
        let att3 = createDummyAttachment(filename: "unknown")
        
        let attrString = NSMutableAttributedString(string: "Start ")
        attrString.append(NSAttributedString(attachment: att1))
        attrString.append(NSAttributedString(string: " Middle "))
        attrString.append(NSAttributedString(attachment: att2))
        attrString.append(NSAttributedString(string: " End "))
        attrString.append(NSAttributedString(attachment: att3))
        
        // 2. Collect attachments manually
        var attachments: [(range: NSRange, attachment: NSTextAttachment)] = []
        attrString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attrString.length), options: []) { value, range, stop in
            if let attachment = value as? NSTextAttachment {
                attachments.append((range: range, attachment: attachment))
            }
        }
        
        // 3. Define sequences (simulating PDF extraction)
        let sequences = [latex1, latex2]
        
        // 4. Run buildResultString directly
        let (extractedString, hasChanges) = clipboardManager.buildResultString(from: attrString, attachments: attachments, pdfLatexSequences: sequences)
        
        XCTAssertTrue(hasChanges)
        let string = extractedString.string
        print("Result string: \(string)")
        
        // Verify structure
        // "Start " + latex1 + " Middle " + (attachment char) + " End " + latex2
        
        XCTAssertTrue(string.contains(latex1))
        XCTAssertTrue(string.contains(latex2))
        XCTAssertTrue(string.contains("Start"))
        XCTAssertTrue(string.contains("Middle"))
        XCTAssertTrue(string.contains("End"))
        
        // Verify Att2 is preserved (still has attachment character)
        // The attachment character is \u{FFFC}
        let attachmentChar = "\u{FFFC}"
        XCTAssertTrue(string.contains(attachmentChar))
        
        // Verify order
        guard let r1 = string.range(of: latex1),
              let r2 = string.range(of: attachmentChar),
              let r3 = string.range(of: latex2) else {
            XCTFail("Missing components")
            return
        }
        
        XCTAssertTrue(r1.upperBound < r2.lowerBound)
        XCTAssertTrue(r2.upperBound < r3.lowerBound)
    }
    
    func createDummyAttachment(filename: String) -> NSTextAttachment {
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // PNG header
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = filename
        return NSTextAttachment(fileWrapper: wrapper)
    }
    
    func createPDFWithText(_ text: String) -> Data {
        let pdfDoc = PDFDocument()
        let page = PDFPage()
        // Drawing text on PDFPage is hard without subclassing.
        // Instead, let's create a PDF from an attributed string.
        let attrStr = NSAttributedString(string: text)
        let printInfo = NSPrintInfo.shared
        let pdfData = NSMutableData()
        
        // This is complicated on macOS.
        // Let's just return dummy data and NOT use it in the test since we pass sequences manually.
        return Data()
    }
}

