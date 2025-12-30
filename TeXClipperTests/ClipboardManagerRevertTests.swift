import XCTest
import AppKit
@testable import TeXClipper

@MainActor
final class ClipboardManagerRevertTests: XCTestCase {
    
    var clipboardManager: ClipboardManager!
    var renderer: MathRenderer!
    
    override func setUp() async throws {
        clipboardManager = ClipboardManager()
        renderer = MathRenderer.shared
        // Give WebView time to initialize
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }
    
    func testExtractAllLatexFromRTFD_WithSVGAttachment() {
        let latex = "x^2"
        let svg = """
        <svg><metadata>{"latex":"\(latex)"}</metadata></svg>
        """
        let svgData = svg.data(using: .utf8)!
        
        let fileWrapper = FileWrapper(regularFileWithContents: svgData)
        fileWrapper.preferredFilename = "equation.svg"
        
        let attachment = NSTextAttachment(fileWrapper: fileWrapper)
        let attrString = NSMutableAttributedString(string: "Equation: ")
        attrString.append(NSAttributedString(attachment: attachment))
        attrString.append(NSAttributedString(string: " end."))
        
        guard let rtfdData = try? attrString.data(from: NSRange(location: 0, length: attrString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) else {
            XCTFail("Failed to create RTFD data")
            return
        }
        
        let result = clipboardManager.extractAllLatexFromRTFD(rtfdData)
        
        XCTAssertNotNil(result)
        if let (extractedString, hasChanges) = result {
            XCTAssertTrue(hasChanges)
            XCTAssertEqual(extractedString.string, "Equation: \(latex) end.")
        }
    }
    
    func testExtractAllLatexFromRTFD_TwoSVGs() {
        let latex1 = "a"
        let svg1 = """
        <svg><metadata>{"latex":"\(latex1)"}</metadata></svg>
        """
        let wrapper1 = FileWrapper(regularFileWithContents: svg1.data(using: .utf8)!)
        wrapper1.preferredFilename = "eq1.svg"
        let att1 = NSTextAttachment(fileWrapper: wrapper1)
        
        let latex2 = "b"
        let svg2 = """
        <svg><metadata>{"latex":"\(latex2)"}</metadata></svg>
        """
        let wrapper2 = FileWrapper(regularFileWithContents: svg2.data(using: .utf8)!)
        wrapper2.preferredFilename = "eq2.svg"
        let att2 = NSTextAttachment(fileWrapper: wrapper2)
        
        let attrString = NSMutableAttributedString(string: "1: ")
        attrString.append(NSAttributedString(attachment: att1))
        attrString.append(NSAttributedString(string: " 2: "))
        attrString.append(NSAttributedString(attachment: att2))
        
        guard let rtfdData = try? attrString.data(from: NSRange(location: 0, length: attrString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) else {
            XCTFail("Failed to create RTFD data")
            return
        }
        
        let result = clipboardManager.extractAllLatexFromRTFD(rtfdData)
        
        XCTAssertNotNil(result)
        if let (extractedString, hasChanges) = result {
            XCTAssertTrue(hasChanges)
            XCTAssertEqual(extractedString.string, "1: \(latex1) 2: \(latex2)")
        }
    }
}
