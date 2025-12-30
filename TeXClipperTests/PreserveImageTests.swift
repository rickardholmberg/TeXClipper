import XCTest
import AppKit
import PDFKit
@testable import TeXClipper

@MainActor
final class PreserveImageTests: XCTestCase {
    
    var clipboardManager: ClipboardManager!
    
    override func setUp() {
        clipboardManager = ClipboardManager()
    }
    
    func testPreserveNonTexImage() {
        // 1. Create a PNG attachment (simulating a non-TeX image)
        // Minimal PNG data
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) 
        let pngAttachment = NSTextAttachment(data: pngData, ofType: "public.png")
        // Ensure it has a file wrapper as that's what we expect from RTFD
        if pngAttachment.fileWrapper == nil {
            let wrapper = FileWrapper(regularFileWithContents: pngData)
            wrapper.preferredFilename = "image.png"
            pngAttachment.fileWrapper = wrapper
        }
        
        // 2. Create a TeX attachment (simulating a TeX image)
        // We'll use a mock PDF that contains "TeXClipper:x^2" in text
        let pdfData = createMockPDF(text: "TeXClipper:x^2")
        let pdfAttachment = NSTextAttachment(data: pdfData, ofType: "com.adobe.pdf")
        if pdfAttachment.fileWrapper == nil {
            let wrapper = FileWrapper(regularFileWithContents: pdfData)
            wrapper.preferredFilename = "equation.pdf"
            pdfAttachment.fileWrapper = wrapper
        }
        
        // 3. Create Attributed String with both
        let attrString = NSMutableAttributedString(string: "Start ")
        attrString.append(NSAttributedString(attachment: pngAttachment))
        attrString.append(NSAttributedString(string: " Middle "))
        attrString.append(NSAttributedString(attachment: pdfAttachment))
        attrString.append(NSAttributedString(string: " End"))
        
        // 4. Convert to RTFD Data
        guard let rtfdData = try? attrString.data(from: NSRange(location: 0, length: attrString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) else {
            XCTFail("Failed to create RTFD data")
            return
        }
        
        // 5. Run extraction
        let result = clipboardManager.extractAllLatexFromRTFD(rtfdData)
        
        // 6. Verify result
        XCTAssertNotNil(result)
        if let (resultString, hasChanges) = result {
            XCTAssertTrue(hasChanges)
            
            // Check content
            let string = resultString.string
            // Expected: "Start ￼ Middle x^2 End" (where ￼ is the object replacement char)
            // Note: The attachment is replaced by object replacement char in .string property
            
            print("Result string: \(string)")
            
            // Verify the PNG attachment is still there
            var foundPNG = false
            resultString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: resultString.length), options: []) { value, range, stop in
                if let attachment = value as? NSTextAttachment {
                    if let wrapper = attachment.fileWrapper {
                        print("Found attachment: \(wrapper.preferredFilename ?? "nil")")
                        if wrapper.preferredFilename == "image.png" || wrapper.preferredFilename == "Attachment.png" {
                            foundPNG = true
                        }
                    }
                }
            }
            XCTAssertTrue(foundPNG, "PNG attachment should be preserved")
            
            // Verify the PDF attachment is GONE (replaced by text)
            var foundPDF = false
            resultString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: resultString.length), options: []) { value, range, stop in
                if let attachment = value as? NSTextAttachment {
                    if let wrapper = attachment.fileWrapper {
                        if wrapper.preferredFilename == "equation.pdf" {
                            foundPDF = true
                        }
                    }
                }
            }
            XCTAssertFalse(foundPDF, "PDF attachment should be replaced")
            
            // 7. Verify we can convert back to RTFD and the PNG data is preserved
            if let newRTFD = try? resultString.data(from: NSRange(location: 0, length: resultString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) {
                // Load it back
                if let reloadedString = try? NSAttributedString(data: newRTFD, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil) {
                    var reloadedPNG = false
                    reloadedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: reloadedString.length), options: []) { value, range, stop in
                        if let attachment = value as? NSTextAttachment {
                            if let wrapper = attachment.fileWrapper {
                                // Check data size
                                if let data = wrapper.regularFileContents, data.count == pngData.count {
                                    reloadedPNG = true
                                }
                            }
                        }
                    }
                    XCTAssertTrue(reloadedPNG, "PNG attachment should be preserved in generated RTFD")
                } else {
                    XCTFail("Failed to reload generated RTFD")
                }
            } else {
                XCTFail("Failed to generate RTFD from result")
            }
        }
    }
    
    func createMockPDF(text: String) -> Data {
        // Create a simple PDF with the text
        let pdfData = NSMutableData()
        let consumer = CGDataConsumer(data: pdfData as CFMutableData)!
        var rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let context = CGContext(consumer: consumer, mediaBox: &rect, nil)!
        
        context.beginPDFPage(nil)
        // We don't actually need to draw text for the ClipboardManager to find it, 
        // because ClipboardManager uses PDFPage.string which relies on PDFKit parsing.
        // But creating a real PDF with text using CoreGraphics is verbose.
        // Instead, we can rely on the fact that ClipboardManager.extractLatexFromPDF checks page.string.
        // But wait, PDFPage.string comes from the PDF content stream.
        // If I just draw text, it should work.
        
        // Actually, let's use PDFKit to create it if possible, or just mock the extraction strategy?
        // No, I can't mock the internal PDFDocument behavior easily.
        
        // Let's try to create a PDF with PDFKit (Annotation) since that's easier?
        // But the new strategy checks `page.string`.
        
        // Let's just use the existing PDF creation from MathRenderer if possible?
        // Or just assume the extraction works (since we tested it) and focus on the preservation logic.
        // I can mock the extraction by swizzling or just by using a PDF that I know works.
        // Or I can subclass ClipboardManager? No.
        
        // Let's just use a dummy PDF and rely on the fact that I want to test PRESERVATION of the OTHER image.
        // So I don't strictly need the PDF extraction to succeed for the PDF part, 
        // I just need `extractAllLatexFromRTFD` to return changes.
        // So I need at least ONE attachment to be converted.
        
        // I'll use the PDFMetadataTests approach: create a PDF with metadata, 
        // because `extractLatexFromPDF` ALSO checks metadata.
        // The new strategy checks text content, but the old metadata checks are still there!
        
        return createPDFWithMetadata(subject: "TeXClipper:x^2")
    }
    
    func createPDFWithMetadata(subject: String) -> Data {
        let page = PDFPage()
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        var attrs = doc.documentAttributes ?? [:]
        attrs[PDFDocumentAttribute.subjectAttribute] = subject
        doc.documentAttributes = attrs
        return doc.dataRepresentation()!
    }
}
